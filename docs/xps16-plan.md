# Plan for the XPS, decided by the owner (2026-11-23)

Moved out of `CLAUDE.md` on 2026-11-24. `CLAUDE.md` has the hardware context (section 9) and the roadmap (section 10), and `xps16-checklist.md` has the checks to run on the machine.

None of this is implemented or tested, and the figures are the owner's notes, not measurements.

**First day, in order:**
1. In Windows: Dell Command Update for BIOS and firmware only, note the BIOS version, and run the F12 diagnostics.
2. In the BIOS: AHCI/NVMe storage, Secure Boot on, and custom charging between 50% and 80% (or Primarily AC).
3. Install Kinoite (Fedora 45) on a LUKS-encrypted disk.
4. Rebase to `base`, then to `xps16-da16260`.
5. Record a baseline in this repo: `fwupdmgr get-devices`, `lspci -nnk`, `dmesg`.
6. Validate s2idle suspend before touching the camera.

**System:**
- **Encryption:** LUKS, unlocked at the end with TPM and a PIN: `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes <dev>`, plus `rpm-ostree kargs --append=rd.luks.options=tpm2-device=auto`.
- **Secure Boot:** on from the start. Our own kernel modules are signed with the owner's MOK during the build.
- **Swap:** zram only, 16 GB, in `base`: `zram-size = min(ram / 4, 16384)` and `compression-algorithm = zstd`.
- **Hibernation:** ruled out. Suspend for breaks, power off at night.
- **Battery:** 80% charge limit, with `battery:desk` and `battery:travel` mise tasks.
- **Login:** Fedora 45 uses Plasma Login Manager (`plasmalogin.service`), not SDDM.
- **Claude and suspend:** mise tasks that run it under `systemd-inhibit --what=idle` by default, and `idle:sleep:handle-lid-switch` only on purpose.
- **OLED:** auto-hide panel, dark wallpaper, and the screen off after 2 to 3 minutes.
- **Hardware notes:** the 388H has 4 P, 8 E and 4 LP cores. The memory gives about 153 GB/s in theory. The SSD is the weak point: it can be replaced, and no BIOS setting speeds it up.

**Voice dictation, in Spanish:**
- Done on 2026-11-25 except for use by hand, directly with phase 2: see `status/xps16-da16260.md`. `mode` is `paste`, not `type`, and the NPU driver is Fedora's. What follows is the original plan.
- Voxtype built into `xps16-da16260`, with `language = "es"` and `mode = "type"`. It needs `ydotool`, and a KDE shortcut that runs `voxtype record toggle`.
- Phase 1 runs on the CPU with the `small` model.
- Phase 2 uses the NPU: a build with `--features openvino-whisper`, the OpenVINO GenAI SDK in `/usr/lib/openvino-genai`, and Intel's NPU driver, with `engine = "openvino"` and `device = "NPU"`.

**Icons:** the Katze Mono theme. It was built on 2026-11-24 and is described in `CLAUDE.md`, section 1; the plan it started from (Papirus glyphs, a per-user script) no longer applies.

**To confirm on the machine:**
- LVFS coverage for the DA16260.
- Intel's NPU driver, shipped as an Ubuntu `.deb`, loading on Fedora 45.
- The original repository of the IR driver (HritwikSinghal or acmodeu).
- Real drain in suspend and real SSD speed.
