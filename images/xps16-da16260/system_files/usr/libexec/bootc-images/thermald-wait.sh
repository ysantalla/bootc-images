#!/usr/bin/env bash
# Runs before thermald: waits up to 30 s for the sensors its adaptive mode needs.
# It never fails, so thermald starts anyway when they do not appear.
set -euo pipefail

# Left by an earlier start that gave up on adaptive mode
rm -f /run/thermald/ignore_adaptive

for _ in {1..60}; do
  if [[ -e /sys/class/powercap/intel-rapl:0 && -e /sys/devices/platform/coretemp.0 ]] &&
    grep -qx TCPU /sys/class/thermal/thermal_zone*/type 2>/dev/null; then
    exit 0
  fi
  sleep 0.5
done
echo "Sensors not ready after 30 s, starting thermald anyway" >&2
