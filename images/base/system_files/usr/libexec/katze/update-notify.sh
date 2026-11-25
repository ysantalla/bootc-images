#!/usr/bin/env bash
# Tells the logged-in user that an update is ready. Runs as the user, never reboots by itself.
set -euo pipefail

version=$(cat /run/katze/update-pending)
# What it changes, when the build said so (update-state.sh)
changes=$(cat /run/katze/update-changes 2>/dev/null || true)
body="Version $version will be applied on the next restart."
[[ -n $changes ]] && body+=$'\n\n'"$changes"

action=$(notify-send --app-name="System update" --icon=system-software-update \
  --expire-time=0 --action=reboot="Restart now" \
  "Update ready" "$body")

# Ask Plasma, so apps with unsaved work can object. Plain reboot only without Plasma.
if [[ "$action" == reboot ]]; then
  busctl --user call org.kde.Shutdown /Shutdown org.kde.Shutdown logoutAndReboot \
    || systemctl reboot
fi
