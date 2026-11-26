# XPS 16 DA16260: what to check and what is still open

Tasks taken from the research of 2026-11-21 on Linux support for this model.
`CLAUDE.md` has the roadmap (section 10) and the hardware context (section 9),
and `xps16-plan.md` the owner's plan;
this file is the working list for the first days with the machine.

The open items come from other people's reports, mostly on an X7 358H, and
were not checked again after that date. The ticked ones were measured on this
machine, and what they found is in `status/xps16-da16260.md`. Tick a line when
it is done, and move what it found there.

## Before installing

- [x] Have a USB Ethernet adapter or a phone to tether (the install went through): nobody has described
      the install path for this model, and Wi-Fi may not work in the installer.

## Baseline, once

Add these to the first-day baseline of `xps16-plan.md` (`fwupdmgr get-devices`,
`lspci -nnk`, `dmesg`):

- [ ] DMI ids and `lsusb`. The panel's EDID was decoded for the VRR trial (2026-11-25).
- [ ] The panel's sink OUI. PSR status from debugfs: PSR2 with Early Transport, Panel Replay not supported by the sink (2026-11-25). A second panel for
      this model (sink OUI `00:aa:01`) is not covered by the upstream Panel
      Replay quirk and is reported to run at about 5 fps until
      `xe.enable_panel_replay=0`.
- [ ] `HPDSensor` from `/sys/class/firmware-attributes/dell-wmi-sysman/attributes/`.
      xps-fedora needs it set to `MSHPD` for the camera; whether the stock
      camera path needs it is unknown.
- [ ] `systemctl is-enabled intel_lpmd thermald`.
- [x] `dmesg | grep -i ish`, and whether `ish_ptl` firmware is present: it loads (2026-11-25). Intel
      ISH is said to need only firmware that linux-firmware already has.

## Power and heat

- [ ] thermald survives two or three cold boots (the `katze-wait-sensors.conf`
      drop-in; one so far), and each power profile reaches both handlers under
      `/sys/class/platform-profile/` (performance and balanced do).
- [ ] RAPL limits in each `dell-pc` mode, on AC and on battery, for both
      `intel-rapl` and `intel-rapl-mmio`. `mise run power` records them.
      Performance read PL1 41 W and PL2 65 W on AC and on battery (2026-11-25).
- [ ] Write PL1 and read it again after 1, 15 and 60 s, after a profile change
      and after unplugging: the firmware may overwrite it.
- [ ] Governor and EPP in each profile, and one fixed benchmark in Balanced and
      in Performance. `katze-xps-performance` includes `throughput-performance`,
      which a Fedora thread ties to a tuned-ppd regression of about 10%.
- [ ] EPP `balance_performance` in `katze-xps-balanced-battery`, with its idle
      cost. One report on an XPS 16 358H: Chrome starts in half the time for
      0.17 W more. Low evidence.
- [ ] Idle watts on battery at 120 Hz and at 60 Hz. Add a refresh switch only
      if the saving is real.
- [x] `BAT0/charge_control_*`, `charge_types` and `PrimaryBattChargeCfg`
      (50 and 80 with `charge_types` on `Custom`, 2026-11-25),
      before writing the `battery:desk` and `battery:travel` tasks: the
      `dell-laptop` thresholds may only apply when `charge_types` is `Custom`.
- [x] `gputop` works with `xe`, without root (2026-11-25). `README.md` names
      it. `intel_gpu_top`, said not to support `xe`, was not tried.
- [x] `nvtop` 3.4.0 finds the Arc B390 on `xe` without root (2026-11-26, from
      a container): load, clock, video engines and memory. No temperature or
      power: `xe` registers no hwmon for this integrated GPU.

## Display

- [x] VRR: the panel can do 20 to 120 Hz, tried for one boot with an edited
      EDID (2026-11-25, `tests/xps16-vrr.sh`). Stock kernels do not see it.
      `kernel-watch.yml` opens an issue when a kernel change could fix that.
- [ ] Glitches. If they show, the remedy is kernel arguments in
      `/usr/lib/bootc/kargs.d/` of the machine image, never `i915.*`. The only
      A/B test on an XPS 16 (one 358H, a patched 7.2.15) got a clean 120 Hz
      with `xe.enable_psr=0 xe.enable_panel_replay=0`, and about 20 Hz when
      scrolling with only Panel Replay off.
- [ ] Refresh rate after resume, a USB-C monitor or dock, brightness keys over
      several boots, automatic brightness, and the Copilot key.

## Sound

- [ ] `/proc/asound/cards`, speakers, internal microphone, a headset, and
      booting with headphones plugged in (no sound in that case on an XPS 16,
      alsa-ucm-conf issue 833). If the microphone is silent, look at the BIOS
      first.

## Network

- [ ] Wi-Fi on a Wi-Fi 7 access point. Omarchy turns Wi-Fi 7 off on the XPS 14
      and 16 (`options iwlwifi disable_11be=Y`) for a broken receive path. If
      it stalls here, add that to `modprobe.d` of the machine image.

## Camera

- [x] The RGB camera on the stock kernel: works in the sensor's full mode only,
      upside down. See `docs/status/xps16-da16260.md`.
- [ ] After a new kernel or libcamera: the picture is still the right way up.
      If Fedora's kernel starts to report the rotation
      (<https://bugzilla.redhat.com/show_bug.cgi?id=2563275>), remove
      `video-direction` from `camera.py`. `kernel-watch.yml` opens an issue
      when that bug leaves `NEW`.
- [ ] When Fedora 45 ships kernel 7.4 (expected around January 2027), check
      `CONFIG_VIDEO_INTEL_IPU6_IPU7` and repeat the camera test. The camera is
      the only reason to retest on 7.4. `kernel-watch.yml` opens an issue when
      Fedora 45's updates have it (7.3.5 on 2026-11-25).
- [ ] Suspend after using the camera: the IPU7 stack is reported to abort it.

## Decisions for the owner

- **Auto-boost.** A daemon that polls average load would be a fourth writer of
  the power limits, beside the firmware, thermald and tuned, and 40% average
  load means little on 4 P, 8 E and 4 LP cores. The alternative is `dell-pc`
  in `performance` on AC. Decide after the RAPL checks above.
- **VRR without a kernel patch.** Decided on 2026-11-25: wait for the kernel.
  The panel gives 20 to 120 Hz only in DisplayID block 0x2b, which neither
  7.3.4, master nor drm-tip reads, and the base EDID is marked as continuous
  frequency, so a range descriptor is enough. An EDID with one, through
  `drm.edid_firmware=`, worked for one boot (`docs/status/xps16-da16260.md`).
  Keeping it would need the file in `/usr/lib/firmware/edid`, the parameter
  in `/usr/lib/bootc/kargs.d/`, and an initramfs regenerated by the machine
  image, since `xe` starts in it: about 240 MB more in every daily update
  unless it is built reproducibly, a boot that depends on our own dracut run,
  and an EDID that only fits this LG panel (product 0x07c5). Instead,
  `tests/check-kernel.sh` (weekly, `kernel-watch.yml`) looks in master and
  drm-tip for the parser reading that block, an EDID quirk for the panel, or
  a new Intel quirk for the DA16260, and opens one issue with the steps.
- **Speaker equalizer.** The speakers are said to sound weaker than on
  Windows. Omarchy ships a PipeWire EQ measured on the XPS 14 only.

## For the IR face unlock (`xps-ir-face`)

Done on 2026-11-25 with our own driver, reader and `katze-face` (README, "Face unlock"), and it unlocks the lock screen from the published image, also right after a suspend. Still to check: other people, a printed photo, the dark and glasses. The references it was weighed against:

- The `HIMX1092` entry in `ipu-bridge` is upstream since 7.3. Only the sensor
  driver is missing: `kernel-watch.yml` opens an issue when `VIDEO_HM1092`
  shows up in Linux master or the media tree's `next`.
- xps-fedora: patches `0031` to `0033`, `0038` and `0039`, a relay
  (`ir-relay`) and a udev rule; it uses Gaze.
- Omarchy pull request 15887 does it with Howdy; the camera lights only after
  the Copilot key.

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
