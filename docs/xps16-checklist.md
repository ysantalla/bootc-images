# XPS 16 DA16260: what to check and what is still open

Tasks taken from the research of 2026-11-21 on Linux support for this model.
`CLAUDE.md` has the roadmap (section 10) and the hardware context (section 9),
and `xps16-plan.md` the owner's plan;
this file is the working list for the first days with the machine.

Nothing here was measured on this machine. The findings come from other
people's reports, mostly on an X7 358H, and were not checked again after
that date. Tick a line when it is done, and move what it found to `status/xps16-da16260.md`.

## Before installing

- [ ] Have a USB Ethernet adapter or a phone to tether: nobody has described
      the install path for this model, and Wi-Fi may not work in the installer.

## Baseline, once

Add these to the first-day baseline of `xps16-plan.md` (`fwupdmgr get-devices`,
`lspci -nnk`, `dmesg`):

- [ ] DMI ids, `lsusb`, and `edid-decode` of the panel.
- [ ] The panel's sink OUI and the PSR status from debugfs. A second panel for
      this model (sink OUI `00:aa:01`) is not covered by the upstream Panel
      Replay quirk and is reported to run at about 5 fps until
      `xe.enable_panel_replay=0`.
- [ ] `HPDSensor` from `/sys/class/firmware-attributes/dell-wmi-sysman/attributes/`.
      xps-fedora needs it set to `MSHPD` for the camera; whether the stock
      camera path needs it is unknown.
- [ ] `systemctl is-enabled intel_lpmd thermald`.
- [ ] `dmesg | grep -i ish`, and whether `ish_ptl` firmware is present. Intel
      ISH is said to need only firmware that linux-firmware already has.

## Power and heat

- [ ] thermald survives two or three cold boots (the `katze-wait-sensors.conf`
      drop-in), and each power profile reaches both handlers under
      `/sys/class/platform-profile/`.
- [ ] RAPL limits in each `dell-pc` mode, on AC and on battery, for both
      `intel-rapl` and `intel-rapl-mmio`. `mise run power` records them.
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
- [ ] `BAT0/charge_control_*`, `charge_types` and `PrimaryBattChargeCfg`,
      before writing the `battery:desk` and `battery:travel` tasks: the
      `dell-laptop` thresholds may only apply when `charge_types` is `Custom`.
- [x] `gputop` works with `xe`, without root (2026-11-25). `README.md` names
      it. `intel_gpu_top`, said not to support `xe`, was not tried.

## Display

- [ ] VRR: not detected on stock kernels up to 7.4-rc3, according to the notes.
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

- [ ] The RGB camera on the stock kernel. One Fedora bug shows a picture in
      qcam and Chrome on stock 7.2.13 with no extra modules, upside down, with
      a fix on its way upstream. xps-fedora reports raw nodes only.
- [ ] When Fedora 45 ships kernel 7.4 (expected around January 2027), check
      `CONFIG_VIDEO_INTEL_IPU6_IPU7` and repeat the camera test. The camera is
      the only reason to retest on 7.4.
- [ ] Suspend after using the camera: the IPU7 stack is reported to abort it.

## Decisions for the owner

- **Auto-boost.** A daemon that polls average load would be a fourth writer of
  the power limits, beside the firmware, thermald and tuned, and 40% average
  load means little on 4 P, 8 E and 4 LP cores. The alternative is `dell-pc`
  in `performance` on AC. Decide after the RAPL checks above.
- **VRR without a kernel patch.** An EDID with a range descriptor, through
  `drm.edid_firmware=`. Nobody has tried it.
- **Speaker equalizer.** The speakers are said to sound weaker than on
  Windows. Omarchy ships a PipeWire EQ measured on the XPS 14 only.

## For the IR face unlock (`xps-ir-face`)

References to audit, never to install from:

- The `HIMX1092` entry in `ipu-bridge` is upstream since 7.3. Only the sensor
  driver is missing.
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
