#!/usr/bin/env bash
# Tells the logged-in user that an update is ready. Runs as the user, never reboots by itself.
set -euo pipefail

version=$(cat /run/bootc-images/update-pending)

action=$(notify-send --app-name="System update" --icon=system-software-update \
  --expire-time=0 --action=reboot="Restart now" \
  "Update ready" "Version $version will be applied on the next restart.")

# Ask Plasma, so apps with unsaved work can object. Plain reboot only without Plasma.
if [[ "$action" == reboot ]]; then
  busctl --user call org.kde.Shutdown /Shutdown org.kde.Shutdown logoutAndReboot \
    || systemctl reboot
fi
