// The Katze desktop: one panel, 56 px thick and always translucent, with the
// virtual desktop switcher next to the tray and tray icons that grow with the panel.
// Plasma runs this for a new user, and when the theme is applied with its
// desktop layout. It follows Plasma's own default panel
// (org.kde.plasma.desktop.defaultPanel), which puts the switcher on the left.
var panel = new Panel
panel.height = 56
// Always translucent. Plasma's default turns the panel opaque under a maximized
// window, in the window's own color, and the two can no longer be told apart.
panel.opacity = "translucent"

// Restrict a horizontal panel to the width of a 21:9 monitor, as Plasma does
const maximumAspectRatio = 21 / 9
if (panel.formFactor === "horizontal") {
    const geo = screenGeometry(panel.screen)
    const maximumWidth = Math.ceil(geo.height * maximumAspectRatio)
    if (geo.width > maximumWidth) {
        panel.alignment = "center"
        panel.minimumLength = maximumWidth
        panel.maximumLength = maximumWidth
    }
}

panel.addWidget("org.kde.plasma.kickoff")
panel.addWidget("org.kde.plasma.icontasks")
panel.addWidget("org.kde.plasma.marginsseparator")
// Hidden by Plasma while there is only one virtual desktop; the image starts with two
panel.addWidget("org.kde.plasma.pager")

const tray = panel.addWidget("org.kde.plasma.systemtray")
tray.currentConfigGroup = ["General"]
tray.writeConfig("scaleIconsToFit", true)

panel.addWidget("org.kde.plasma.digitalclock")
panel.addWidget("org.kde.plasma.showdesktop")

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = 'org.kde.image';
}
