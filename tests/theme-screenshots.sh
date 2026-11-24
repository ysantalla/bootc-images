#!/usr/bin/env bash
# Takes the pictures of the Katze themes again, from a running test VM, and writes
# them where the repository keeps them: the previews of both global themes and the
# screenshots of the README. Run it with `mise run theme:screenshots`.
#
# It needs, in the VM (`mise run vm-up base`):
#   - the user of bib/config.toml logged in to Plasma
#   - sshd running and let through: `sudo systemctl enable --now sshd` and
#     `sudo firewall-cmd --add-service=ssh`
# and on this machine, ImageMagick's `magick`.
#
# It changes that session while it runs (resolution, theme, wallpaper, open
# windows, and it restarts the panel) and puts back the theme, the wallpaper and
# the resolution at the end. Do not use the VM meanwhile.
set -euo pipefail

cd "$(dirname "$0")/.."
config=bib/config.toml
port=${KATZE_VM_SSH_PORT:-2222}
previews=images/base/system_files/usr/share/plasma/look-and-feel
shots=docs/screenshots

test -f "$config" || { echo "Missing $config: it has the test VM's user" >&2; exit 1; }
command -v magick >/dev/null || { echo "This needs ImageMagick (magick)" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# ssh asks this for the password, so it is never on a command line or in the environment
cat >"$work/askpass" <<EOF
#!/usr/bin/env python3
import tomllib
print(tomllib.load(open("$PWD/$config", "rb"))["customizations"]["user"][0]["password"])
EOF
chmod 0700 "$work/askpass"
user=$(python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["customizations"]["user"][0]["name"])' "$config")

vm() { # vm <command>: run it in the VM as the test user; stdin goes to the command
  SSH_ASKPASS="$work/askpass" SSH_ASKPASS_REQUIRE=force setsid -w ssh -p "$port" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile="$work/known_hosts" \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o ConnectTimeout=10 -o LogLevel=ERROR "$user@127.0.0.1" "$@"
}

vm true </dev/null || { echo "Cannot reach the VM on port $port: is it up, with sshd let through?" >&2; exit 1; }

echo "Taking the pictures in the VM (about two minutes)..."
vm 'bash -s' <<'GUEST'
set -euo pipefail

# Everything below talks to the Plasma session, so it needs that session's own environment
pid=$(pgrep -u "$USER" -x plasmashell | head -1) || { echo "No Plasma session for $USER in the VM" >&2; exit 1; }
while IFS= read -r -d '' kv; do
  case "$kv" in XDG_*|WAYLAND_DISPLAY=*|DBUS_SESSION_BUS_ADDRESS=*|DISPLAY=*|QT_*|KDE_*) export "$kv" ;; esac
done <"/proc/$pid/environ"

out=/tmp/katze-shots
rm -rf "$out"
mkdir -p "$out"

kwin() { # kwin <javascript>: run it in KWin
  local file id
  file=$(mktemp --suffix=.js)
  printf '%s\n' "$1" >"$file"
  id=$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$file" "katze$RANDOM")
  qdbus-qt6 org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1 || true
  rm -f "$file"
}
restart_panel() {
  systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
  systemctl --user restart plasma-plasmashell.service
  sleep 7
}
capture() { spectacle -b -n -f -o "$out/$1.png" >/dev/null 2>&1; }
launcher() { qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; }

# What to put back
theme=$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)
wallpaper=$(grep -m1 '^Image=' ~/.config/plasma-org.kde.plasma.desktop-appletsrc | cut -d= -f2- || true)
screen=$(kscreen-doctor -o | sed 's/\x1b\[[0-9;]*m//g')
output=$(awk '/^Output:/ {print $3; exit}' <<<"$screen")
mode=$(grep -o '[0-9]*:[^ ]*\*' <<<"$screen" | head -1 | cut -d: -f1)
scale=$(awk '/Scale:/ {print $2; exit}' <<<"$screen")
full_hd=$(grep -o '[0-9]*:1920x1080@[0-9.]*' <<<"$screen" | head -1 | cut -d: -f1)
restore() {
  pkill -x dolphin || true
  pkill -f plasma-discover || true
  kwriteconfig6 --file plasmarc --group PlasmaToolTips --key Delay --delete
  [[ -n $wallpaper ]] && plasma-apply-wallpaperimage "${wallpaper#file://}" >/dev/null 2>&1 || true
  plasma-apply-lookandfeel -a "${theme:-katze-dark}" >/dev/null 2>&1 || true
  sleep 4
  restart_panel
  [[ -n $mode ]] && kscreen-doctor "output.$output.mode.$mode" "output.$output.scale.$scale" >/dev/null 2>&1 || true
}
trap restore EXIT

[[ -n $full_hd ]] || { echo "The VM's screen has no 1920x1080 mode" >&2; exit 1; }
kscreen-doctor "output.$output.mode.$full_hd" "output.$output.scale.1" >/dev/null 2>&1
sleep 4
# The themes' own wallpaper, and no tooltip left over from wherever the pointer is
plasma-apply-wallpaperimage /usr/share/wallpapers/Next >/dev/null 2>&1
kwriteconfig6 --file plasmarc --group PlasmaToolTips --key Delay -- -1

pkill -x dolphin || true
pkill -f plasma-discover || true
sleep 1
setsid -f dolphin --new-window ~ >/dev/null 2>&1
sleep 3
setsid -f plasma-discover >/dev/null 2>&1
sleep 30 # Discover fetches its front page

for variant in dark light; do
  plasma-apply-lookandfeel -a "katze-$variant" >/dev/null 2>&1
  sleep 4
  restart_panel # the panel keeps the icons it has drawn until it restarts
  kwin 'workspace.windowList().forEach(function (w) {
    if (!w.normalWindow) return;
    if (w.resourceClass == "org.kde.dolphin") { w.minimized = false; w.setMaximize(false, false); w.frameGeometry = {x: 150, y: 110, width: 1000, height: 640}; }
    else if (w.resourceClass == "org.kde.discover") { w.minimized = false; w.setMaximize(false, false); w.frameGeometry = {x: 760, y: 230, width: 1000, height: 700}; workspace.activeWindow = w; }
    else { w.minimized = true; }
  });'
  sleep 3
  capture "desktop-$variant"
  kwin 'workspace.windowList().forEach(function (w) { if (w.normalWindow) { w.minimized = true; } });'
  sleep 1
  launcher
  sleep 4
  capture "launcher-$variant"
  launcher
  sleep 1
done
ls "$out"
GUEST

vm 'tar -C /tmp/katze-shots -cf - .' </dev/null | tar -xf - -C "$work"
for variant in dark light; do
  for kind in desktop launcher; do
    test -s "$work/$kind-$variant.png" || { echo "The VM gave no $kind-$variant.png" >&2; exit 1; }
  done
  # What System Settings shows for the global theme
  magick "$work/launcher-$variant.png" -quality 88 "$previews/katze-$variant/contents/previews/fullscreenpreview.jpg"
  magick "$work/launcher-$variant.png" -resize 600x337! "$previews/katze-$variant/contents/previews/preview.png"
  # The README: the whole desktop, and the launcher's corner
  magick "$work/desktop-$variant.png" -resize 1600x900! -quality 86 "$shots/katze-$variant.jpg"
  magick "$work/launcher-$variant.png" -crop 900x670+0+410 +repage -quality 88 "$shots/katze-$variant-launcher.jpg"
done
echo "Wrote the previews under $previews and the pictures under $shots. Look at them before committing."
