#!/usr/bin/env bash
# The owner's Plasma style, with custom taskbar indicators, as the default for new users.
# Source: github.com/ysantalla/plasma-tips, pinned to a commit. To update, change the commit here.
set -euxo pipefail

THEME_COMMIT=c503375f5d98a734c085df76531a0c82141eb39d
THEME_ID=breeze-custom

work=$(mktemp -d)
git -C "$work" init -q
git -C "$work" fetch -q --depth 1 https://github.com/ysantalla/plasma-tips.git "$THEME_COMMIT"
git -C "$work" -c advice.detachedHead=false checkout -q FETCH_HEAD
test "$(git -C "$work" rev-parse HEAD)" = "$THEME_COMMIT"

# Only this folder: the repo's breeze-dark would replace Plasma's own theme of that name
target=/usr/share/plasma/desktoptheme/$THEME_ID
install -d "$target/widgets"
install -m 0644 -t "$target" \
  "$work/$THEME_ID/colors" "$work/$THEME_ID/metadata.json" "$work/$THEME_ID/plasmarc"
install -m 0644 -t "$target/widgets" \
  "$work/$THEME_ID/widgets/clock.svg" "$work/$THEME_ID/widgets/tasks.svgz"

rm -rf "$work"

# Fedora's default look-and-feel names the Plasma style, so change it there as well as in
# /etc/xdg. A user's own ~/.config/plasmarc still wins.
defaults=/usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop/contents/defaults
sed -i "/^\[plasmarc\]\[Theme\]/,/^\$/ s/^name=.*/name=$THEME_ID/" "$defaults"
grep -q "^name=$THEME_ID\$" "$defaults"
printf '[Theme]\nname=%s\n' "$THEME_ID" > /etc/xdg/plasmarc
