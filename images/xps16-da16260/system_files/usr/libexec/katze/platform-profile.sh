#!/usr/bin/env bash
# Sets Dell's thermal mode and Intel's SoC power slider, each by its own handler.
# The legacy /sys/firmware/acpi/platform_profile only offers what both share,
# so tuned's power saver request reaches neither of them.
# Usage: platform-profile.sh <dell-pc profile> <SoC Power Slider profile>
# Adapted from onuralpszr/xps-fedora (dell-xps-ptl-config, commit 98e8400).
set -euo pipefail

root=${PLATFORM_PROFILE_DIR:-/sys/class/platform-profile}

set_handler() { # set_handler <handler name> <profile>
  local name=$1 want=$2 handler
  for handler in "$root"/*; do
    [[ -r $handler/name && $(<"$handler/name") == "$name" ]] || continue
    if [[ " $(<"$handler/choices") " == *" $want "* ]]; then
      echo "$want" >"$handler/profile"
    else
      echo "$name has no '$want' (choices: $(<"$handler/choices"))" >&2
    fi
  done
}

set_handler dell-pc "${1:?dell-pc profile}"
set_handler "SoC Power Slider" "${2:?SoC Power Slider profile}"
