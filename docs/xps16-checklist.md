# XPS 16 DA16260: what to check and what is still open

The working list of checks on the machine. `CLAUDE.md` has the roadmap
(section 10) and the hardware context (section 9), and `xps16-plan.md` the
owner's plan. What each check found goes in `status/xps16-da16260.md`: tick the
line here and put the result there.

Many open items come from other people's reports on this model, mostly on an
X7 358H, from the research of 2026-11-21. Reviewed on 2026-11-26.

## Baseline

- [x] DMI ids and `lsusb` (2026-11-26). The panel's EDID was decoded for the
      VRR trial (2026-11-25).
- [x] `intel_lpmd` and `thermald` enabled and active (2026-11-26).
- [x] ISH loads `ish_ptl` firmware (2026-11-25).
- [ ] The panel's sink OUI (needs root, debugfs). PSR status: PSR2 with Early
      Transport, Panel Replay not supported by the sink (2026-11-25). A second
      panel for this model (sink OUI `00:aa:01`) is not covered by the upstream
      Panel Replay quirk and is reported to run at about 5 fps until
      `xe.enable_panel_replay=0`.
- [ ] `HPDSensor`'s current value (needs root). It offers `MSHPD` and
      `IntelHPD`; xps-fedora sets `MSHPD` for the camera, and the camera works
      here as it is, so this is only for the record.

## Power and heat

- [x] thermald started with no error in ten boots in a row (2026-11-25 and 26).
- [ ] One cold boot (from power off, not a restart) with thermald running: the
      `katze-wait-sensors.conf` drop-in is for that case.
- [x] Power saver, balanced and performance each reach tuned and both
      handlers under `/sys/class/platform-profile/` (2026-11-26, on AC).
- [ ] `katze-xps-balanced-battery`, on battery.
- [ ] RAPL limits in each `dell-pc` mode, on AC and on battery, for both
      `intel-rapl` and `intel-rapl-mmio`. `mise run power` records them.
      Performance read PL1 41 W and PL2 65 W on AC and on battery (2026-11-25).
- [ ] Write PL1 and read it again after 1, 15 and 60 s, after a profile change
      and after unplugging: the firmware may overwrite it.
- [x] Governor and EPP in each profile (2026-11-26): `powersave` and `power`,
      `powersave` and `balance_performance`, `performance` and `performance`.
- [ ] One fixed benchmark in Balanced and in Performance. `katze-xps-performance` includes
      `throughput-performance`, which a Fedora thread ties to a tuned-ppd
      regression of about 10%.
- [ ] EPP `balance_performance` in `katze-xps-balanced-battery`, with its idle
      cost. One report on an XPS 16 358H: Chrome starts in half the time for
      0.17 W more. Low evidence.
- [ ] Idle watts on battery at 120 Hz and at 60 Hz. Add a refresh switch only
      if the saving is real.
- [x] Charge limits: 50 and 80, `charge_types` on `Custom` (2026-11-25).
- [x] `gputop` works with `xe`, without root (2026-11-25). `intel_gpu_top`,
      said not to support `xe`, was not tried.
- [x] `nvtop` 3.4.0 finds the Arc B390 on `xe` without root (2026-11-26, from
      a container): load, clock, video engines and memory. No temperature or
      power: `xe` registers no hwmon for this integrated GPU.

## Suspend and battery

- [x] s2idle of about 16 minutes with Secure Boot on, and short ones during
      face unlock (2026-11-25).
- [ ] One night suspended on battery, and how much it drained.
- [ ] Sound and both displays after a resume.
- [ ] Suspend while the camera is in use: the IPU7 stack is reported to abort
      it, and `camera.py` turns the camera off first.
- [ ] Dictation on the NPU after a suspend.

## Display

- [x] VRR: the panel can do 20 to 120 Hz, tried for one boot with an edited
      EDID (2026-11-25, `tests/xps16-vrr.sh`). Stock kernels do not see it, and
      `kernel-watch.yml` opens an issue when a kernel change could fix that.
- [x] An external 4K Dell monitor over USB-C at 60 Hz, with its hub and
      Ethernet, beside the panel at 120 Hz (2026-11-26).
- [ ] Glitches. If they show, the remedy is kernel arguments in
      `/usr/lib/bootc/kargs.d/` of the machine image, never `i915.*`. The only
      A/B test on an XPS 16 (one 358H, a patched 7.2.15) got a clean 120 Hz
      with `xe.enable_psr=0 xe.enable_panel_replay=0`, and about 20 Hz when
      scrolling with only Panel Replay off.
- [x] Two ambient light sensors, seen by `iio-sensor-proxy` (2026-11-26).
- [ ] Refresh rate after a resume, brightness keys over several boots,
      automatic brightness in use, and the Copilot key.
- [ ] The screen turning off after 3 minutes on AC and 2 on battery
      (PowerDevil defaults of the machine image).

## Sound

- [x] One card, `sof-soundwire`; the speakers play (2026-11-26).
- [x] The internal microphone picks up the room: mean -30 dB (2026-11-26).
- [ ] A headset, and booting with headphones plugged in (no sound in that case
      on an XPS 16, alsa-ucm-conf issue 833). If the microphone is silent, look
      at the BIOS first.

## Network

- [x] Wi-Fi on a Wi-Fi 5 access point, 5 GHz, 80 MHz (2026-11-26).
- [ ] Wi-Fi on a Wi-Fi 7 access point. Omarchy turns Wi-Fi 7 off on the XPS 14
      and 16 (`options iwlwifi disable_11be=Y`) for a broken receive path. If
      it stalls here, add that to `modprobe.d` of the machine image.
- [x] Incus containers: the first project container ran here, and reached the
      internet but not the host, the LAN or the tailnet (2026-11-26,
      `secrets-and-devbox.md`, section 8.3).
- [ ] An Incus VM (`--vm`), and IPv6 for instances.

## Video and applications

- [x] VA-API with ffmpeg: H.264, HEVC and AV1 encode, and H.264, HEVC, VP9
      and AV1 decode on the video engine; 4K60 AV1 at 373 fps (2026-11-26).
      Haruna uses the same libraries.
- [ ] Intel hardware decode and encode in Chrome, AV1 included (steps in
      `README.md`), and whether the browser flags of the machine image are
      needed at all: compare a real video with and without them.
- [ ] Haruna itself shows hardware decoding (its statistics overlay).
- [ ] Wayland screen sharing in a real call.
- [ ] Dictation by hand in Brave, Zed and Slack.

## Camera

- [x] The RGB camera on the stock kernel: works in the sensor's full mode only,
      upside down, which `camera.py` handles (2026-11-25).
- [ ] The camera from the image (`katze-camera.service` at login) in a real
      video call, and in Firefox and Flatpaks such as Slack.
- [ ] After a new kernel or libcamera: the picture is still the right way up.
      If Fedora's kernel starts to report the rotation
      (<https://bugzilla.redhat.com/show_bug.cgi?id=2563275>), remove
      `video-direction` from `camera.py`. `kernel-watch.yml` opens an issue
      when that bug leaves `NEW`.
- [ ] When Fedora 45 ships kernel 7.4 (expected around January 2027), check
      `CONFIG_VIDEO_INTEL_IPU6_IPU7` and repeat the camera test.
      `kernel-watch.yml` opens an issue when Fedora 45's updates have it.

## Face unlock

Works on the lock screen from the published image, also right after a suspend
(2026-11-25, README, "Face unlock"). Still to check:

- [ ] Another person is refused, and so is a printed photo.
- [ ] In the dark, and with glasses.
- [ ] A user with no face registered sees nothing new.
- [ ] The active-session check on the machine: another account, or a session
      that is not at the screen, gets "no" at once.
- [ ] From the security review: whether another process can write into the
      IPU7 capture buffers while `ir-camera` reads them (`mmap` the node as the
      user while the reader streams; if it works, copy each frame first).

The references it was weighed against:

- The `HIMX1092` entry in `ipu-bridge` is upstream since 7.3. Only the sensor
  driver is missing: `kernel-watch.yml` opens an issue when `VIDEO_HM1092`
  shows up in Linux master or the media tree's `next`.
- xps-fedora: patches `0031` to `0033`, `0038` and `0039`, a relay
  (`ir-relay`) and a udev rule; it uses Gaze.
- Omarchy pull request 15887 does it with Howdy; the camera lights only after
  the Copilot key.

## Decisions

- **Auto-boost: on hold** (2026-11-25). Under load on AC the package held a
  steady 31.6 W, below PL1, and the owner is content with that. If it comes
  back: a daemon that polls average load would be a fourth writer of the power
  limits, beside the firmware, thermald and tuned, and 40% average load means
  little on 4 P, 8 E and 4 LP cores. The alternative is `dell-pc` in
  `performance` on AC.
- **VRR: wait for the kernel** (2026-11-25). The panel gives 20 to 120 Hz only
  in DisplayID block 0x2b, which neither 7.3.4, master nor drm-tip reads, and
  the base EDID is marked as continuous frequency, so a range descriptor is
  enough. An EDID with one, through `drm.edid_firmware=`, worked for one boot
  (`docs/status/xps16-da16260.md`). Keeping it would need the file in
  `/usr/lib/firmware/edid`, the parameter in `/usr/lib/bootc/kargs.d/`, and an
  initramfs regenerated by the machine image, since `xe` starts in it: about
  240 MB more in every daily update unless it is built reproducibly, a boot
  that depends on our own dracut run, and an EDID that only fits this LG panel
  (product 0x07c5). Instead, `tests/check-kernel.sh` (weekly,
  `kernel-watch.yml`) looks in master and drm-tip for the parser reading that
  block, an EDID quirk for the panel, or a new Intel quirk for the DA16260, and
  opens one issue with the steps.
- **Speaker equalizer: open.** The speakers are said to sound weaker than on
  Windows. Omarchy ships a PipeWire EQ measured on the XPS 14 only.

## Sources

- Panel Replay quirk for the DA16260:
  <https://github.com/torvalds/linux/commit/cb8d155b0806>, and a fix observed
  on it: <https://github.com/torvalds/linux/commit/3659b6d90f98>
- Other commits cited for 7.4: <https://github.com/torvalds/linux/commit/2f4ffd14>,
  <https://github.com/torvalds/linux/commit/4fdb0342>
- intel-gfx threads:
  <http://www.mail-archive.com/intel-gfx@lists.freedesktop.org/msg384112.html>,
  <http://www.mail-archive.com/intel-gfx@lists.freedesktop.org/msg384123.html>
- Camera on the stock kernel: <https://bugzilla.redhat.com/show_bug.cgi?id=2563275>
- tuned-ppd performance:
  <https://discussion.fedoraproject.org/t/tuned-ppd-worsens-performance-and-efficiency-vs-power-profiles-daemon/199402>,
  <https://bugzilla.redhat.com/show_bug.cgi?id=2522083>
- Chromium's video flags:
  <https://chromium.googlesource.com/chromium/src.git/+show/lkgr/docs/gpu/vaapi.md>
- xps-fedora's findings: <https://github.com/onuralpszr/xps-fedora/blob/main/docs/findings.md>,
  and its power files under
  <https://github.com/onuralpszr/xps-fedora/blob/main/packages/dell-xps-ptl-config/>
- `intel_gpu_top` and `xe`: <https://www.mankier.com/1/intel_gpu_top>
- Omarchy (`basecamp/omarchy`): issues 11176 and 14174, pull request 15887
- <https://lkml.iu.edu/2607.2/08382.html>
