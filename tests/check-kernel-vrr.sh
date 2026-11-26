#!/usr/bin/env bash
# Looks for kernel changes that could give the XPS 16's panel VRR without the EDID that tests/xps16-vrr.sh
# writes. On 2026-11-25 the panel (LG, product 0x07c5) gave its 20-120 Hz range only in DisplayID block
# 0x2b (Adaptive-Sync), which the kernel does not read, so KWin said "incapable".
# Reads Linux master and drm-tip, where display changes land first. Prints one line per sign found,
# "<tree> <what> <file URL>", and nothing when there is none. A failed download fails the script.
set -euo pipefail

trees=(
  "master https://raw.githubusercontent.com/torvalds/linux/master"
  "drm-tip https://gitlab.freedesktop.org/drm/tip/-/raw/drm-tip"
)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for tree in "${trees[@]}"; do
  name=${tree%% *} base=${tree#* }
  get() { curl -fsSL --retry 3 -o "$tmp/$name-$(basename "$1")" "$base/$1"; echo "$tmp/$name-$(basename "$1")"; }
  edid=$(get drivers/gpu/drm/drm_edid.c)
  displayid=$(get drivers/gpu/drm/drm_displayid_internal.h)
  quirks=$(get drivers/gpu/drm/i915/display/intel_quirks.c)

  # The parser reads the Adaptive-Sync block (none of these words or a 0x2b tag existed on 2026-11-25)
  if grep -q -i -E 'adaptive[ _-]?sync' "$edid" "$displayid" ||
    grep -q -E '#define[[:space:]]+DATA_BLOCK_2_[A-Z0-9_]+[[:space:]]+0x2[bB]' "$displayid"; then
    echo "$name DisplayID-Adaptive-Sync-block $base/drivers/gpu/drm/drm_edid.c"
  fi
  # An EDID quirk for this panel
  if grep -q -E "EDID_QUIRK\('L', 'G', 'D', (0x0?7[cC]5|1989)\b" "$edid"; then
    echo "$name EDID-quirk-for-LGD-0x07c5 $base/drivers/gpu/drm/drm_edid.c"
  fi
  # A second Intel quirk for the DA16260 (subsystem 1028:0dba); the first disables Panel Replay
  if (($(grep -c -i 'subsystem_device = 0x0dba' "$quirks") > 1)); then
    echo "$name new-Intel-quirk-for-DA16260 $base/drivers/gpu/drm/i915/display/intel_quirks.c"
  fi
done
