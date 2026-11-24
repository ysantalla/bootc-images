# Katze Plasma style

The panel, widgets and taskbar indicators of the Katze Dark and Katze Light
global themes: Breeze, with the owner's taskbar indicators (`widgets/tasks.svgz`)
and clock (`widgets/clock.svg`), moved here from `ysantalla/plasma-tips`.

It has no `colors` file on purpose. A Plasma style that ships one paints the
panel and the launcher with those colors whatever the color scheme and accent
are. Without it, one style serves the light and the dark scheme, and the icons
drawn in the panel follow the accent.

`widgets/panel-background.svg` and `translucent/widgets/panel-background.svg`
are not in this folder: `plasma-theme.sh` makes them at build time from the
Breeze of that build, with the panel's fill at 92% instead of 85%. The Katze
layouts keep the panel translucent, and at 85% the wallpaper colored it more
than the owner wanted. System Settings only offers adaptive, opaque and
translucent: how translucent is decided here. If Breeze stops using that
value, the build prints a warning and the panel keeps Breeze's look.

The mark on a task with several windows (`group-expander-*` in
`widgets/tasks.svgz`) is drawn in the text color with dots in the background
color. It was in the highlight color, which is the color of the icon's own shape
since the icons take 40% of the accent, so it could not be told apart.

To try a change without building an image, copy this folder to
`~/.local/share/plasma/desktoptheme/katze` and run
`plasma-apply-desktoptheme katze`.
