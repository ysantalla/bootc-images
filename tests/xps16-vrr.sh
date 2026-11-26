#!/usr/bin/env bash
# Tries VRR on the XPS's own panel, for ONE boot: the kernel gets a copy of the panel's EDID with the
# 20-120 Hz range written where Linux looks for it. Nothing is layered and ostree's entries are not changed:
# an extra GRUB entry in /boot/grub2/custom.cfg is picked once.
# Run on the XPS as the desktop user, from Konsole (sudo asks for the password). Files go to output/vrr.
#   tests/xps16-vrr.sh            makes the files and sets the next boot, only that one, to use them
#   tests/xps16-vrr.sh check      after the test boot: what the kernel and KWin see
#   tests/xps16-vrr.sh compare    PSR with VRR Never and Always, from debugfs; leaves VRR on Automatic
#   tests/xps16-vrr.sh undo       removes the files from /boot and the GRUB entry
# Results of 2026-11-25: docs/status/xps16-da16260.md. A kernel that reads the panel's own range makes this unneeded.
set -euo pipefail
script=$(readlink -f "$0")
cd "$(dirname "$script")/.."
mkdir -p output/vrr
cd output/vrr
edid=/sys/class/drm/card0-eDP-1/edid
name=katze-xps16-vrr.bin

make_files() {
  python3 -I - "$edid" "$name" <<'PY'
import sys
source, name = sys.argv[1:]
e = bytearray(open(source, "rb").read())
if len(e) != 256 or e[:8] != bytes.fromhex("00ffffffffffff00") or any(sum(e[i:i + 128]) % 256 for i in (0, 128)):
    sys.exit("unexpected EDID")
if e[8:12] != bytes.fromhex("30e4c507"):
    sys.exit("not the LG panel this was written for")
if any(e[72:90]) and e[72:76] != bytes.fromhex("000000fd"):
    sys.exit("the second descriptor is not empty any more")
# The range the panel itself gives, in its DisplayID Adaptive-Sync block (0x2b)
x, i, low, high = e[128:], 5, 0, 0
while i < 5 + x[2] and (x[i] or x[i + 2]):
    if x[i] == 0x2B:
        d = x[i + 3:i + 9]
        low, high = d[2], ((d[4] & 3) << 8 | d[3]) + 1
    i += 3 + x[i + 2]
if (low, high) != (20, 120):
    sys.exit(f"unexpected range {low}-{high}")
# Display range limits, "range limits only": 20-120 Hz, 30-256 kHz (+255 in byte 4), 860 MHz
e[72:90] = bytes([0, 0, 0, 0xFD, 0x08, low, high, 30, 1, 86, 1, 10]) + b" " * 6
e[127] = -sum(e[:127]) % 256
open(name, "wb").write(e)

# An extra initramfs with only that file (newc cpio)
def entry(path, mode, data=b"", ino=[0]):
    ino[0] += 1
    p = path.encode() + b"\0"
    f = (ino[0], mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(p), 0)
    head = b"070701" + b"".join(b"%08X" % v for v in f) + p
    return head + b"\0" * (-len(head) % 4) + data + b"\0" * (-len(data) % 4)
out = b""
for d in ("usr", "usr/lib", "usr/lib/firmware", "usr/lib/firmware/edid"):
    out += entry(d, 0o40755)
out += entry("usr/lib/firmware/edid/" + name, 0o100644, bytes(e)) + entry("TRAILER!!!", 0)
open("katze-vrr.img", "wb").write(out + b"\0" * (-len(out) % 512))
PY
}

case ${1-} in
"")
  make_files
  decoded=$(di-edid-decode "$name" 2>&1 || true)
  grep "Monitor ranges" <<<"$decoded" | grep -q "20-120 Hz" || { echo "The new EDID does not decode"; exit 1; }
  # A staged update renames the deployment at shutdown, and the test entry would point at nothing
  if ! rpm-ostree status --json | python3 -I -c 'import json, sys; sys.exit(any(d.get("staged") for d in json.load(sys.stdin)["deployments"]))'; then
    echo "An update is staged: reboot once normally first, then run this again"; exit 1
  fi
  # The booted entry's kernel, initramfs and options, from its BLS file
  ostree=$(grep -o 'ostree=[^ ]*' /proc/cmdline)
  entry=$(grep -l -- " $ostree " /boot/loader/entries/*.conf | head -1)
  [[ -n $entry ]] || { echo "Cannot find the booted entry"; exit 1; }
  linux=$(awk '$1 == "linux" { print $2 }' "$entry")
  initrd=$(awk '$1 == "initrd" { print $2 }' "$entry")
  options=$(sed -n 's/^options //p' "$entry")
  # bootupd's GRUB has no next_entry, but it sources custom.cfg after the BLS entries
  cat > custom.cfg <<CFG
# Katze: VRR test (vrr-test.sh). Picked once, when katze_vrr_once is set; vrr-test.sh undo removes this file.
menuentry 'Katze: VRR test (one boot)' --id katze-vrr {
  load_video
  linux $linux $options drm.edid_firmware=eDP-1:edid/$name
  initrd $initrd /boot/katze-vrr.img
}
if [ "\${katze_vrr_once}" ]; then
  set default=katze-vrr
  unset katze_vrr_once
  save_env katze_vrr_once
fi
CFG
  # bootc mounts /boot read-only: open it for the copy only
  sudo sh -c 'mount -o remount,rw /boot &&
    install -m0644 katze-vrr.img /boot/katze-vrr.img &&
    install -m0644 custom.cfg /boot/grub2/custom.cfg &&
    grub2-editenv /boot/grub2/grubenv set katze_vrr_once=1
    mount -o remount,ro /boot'
  sudo grep -q '^katze_vrr_once=1' /boot/grub2/grubenv || { echo "Could not set up the boot"; exit 1; }
  cat <<EOF

Ready. The next boot, and only that one, uses "Katze: VRR test (one boot)". Nothing to type.
Reboot now, before the update timer stages something. It asks for the disk PIN as always.
If the internal screen stays black: hold the power button and start again, which boots normally.
Once in, run: $script check, then $script compare
And afterwards: $script undo
EOF
  ;;
make) make_files ;;
check)
  grep -o 'drm.edid_firmware=[^ ]*' /proc/cmdline || echo "This boot does not use the new EDID"
  # sysfs reports a size of 0, which cmp -s trusts: read it through a pipe
  head -c 4096 "$edid" | cmp -s - "$name" && echo "Kernel: has the new EDID" || echo "Kernel: has the panel's own EDID"
  journalctl -k -b --no-pager -o cat -g 'EDID' | head || true
  kscreen-doctor -o | sed 's/\x1b\[[0-9;]*m//g' | awk '/^Output:/ { name = $3 } /Vrr:/ { print "KWin, " name ": " $0 }'
  ;;
undo)
  sudo sh -c 'mount -o remount,rw /boot &&
    rm -f /boot/katze-vrr.img /boot/grub2/custom.cfg &&
    grub2-editenv /boot/grub2/grubenv unset katze_vrr_once
    mount -o remount,ro /boot'
  echo "Removed from /boot, with the GRUB entry. The files in output/vrr are left."
  ;;
compare)
  # With VRR on, xe turns PSR off: that change shows VRR really reached the pipe
  d=/sys/kernel/debug/dri/0000:00:02.0
  sudo -v
  for policy in never always; do
    echo "== VRR $policy =="
    kscreen-doctor "output.eDP-1.vrrpolicy.$policy" >/dev/null
    sleep 4
    sudo cat "$d/eDP-1/vrr_range" || true
    sudo grep "PSR mode" "$d/eDP-1/i915_psr_status" || true
  done 2>&1 | tee compare.log
  kscreen-doctor output.eDP-1.vrrpolicy.automatic >/dev/null
  echo "VRR left on Automatic. Saved in output/vrr/compare.log"
  ;;
*) sed -n 2,9p "$script"; exit 2 ;;
esac
