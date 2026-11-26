#!/usr/bin/env bash
# Looks for kernel and Fedora changes that the XPS 16 waits for. Each subject has a key:
#   vrr       the panel (LG, product 0x07c5) gives its 20-120 Hz range only in DisplayID block 0x2b
#             (Adaptive-Sync), which the kernel does not read, so KWin says "incapable" (2026-11-25).
#   hm1092    the infrared camera's sensor has no driver upstream; the image builds its own (module.yml).
#   linux-7.4 Fedora 45's kernel reaches 7.4, with IPU7 in the IPU6 driver: retest the camera.
#   rotation  Fedora bug 2563275, the internal camera upside down; camera.py turns it over.
# Without arguments: one line per subject that moved, "<key><TAB><where><TAB><what><TAB><URL>", and nothing
# when none did. A failed download fails the script. `title <key>` and `steps <key>` print the issue's text.
set -euo pipefail

linux="master https://raw.githubusercontent.com/torvalds/linux/master"
drm="drm-tip https://gitlab.freedesktop.org/drm/tip/-/raw/drm-tip"
media="media-next https://gitlab.freedesktop.org/linux-media/media-committers/-/raw/next"
bug=2563275

title() {
  case $1 in
  vrr) echo "A kernel change may give the XPS 16's panel VRR" ;;
  hm1092) echo "The XPS 16's infrared sensor (HM1092) has a driver upstream" ;;
  linux-7.4) echo "Fedora 45 ships Linux 7.4: retest the XPS 16's camera" ;;
  rotation) echo "Fedora bug $bug (camera upside down) has moved" ;;
  *) return 1 ;;
  esac
}

steps() {
  case $1 in
  vrr)
    echo "1. Read the change, and find the first release that has it (\`git tag --contains <commit>\`)."
    echo "2. Wait for Fedora 45's kernel to reach that release: it comes in the daily build, with nothing to change here."
    echo "3. On the XPS, after a normal boot of that image: \`kscreen-doctor -o\` should show eDP-1 with \`Vrr:\` other than \`incapable\`."
    echo "   Then \`tests/xps16-vrr.sh compare\` (from Konsole) checks the range and PSR, and leaves VRR on Automatic."
    echo "4. Record it in \`docs/status/xps16-da16260.md\`, see \`docs/xps16-checklist.md\` (\"VRR\"), and close this issue."
    ;;
  hm1092)
    echo "1. Compare it with ours (\`images/xps16-da16260/build_files/hm1092/\`, its README has the audit and our five changes),"
    echo "   above all the CAP_SYS_RAWIO check, which the lock screen's face unlock relies on."
    echo "2. Find the first release that has it, and wait for Fedora 45's kernel to reach it, with \`CONFIG_VIDEO_HM1092\` enabled."
    echo "3. Then the image can drop its own module, \`module.yml\` and the module key: a change that touches Secure Boot, so plan it with the owner."
    ;;
  linux-7.4)
    echo "1. Check \`CONFIG_VIDEO_INTEL_IPU6_IPU7\` (or the name it took) in the image's \`/usr/lib/modules/*/config\`."
    echo "2. On the XPS: the camera test of \`docs/xps16-checklist.md\` (\"Camera\"): 1080p and smaller modes, the picture's direction,"
    echo "   \`katze-camera.service\`, a suspend after using the camera, and the infrared camera with \`hm1092\`."
    echo "3. The other 7.4 items in \`CLAUDE.md\`, section 9: Intelligent Bias Control v3 and GPU cold reset recovery."
    echo "4. Record it in \`docs/status/xps16-da16260.md\` and close this issue."
    ;;
  rotation)
    echo "1. Read the bug. If Fedora's kernel reports the rotation, the picture of \`camera.py\` will be upside down once it arrives."
    echo "2. On the image with that kernel: \`cam -l\` shows the rotation; remove \`video-direction\` from \`camera.py\` in the same change."
    echo "3. Record it in \`docs/status/xps16-da16260.md\` and close this issue."
    ;;
  *) return 1 ;;
  esac
}

case ${1-} in
title | steps) "$1" "$2"; exit ;;
"") ;;
*) sed -n 2,9p "$0"; exit 2 ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
get() { # get <tree> <path>: the file's local copy
  local name=${1%% *} base=${1#* } out
  out="$tmp/$name-${2//\//_}"
  curl -fsSL --retry 3 -o "$out" "$base/$2"
  echo "$out"
}
url() { echo "${1#* }/$2"; }
found() { printf '%s\t%s\t%s\t%s\n' "$@"; }

# vrr: the parser reads the Adaptive-Sync block (no such words or 0x2b tag on 2026-11-25), an EDID quirk
# for the panel, or a second Intel quirk for the DA16260 (subsystem 1028:0dba; the first disables Panel Replay)
for tree in "$linux" "$drm"; do
  edid=$(get "$tree" drivers/gpu/drm/drm_edid.c)
  displayid=$(get "$tree" drivers/gpu/drm/drm_displayid_internal.h)
  quirks=$(get "$tree" drivers/gpu/drm/i915/display/intel_quirks.c)
  if grep -q -i -E 'adaptive[ _-]?sync' "$edid" "$displayid" ||
    grep -q -E '#define[[:space:]]+DATA_BLOCK_2_[A-Z0-9_]+[[:space:]]+0x2[bB]' "$displayid"; then
    found vrr "${tree%% *}" "the EDID parser reads DisplayID's Adaptive-Sync block" "$(url "$tree" drivers/gpu/drm/drm_edid.c)"
  fi
  if grep -q -E "EDID_QUIRK\('L', 'G', 'D', (0x0?7[cC]5|1989)\b" "$edid"; then
    found vrr "${tree%% *}" "an EDID quirk for the panel, LGD 0x07c5" "$(url "$tree" drivers/gpu/drm/drm_edid.c)"
  fi
  if (($(grep -c -i 'subsystem_device = 0x0dba' "$quirks") > 1)); then
    found vrr "${tree%% *}" "a new Intel quirk for the DA16260" "$(url "$tree" drivers/gpu/drm/i915/display/intel_quirks.c)"
  fi
done

# hm1092: a sensor driver in Linux or in the media tree's next branch, where it would land first
for tree in "$linux" "$media"; do
  if grep -q -E '^config VIDEO_HM1092\b' "$(get "$tree" drivers/media/i2c/Kconfig)"; then
    found hm1092 "${tree%% *}" "drivers/media/i2c has VIDEO_HM1092" "$(url "$tree" drivers/media/i2c/Kconfig)"
  fi
done

# linux-7.4: the kernel in Fedora 45's updates, which the daily build takes
kernel=$(curl -fsSL --retry 3 https://mdapi.fedoraproject.org/f45-updates/pkg/kernel |
  python3 -I -c 'import json, sys; print(json.load(sys.stdin)["version"])')
[[ $kernel =~ ^[0-9]+\.[0-9]+ ]] || { echo "cannot read Fedora 45's kernel: '$kernel'" >&2; exit 1; }
if [[ $(printf '%s\n' 7.4 "$kernel" | sort -V | head -1) == 7.4 ]]; then
  found linux-7.4 fedora-45 "kernel $kernel in updates" "https://packages.fedoraproject.org/pkgs/kernel/kernel/"
fi

# rotation: the bug leaves NEW or ASSIGNED (it was NEW on 2026-11-25)
status=$(curl -fsSL --retry 3 "https://bugzilla.redhat.com/rest/bug/$bug?include_fields=status,resolution" |
  python3 -I -c 'import json, sys; b = json.load(sys.stdin)["bugs"][0]; print(" ".join(filter(None, (b["status"], b["resolution"]))))')
[[ -n $status ]] || { echo "cannot read bug $bug" >&2; exit 1; }
if [[ $status != NEW && $status != ASSIGNED ]]; then
  found rotation bugzilla "status $status" "https://bugzilla.redhat.com/show_bug.cgi?id=$bug"
fi
