#!/usr/bin/python3 -I
"""Offers the internal camera to applications as one PipeWire camera.

libcamera aborts when it is asked for 1080p or less on this machine, because the sensor's
1928x1088 mode does not work behind Intel's CVS chip. This process always asks for 1440p, which
uses the sensor's full mode, has the GPU turn the picture over (the sensor is mounted upside
down) and scale it to 1080p. The camera is on only while an application uses it, in a process of
its own: libcamera 0.7.2 leaves two threads and a GPU buffer behind each time, and can abort.
"""

import fcntl
import os
import signal
import subprocess
import sys
import threading

import gi

gi.require_version("GLibUnix", "2.0")
gi.require_version("Gst", "1.0")
gi.require_version("GstApp", "1.0")
gi.require_version("Wp", "0.5")
from gi.repository import Gio, GLib, GLibUnix, GObject, Gst, GstApp, Wp  # noqa: E402, F401

NAME = "katze-camera"
WIDTH, HEIGHT = 1920, 1080
# YUY2 has one plane. Chrome 158's video process crashed with NV12, which PipeWire splits in two.
FRAME_BYTES = WIDTH * HEIGHT * 2
CAPS = f"video/x-raw,format=YUY2,width={WIDTH},height={HEIGHT},framerate=30/1"
OUTPUT = (
    f'appsrc name=frames is-live=true format=time do-timestamp=true max-buffers=2 leaky-type=downstream caps="{CAPS}" '
    "! pipewiresink mode=provide sync=false async=false "
    f'stream-properties="props,media.class=Video/Source,media.role=Camera,node.name={NAME},node.description=Camera"'
)
CAMERA = (
    # The colour sensor's ACPI name: the infrared one, LNK0, could be a camera to libcamera too
    r"/usr/bin/gst-launch-1.0 -q -e libcamerasrc camera-name=\\_SB_.LNK1 ! "
    "video/x-raw,format=RGBx,width=2560,height=1440 "
    "! queue max-size-buffers=2 leaky=downstream "
    # If a kernel starts to report that the sensor is upside down, libcamera may turn it itself:
    # then remove video-direction.
    f"! vapostproc video-direction=180 ! video/x-raw,format=YUY2,width={WIDTH},height={HEIGHT} ! fdsink fd=1 sync=false"
).split()
# A new consumer makes its node go running, idle and running again
STOP_DELAY_MS = 1500
RETRY_S = 2
STOP_LIMIT_S = 3


class Relay:
    def __init__(self):
        self.loop = GLib.MainLoop()
        self.status = 0
        self.camera = None
        self.wanted = False
        self.sleeping = False
        self.stop_timer = 0
        self.retry_timer = 0
        self.inhibitor = None

        self.output = Gst.parse_launch(OUTPUT)
        self.frames = self.output.get_by_name("frames")
        bus = self.output.get_bus()
        bus.add_signal_watch()
        bus.connect("message::error", self.on_output_error)

        self.core = Wp.Core.new(None, None, None)
        GObject.Object.connect(self.core, "disconnected", lambda *_: self.fail("PipeWire went away"))
        self.nodes = Wp.ObjectManager.new()
        interest = Wp.ObjectInterest.new_type(Wp.Node)
        interest.add_constraint(
            Wp.ConstraintType.PW_PROPERTY, "node.name", Wp.ConstraintVerb.EQUALS, GLib.Variant("s", NAME)
        )
        self.nodes.add_interest_full(interest)
        self.nodes.request_object_features(Wp.Node, Wp.ProxyFeatures.PIPEWIRE_OBJECT_FEATURES_MINIMAL)
        self.nodes.connect("object-added", self.on_node)

    def run(self):
        self.core.install_object_manager(self.nodes)
        if not self.core.connect():
            sys.exit("cannot connect to PipeWire")
        self.watch_sleep()
        self.output.set_state(Gst.State.PLAYING)
        self.push_black()
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.loop.quit)
        self.loop.run()
        self.stop()
        self.output.set_state(Gst.State.NULL)
        return self.status

    def fail(self, why):
        print(why, file=sys.stderr, flush=True)
        self.status = 1
        self.loop.quit()

    def on_output_error(self, _bus, message):
        self.fail(f"virtual camera: {message.parse_error()[0].message}")

    # The virtual camera: PipeWire says whether an application is using it

    def on_node(self, _nodes, node):
        node.connect("state-changed", lambda _node, _old, new: self.on_state(new))
        self.on_state(node.get_state()[0])

    def on_state(self, state):
        self.wanted = state == Wp.NodeState.RUNNING
        if self.wanted:
            self.cancel("stop_timer")
            self.start()
        elif self.camera and not self.stop_timer:
            self.stop_timer = GLib.timeout_add(STOP_DELAY_MS, self.on_stop_timer)

    def on_stop_timer(self):
        self.stop_timer = 0
        self.stop()
        return GLib.SOURCE_REMOVE

    def cancel(self, timer):
        if getattr(self, timer):
            GLib.source_remove(getattr(self, timer))
            setattr(self, timer, 0)

    # The real camera

    def start(self):
        if self.camera or self.sleeping or self.retry_timer:
            return
        print("camera on", flush=True)
        self.camera = subprocess.Popen(CAMERA, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, bufsize=0)
        fcntl.fcntl(self.camera.stdout, fcntl.F_SETPIPE_SZ, 1 << 20)
        self.reader = threading.Thread(target=self.read_frames, args=(self.camera,), daemon=True)
        self.reader.start()

    def read_frames(self, camera):
        while True:
            frame = bytearray(FRAME_BYTES)
            view, done = memoryview(frame), 0
            while done < FRAME_BYTES:
                count = camera.stdout.readinto(view[done:])
                if not count:
                    GLib.idle_add(self.on_camera_end, camera)
                    return
                done += count
            self.frames.push_buffer(Gst.Buffer.new_wrapped(bytes(frame)))

    def on_camera_end(self, camera):
        if camera is self.camera:  # it ended by itself
            print("the camera stopped by itself", file=sys.stderr, flush=True)
            self.stop()
            self.retry_timer = GLib.timeout_add_seconds(RETRY_S, self.on_retry_timer)
        return GLib.SOURCE_REMOVE

    def on_retry_timer(self):
        self.retry_timer = 0
        if self.wanted:
            self.start()
        return GLib.SOURCE_REMOVE

    def stop(self):
        self.cancel("stop_timer")
        self.cancel("retry_timer")
        if not self.camera:
            return
        camera, self.camera = self.camera, None
        camera.send_signal(signal.SIGINT)
        try:
            camera.wait(STOP_LIMIT_S)
        except subprocess.TimeoutExpired:
            camera.kill()
            camera.wait()
        self.reader.join()
        camera.stdout.close()
        self.push_black()
        print("camera off", flush=True)

    def push_black(self):
        self.frames.push_buffer(Gst.Buffer.new_wrapped(b"\x10\x80" * (FRAME_BYTES // 2)))

    # The kernel's camera driver refuses to suspend while the camera is on

    def watch_sleep(self):
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
            self.logind = Gio.DBusProxy.new_sync(
                self.bus,
                Gio.DBusProxyFlags.DO_NOT_LOAD_PROPERTIES,
                None,
                "org.freedesktop.login1",
                "/org/freedesktop/login1",
                "org.freedesktop.login1.Manager",
            )
        except GLib.Error as error:
            print(f"cannot watch for suspend: {error.message}", file=sys.stderr, flush=True)
            return
        self.logind.connect("g-signal", self.on_logind)
        self.inhibit_sleep()

    def inhibit_sleep(self):
        try:
            reply, descriptors = self.logind.call_with_unix_fd_list_sync(
                "Inhibit",
                GLib.Variant("(ssss)", ("sleep", "Katze", "Turn the camera off first", "delay")),
                Gio.DBusCallFlags.NONE,
                -1,
                None,
                None,
            )
            self.inhibitor = descriptors.get(reply.unpack()[0])
        except GLib.Error as error:
            print(f"cannot delay suspend: {error.message}", file=sys.stderr, flush=True)

    def on_logind(self, _proxy, _sender, signal, parameters):
        if signal != "PrepareForSleep":
            return
        self.sleeping = parameters.unpack()[0]
        if self.sleeping:
            self.stop()
            if self.inhibitor is not None:
                os.close(self.inhibitor)
                self.inhibitor = None
        else:
            self.inhibit_sleep()
            if self.wanted:
                self.start()


if __name__ == "__main__":
    Gst.init(None)
    Wp.init(Wp.InitFlags.ALL)
    sys.exit(Relay().run())
