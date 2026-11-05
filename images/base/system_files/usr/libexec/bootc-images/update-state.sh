#!/usr/bin/env bash
# Records a downloaded update so the desktop can announce it. /run clears on reboot.
set -euo pipefail

STATE=/run/bootc-images/update-pending

version=$(bootc status --format=json | jq -r '.status.staged.image.version // empty')
[[ -n "$version" ]] || exit 0

mkdir -p "$(dirname "$STATE")"
# Write only when the version changes: every write shows a notification
if [[ ! -f "$STATE" || "$(cat "$STATE")" != "$version" ]]; then
  echo "$version" > "$STATE"
fi
