#!/usr/bin/env bash
# Installs the image's launchers for Flatpak apps into the user's applications directory.
# Flatpak's own launchers are generated at install time without custom arguments, and
# they come before /usr/share in XDG_DATA_DIRS, so only the user's directory can override them.
# Entries without our marker belong to the user and are never replaced.
set -euo pipefail

SRC=/usr/share/bootc-images/applications
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
MARKER=X-Bootc-Images-Managed=true

mkdir -p "$DEST"
for src in "$SRC"/*.desktop; do
  dest="$DEST/$(basename "$src")"
  if [[ -e "$dest" ]] && ! grep -qx "$MARKER" "$dest"; then
    continue
  fi
  cmp -s "$src" "$dest" || install -m 0644 "$src" "$dest"
done
