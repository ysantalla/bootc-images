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

mapfile -t apps < <(grep -vE '^\s*(#|$)' "$LIST")
if (( ${#apps[@]} > 0 )); then
  flatpak install --system --noninteractive --or-update flathub "${apps[@]}"
fi

echo "$sum" > "$STATE"
