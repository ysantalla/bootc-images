#!/usr/bin/env bash
# Makes Katze Dark the look of a new user: global theme, Plasma style, color scheme,
# icons and fonts. The themes themselves are in system_files.
set -euxo pipefail

GLOBAL_THEME=katze-dark
# What the Dark Mode switch and "Switch to Dark Mode at Night" change to and from
LIGHT_THEME=katze-light
THEME_ID=katze
COLOR_SCHEME=KatzeDark
ICON_THEME=katze-mono

# Only Breeze's and Katze's global themes are offered. plasma-workspace requires the
# package that owns Fedora's, so the themes are removed and the package stays.
test -d /usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop
rm -r /usr/share/plasma/look-and-feel/org.fedoraproject.*

# Katze Mono for the applications of the image, and for those that arrive later as
# Flatpaks, which have no launcher yet. katze-icons.service adds each user's own.
for variant in dark light; do
  dir=/usr/share/icons/$ICON_THEME
  [[ $variant == light ]] && dir=$dir-light
  python3 /usr/libexec/katze/katze-mono.py --follow-accent --variant "$variant" \
    --all-aliases --output "$dir"
  test -s "$dir/index.theme"
  test -s "$dir/apps/scalable/org.kde.dolphin.svg"
done

# The global theme's own defaults must name things that exist.
defaults=/usr/share/plasma/look-and-feel/$GLOBAL_THEME/contents/defaults
grep -q "^name=$THEME_ID\$" "$defaults"
grep -q "^ColorScheme=$COLOR_SCHEME\$" "$defaults"
grep -q "^Theme=$ICON_THEME\$" "$defaults"
test -f "/usr/share/plasma/desktoptheme/$THEME_ID/metadata.json"
test -f "/usr/share/color-schemes/$COLOR_SCHEME.colors"
test -f "/usr/share/plasma/look-and-feel/$LIGHT_THEME/metadata.json"
printf '[Theme]\nname=%s\n' "$THEME_ID" > /etc/xdg/plasmarc

# Two virtual desktops, one above the other, so the switcher in the panel has something to show
kwriteconfig6 --file /etc/xdg/kwinrc --group Desktops --key Number 2
kwriteconfig6 --file /etc/xdg/kwinrc --group Desktops --key Rows 2
grep -q '^Number=2$' /etc/xdg/kwinrc

# The owner's interface fonts. Noto stays the system's sans-serif, for its language coverage.
FONT_TAIL=-1,5,400,0,0,0,0,0,0,0,0,0,0,1
cat > /etc/xdg/kdeglobals <<EOF
[General]
ColorScheme=$COLOR_SCHEME
XftAntialias=true
XftHintStyle=hintslight
XftSubPixel=none
font=Inter,11,$FONT_TAIL
menuFont=Inter,11,$FONT_TAIL
smallestReadableFont=Inter,9,$FONT_TAIL
toolBarFont=Inter,11,$FONT_TAIL

[Icons]
Theme=$ICON_THEME

[KDE]
LookAndFeelPackage=$GLOBAL_THEME
DefaultDarkLookAndFeel=$GLOBAL_THEME
DefaultLightLookAndFeel=$LIGHT_THEME

[WM]
activeFont=Inter,11,$FONT_TAIL
EOF

# No sub-pixel text for apps that read fontconfig: Fedora assumes RGB stripes on KDE, and OLED
# panels often lack them. This replaces its rule rather than overriding it.
test -e /etc/fonts/conf.d/10-sub-pixel-rgb-for-kde.conf
rm /etc/fonts/conf.d/10-sub-pixel-rgb-for-kde.conf
ln -s /usr/share/fontconfig/conf.avail/10-sub-pixel-none.conf /etc/fonts/conf.d/10-sub-pixel-none.conf
