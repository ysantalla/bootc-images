#!/usr/bin/env bash
# Records a downloaded update so the desktop can announce it. /run clears on reboot.
set -euo pipefail

STATE=/run/katze/update-pending
CHANGES=/run/katze/update-changes

version=$(bootc status --format=json | jq -r '.status.staged.image.version // empty')
[[ -n "$version" ]] || exit 0

mkdir -p "$(dirname "$STATE")"
# Write only when the version changes: every write shows a notification
if [[ ! -f "$STATE" || "$(cat "$STATE")" != "$version" ]]; then
  # What the new image changes, from the change list each build carries. Written first:
  # the notification starts when the version file appears. Never worth failing the update for.
  staged=$(rpm-ostree status --json | jq -r '.deployments[] | select(.staged == true)
    | "/ostree/deploy/\(.osname)/deploy/\(.checksum).\(.serial)"' | head -1) || staged=
  /usr/libexec/katze/update-changes.sh /usr/share/katze/changelog "$staged/usr/share/katze/changelog" \
    > "$CHANGES" 2>/dev/null || : > "$CHANGES"
  echo "$version" > "$STATE"
fi
