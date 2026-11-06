#!/usr/bin/env bash
# Installs or updates the Flatpaks listed in the image.
# Only runs when the list changed. Never uninstalls anything.
set -euo pipefail

LIST=/usr/share/bootc-images/flatpaks.list
STATE=/var/lib/bootc-images/flatpaks.sha256

mkdir -p "$(dirname "$STATE")"
sum=$(sha256sum "$LIST" | cut -d' ' -f1)
if [[ -f "$STATE" && "$(cat "$STATE")" == "$sum" ]]; then
  exit 0
fi

flatpak remote-add --system --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
# A stock install may already have this remote, disabled or filtered
flatpak remote-modify --system --enable --no-filter flathub

mapfile -t apps < <(grep -vE '^\s*(#|$)' "$LIST")
# One at a time, so a bad ID does not block the others. The list counts as done only if all succeed.
failed=0
for app in "${apps[@]}"; do
  flatpak install --system --noninteractive --or-update flathub "$app" || failed=1
done
(( failed == 0 ))

echo "$sum" > "$STATE"
