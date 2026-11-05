#!/usr/bin/env bash
# Warns the logged-in user when the running image is old, which means updates stopped arriving:
# a failed or disabled CI build, downloads always skipped, or a machine left on a rollback.
set -euo pipefail

MAX_DAYS=14

built=$(cat /usr/share/bootc-images/build-time)
days=$(( ($(date +%s) - built) / 86400 ))

if (( days > MAX_DAYS )); then
  notify-send --app-name="System update" --icon=dialog-warning \
    "System image is out of date" "This image was built $days days ago. Check 'bootc status' and the GitHub Actions builds."
fi
