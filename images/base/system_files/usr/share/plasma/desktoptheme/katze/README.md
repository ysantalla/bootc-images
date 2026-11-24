# Katze Plasma style

The panel, widgets and taskbar indicators of the Katze Dark and Katze Light
global themes: Breeze, with the owner's taskbar indicators (`widgets/tasks.svgz`)
and clock (`widgets/clock.svg`), moved here from `ysantalla/plasma-tips`.

It has no `colors` file on purpose. A Plasma style that ships one paints the
panel and the launcher with those colors whatever the color scheme and accent
are. Without it, one style serves the light and the dark scheme, and the icons
drawn in the panel follow the accent.

To try a change without building an image, copy this folder to
`~/.local/share/plasma/desktoptheme/katze` and run
`plasma-apply-desktoptheme katze`.
