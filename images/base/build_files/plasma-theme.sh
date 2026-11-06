#!/usr/bin/env bash
# The owner's Plasma style and color scheme, as the default for new users.
# Source: github.com/ysantalla/plasma-tips, pinned to a commit. To update, change the commit here.
set -euxo pipefail

THEME_COMMIT=f00ddb7a5358e52c6a11032786148cdfe9659d25
THEME_ID=breeze-custom
COLOR_SCHEME=BreezeDarkCustom

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

install -m 0644 -t /usr/share/color-schemes "$work/color-schemes/$COLOR_SCHEME.colors"

rm -rf "$work"

# Fedora's default look-and-feel names these, so change them there as well as in /etc/xdg.
# Dark icons go with the dark colors. A user's own settings in ~/.config still win.
defaults=/usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop/contents/defaults
sed -i "/^\[plasmarc\]\[Theme\]/,/^\$/ s/^name=.*/name=$THEME_ID/" "$defaults"
sed -i "s/^ColorScheme=.*/ColorScheme=$COLOR_SCHEME/" "$defaults"
sed -i '/^\[kdeglobals\]\[Icons\]/,/^$/ s/^Theme=.*/Theme=breeze-dark/' "$defaults"
grep -q "^name=$THEME_ID\$" "$defaults"
grep -q "^ColorScheme=$COLOR_SCHEME\$" "$defaults"
grep -q '^Theme=breeze-dark$' "$defaults"
printf '[Theme]\nname=%s\n' "$THEME_ID" > /etc/xdg/plasmarc
printf '[General]\nColorScheme=%s\n\n[Icons]\nTheme=breeze-dark\n' "$COLOR_SCHEME" > /etc/xdg/kdeglobals
