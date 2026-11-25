#!/usr/bin/env bash
# Checks a built image from the inside, before it is published.
# Usage: podman run --rm --network=none -v "$PWD/tests:/tests:ro" <image> bash /tests/smoke.sh <name>
set -uo pipefail

name=${1:?image name}
failures=0

ok() { # ok <description> <command...>
  local what=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   $what"
  else
    echo "FAIL $what"
    failures=$((failures + 1))
  fi
}

not() { ! "$@"; }
thermald_waits() { [[ "$(systemctl cat thermald.service 2>/dev/null)" == *"ExecStartPre=/usr/libexec/katze/thermald-wait.sh"* ]]; }
platform_profile_works() { # with a copy of the two handlers the XPS has
  local dir
  dir=$(mktemp -d)
  mkdir "$dir/a" "$dir/b"
  echo dell-pc >"$dir/a/name" && echo "cool quiet balanced performance" >"$dir/a/choices"
  echo "SoC Power Slider" >"$dir/b/name" && echo "low-power balanced performance" >"$dir/b/choices"
  PLATFORM_PROFILE_DIR=$dir /usr/libexec/katze/platform-profile.sh quiet low-power &&
    [[ "$(<"$dir/a/profile")" == quiet && "$(<"$dir/b/profile")" == low-power ]]
}
incus_kept_out_of() { firewall-offline-cmd --policy=katze-incus-private --list-rich-rules 2>/dev/null | grep -q "destination address=\"$1\" reject"; }
firewall_target() { [[ "$(firewall-offline-cmd "$1" --get-target 2>/dev/null)" == "$2" ]]; }
enabled() { [[ "$(systemctl is-enabled "$1" 2>/dev/null)" == enabled ]]; }
user_enabled() { [[ "$(systemctl --global is-enabled "$1" 2>/dev/null)" == enabled ]]; }
compose_is_quiet() { [[ "$(docker compose version 2>&1)" != *"external compose provider"* ]]; }
zsh_is_clean() { [[ -z "$(HOME=$(mktemp -d) TERM=dumb zsh -ic exit 2>&1)" ]]; }
# What a program installed per user needs: the login shell that starts Plasma, a terminal and a script.
# A second zsh must not change the order it inherits.
zsh_finds_user_programs() {
  local home flags
  home=$(mktemp -d)
  mkdir -p "$home/.local/bin"
  printf '#!/bin/sh\necho found\n' >"$home/.local/bin/katze-smoke"
  chmod +x "$home/.local/bin/katze-smoke"
  for flags in -lc -ic -c; do
    [[ "$(env -i HOME="$home" TERM=dumb PATH=/usr/bin:/bin zsh "$flags" katze-smoke 2>/dev/null)" == found ]] || return 1
  done
  # shellcheck disable=SC2016 # zsh expands it
  [[ "$(env -i HOME="$home" PATH="/first:$home/.local/bin:$home/bin:/usr/bin" zsh -c 'echo $PATH')" == "/first:$home/.local/bin:$home/bin:/usr/bin" ]]
}
# Only our units: upstream's complain here. Read once: with pipefail, `verify | grep -q` misreads a match
units_are_valid() {
  local out
  command -v systemd-analyze >/dev/null || return 1
  out=$(cd /usr/lib/systemd/system && systemd-analyze verify katze-flatpaks.service katze-setup.service katze-update.service katze-update.timer 2>&1)
  ! grep -qE 'katze-(flatpaks|setup|update)\.' <<<"$out"
}
user_units_are_valid() { local out; command -v systemd-analyze >/dev/null || return 1; out=$(systemd-analyze --user verify /usr/lib/systemd/user/katze-* 2>&1); ! grep -q katze- <<<"$out"; }
podman_docker() { [[ "$(docker --version 2>&1)" == "podman version"* ]]; }
has_decoder() { grep -qE "^ [A-Z.]{6} $1 " <<<"$DECODERS"; }
# As on a real machine: mtimes of 0 and a user who cannot rewrite the image's font cache
machine_sees_font() {
  find /usr/share/fonts -type d -exec touch -d @0 {} +
  local home
  home=$(mktemp -d)
  chmod 0777 "$home"
  [[ -n "$(runuser -u nobody -- env HOME="$home" XDG_CACHE_HOME="$home/.cache" fc-list "$1" family)" ]]
}
icons_parse() { python3 -c 'import sys, glob, xml.etree.ElementTree as ET; files = glob.glob(sys.argv[1] + "/apps/*/*.svg"); [ET.parse(f) for f in files]; sys.exit(not files)' "$1"; }
# A launcher whose Icon= is a relative path must not stop the generator or be written outside the theme
icons_survive_odd_names() {
  local home
  home=$(mktemp -d)
  mkdir -p "$home/data/applications"
  printf '[Desktop Entry]\nType=Application\nName=Up\nIcon=../../../escaped\n' >"$home/data/applications/up.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Sub\nIcon=some/dir/icon\n' >"$home/data/applications/sub.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Fine\nIcon=fine\n' >"$home/data/applications/fine.desktop"
  HOME=$home XDG_DATA_HOME=$home/data XDG_DATA_DIRS=/nonexistent \
    python3 /usr/libexec/katze/katze-mono.py --output "$home/a/b/theme" &&
    [[ -s $home/a/b/theme/apps/scalable/fine.svg && -z "$(find "$home" -name 'escaped*' -o -name icon.svg)" ]]
}
# PowerDevil's display timeout as a user with an empty home reads it
screen_off_after() { # screen_off_after <power state> <seconds>
  [[ "$(HOME=$(mktemp -d) XDG_CONFIG_DIRS=/etc/xdg:/usr/share/kde-settings/kde-profile/default/xdg \
    kreadconfig6 --file powerdevilrc --group "$1" --group Display --key TurnOffDisplayIdleTimeoutSec)" == "$2" ]]
}
opens_images_with() { [[ "$(XDG_CURRENT_DESKTOP=KDE gio mime "$1" 2>/dev/null | head -1)" == *"$2"* ]]; }
# The user's copy of the theme, written at login, must declare what only the image's copy has,
# or Plasma shortens "folder-documents" to this theme's "folder"
home_theme_keeps_breeze_folders() {
  local home
  home=$(mktemp -d)
  HOME=$home XDG_DATA_HOME=$home/data XDG_DATA_DIRS=/usr/local/share:/usr/share \
    python3 /usr/libexec/katze/katze-mono.py --follow-accent >/dev/null 2>&1 &&
    grep -q '^\[breeze/places/64\]$' "$home/data/icons/katze-mono/index.theme" &&
    grep -q '^\[apps/22\]$' "$home/data/icons/katze-mono/index.theme" &&
    test -e /usr/share/icons/katze-mono/breeze/places/64/folder-documents.svg
}
# Which file Plasma's own lookup (KIconThemes) returns for an icon name, with Katze Mono as the
# theme. "home" also writes the user's copy of the theme first, as katze-icons.service does at
# login. Checks on files and on index.theme missed three regressions that this would have shown.
icon_lookup() { # icon_lookup <image|home> <icon name>
  local home
  home=$(mktemp -d)
  mkdir -p "$home/.config" "$home/rt"
  printf '[Icons]\nTheme=katze-mono\n' >"$home/.config/kdeglobals"
  if [[ $1 == home ]]; then
    # an application of the user's own, so that there is something to write
    mkdir -p "$home/.local/share/applications"
    printf '[Desktop Entry]\nType=Application\nName=Mine\nIcon=katze-smoke-app\n' >"$home/.local/share/applications/mine.desktop"
    HOME=$home XDG_DATA_HOME=$home/.local/share /usr/libexec/katze/icons.sh >/dev/null 2>&1 || return 1
  fi
  HOME=$home XDG_DATA_HOME=$home/.local/share XDG_CONFIG_HOME=$home/.config XDG_RUNTIME_DIR=$home/rt \
    QT_QPA_PLATFORM=offscreen kiconfinder6 "$2" 2>/dev/null | tail -1
}
# With nothing of their own, a user gets no copy of the theme, and an older full copy goes away
home_copy_is_only_whats_new() {
  local home
  home=$(mktemp -d)
  HOME=$home XDG_DATA_HOME=$home/data python3 /usr/libexec/katze/katze-mono.py --follow-accent >/dev/null 2>&1 &&
    test -s "$home/data/icons/katze-mono/apps/scalable/org.kde.dolphin.svg" &&
    HOME=$home XDG_DATA_HOME=$home/data /usr/libexec/katze/icons.sh &&
    [[ ! -e $home/data/icons/katze-mono && ! -e $home/data/icons/katze-mono-light ]]
}
# shellcheck disable=SC2053 # the third argument is a glob on purpose
lookup_is() { [[ "$(icon_lookup "$1" "$2")" == $3 ]]; } # lookup_is <image|home> <icon name> <glob>
# update-changes.sh: the notification lists what a new image has that the running one does not
update_changes() {
  local dir
  dir=$(mktemp -d)
  printf 'b2 Second change\na1 First change\n' >"$dir/running"
  printf 'c3 Third change\nb2 Second change\na1 First change\n' >"$dir/new"
  [[ "$(/usr/libexec/katze/update-changes.sh "$dir/running" "$dir/new")" == "• Third change" ]] &&
    [[ -z "$(/usr/libexec/katze/update-changes.sh "$dir/running" "$dir/running")" ]] &&
    [[ -z "$(/usr/libexec/katze/update-changes.sh "$dir/running" "$dir/missing")" ]]
}
# What a user with an empty home reads, with the config path Plasma's session sets
kde_default() { # kde_default <file> <group> <key> <expected prefix>
  local value
  value=$(HOME=$(mktemp -d) XDG_CONFIG_DIRS=/etc/xdg:/usr/share/kde-settings/kde-profile/default/xdg \
    kreadconfig6 --file "$1" --group "$2" --key "$3")
  [[ "$value" == "$4"* ]]
}
font_has() { [[ -n "$(fc-list "$1:charset=$2" family)" ]]; }
font_for() { [[ "$(fc-match -f '%{family}' "$1")" == "$2"* ]]; }
repo_disabled() { grep -q '^enabled=0' "/etc/yum.repos.d/$1.repo" && ! grep -q '^enabled=1' "/etc/yum.repos.d/$1.repo"; }

camera_loads() { # imports camera.py, and checks the GStreamer elements it names
  PYTHONDONTWRITEBYTECODE=1 python3 -c '
import sys
sys.path.insert(0, "/usr/libexec/katze")
import camera
camera.Gst.init(None)
missing = [e for e in ("appsrc", "pipewiresink", "libcamerasrc", "fdsink") if not camera.Gst.ElementFactory.find(e)]
sys.exit(" ".join(missing) or 0)' || return
  test -x /usr/bin/gst-launch-1.0 -a -e /usr/lib64/gstreamer-1.0/libgstva.so # vapostproc only exists on a machine with the GPU
}

# Every Exec line of a launcher carries (or lacks) a flag
all_exec_have() { grep -q '^Exec=' "$1" && ! grep '^Exec=' "$1" | grep -qvF -- "$2"; }
no_exec_has() { [[ -f "$1" ]] && ! grep '^Exec=' "$1" | grep -qF -- "$2"; }

LAUNCHERS=(google-chrome com.google.Chrome brave-origin com.brave.Origin)
ENCODE=--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL

for pkg in incus okular kcalc haruna podman-docker docker-compose zsh yakuake fastfetch firefox google-chrome-stable brave-origin tailscale jq; do
  ok "package $pkg" rpm -q "$pkg"
done
ok "firewall defaults to katze-laptop" grep -qx 'DefaultZone=katze-laptop' /etc/firewalld/firewalld.conf
ok "firewall configuration is valid" firewall-offline-cmd --check-config
ok "Incus instances cannot reach the host's ports" firewall_target --zone=katze-incus default
ok "Incus instances can reach other networks" firewall_target --policy=katze-incus-out ACCEPT
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 fc00::/7; do
  ok "Incus instances cannot reach $net" incus_kept_out_of "$net"
done
ok "the private networks policy runs before the one that accepts" test "$(firewall-offline-cmd --policy=katze-incus-private --get-priority)" -lt "$(firewall-offline-cmd --policy=katze-incus-out --get-priority)"
ok "Zed uses the desktop's window borders" grep -qF 'dev.zed.Zed 0644 root root - [Environment]\nZED_WINDOW_DECORATIONS=server' /usr/lib/tmpfiles.d/katze-flatpak-overrides.conf

for pkg in toolbox distrobox nvtop moby-engine docker-cli; do
  ok "package $pkg is absent" not rpm -q "$pkg"
done

for unit in incus.socket tailscaled.service katze-setup.service katze-flatpaks.service katze-update.timer; do
  ok "enabled $unit" enabled "$unit"
done
for unit in bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer uupd.timer; do
  ok "not enabled $unit" not enabled "$unit"
done
for unit in katze-update-notify.service katze-update-notify.path katze-desktop-entries.service katze-image-age.timer katze-icons.service podman.socket; do
  ok "user enabled $unit" user_enabled "$unit"
done

for repo in google-chrome brave-browser tailscale; do
  ok "repo $repo is disabled" repo_disabled "$repo"
done

ok "/opt links to var/opt" test "$(readlink /opt)" = var/opt
for script in /usr/libexec/katze/*.sh; do
  ok "executable $script" test -x "$script"
done
# Read once: with pipefail, `ffmpeg | grep -q` fails when grep stops reading early
DECODERS=$(ffmpeg -hide_banner -decoders 2>/dev/null)
for decoder in h264 hevc vp9 av1 mpeg2video aac ac3 eac3 dca truehd flac opus; do
  ok "ffmpeg decodes $decoder" has_decoder "$decoder"
done
ok "docker is Podman" podman_docker
ok "docker compose has the real Compose" test -x /usr/libexec/docker/cli-plugins/docker-compose
ok "docker compose runs without the provider notice" compose_is_quiet
ok "starship runs" starship --version
ok "zsh starts without errors" zsh_is_clean
ok "zsh finds programs in ~/.local/bin" zsh_finds_user_programs
ok "Konsole opens our profile" grep -qx 'DefaultProfile=katze.profile' /etc/xdg/konsolerc
ok "Yakuake starts with the session" test -f /etc/xdg/autostart/org.kde.yakuake.desktop
ok "our system units are valid" units_are_valid
ok "our user units are valid" user_units_are_valid
ok "factory prompt keeps its icons" grep -q $'\xee\x82\xb0' /usr/share/katze/starship.toml
# Must run before the fc-list and fc-match calls below, which can rewrite the cache as root
ok "a machine can see the terminal font" machine_sees_font "MesloLGS Nerd Font"
# A Tibetan font also defines U+F30A, so an unusable terminal font shows a wrong icon instead of a blank
ok "terminal font has the Fedora icon" font_has "MesloLGS Nerd Font" f30a
ok "terminal font has the prompt separator" font_has "MesloLGS Nerd Font" e0b0
THEME=/usr/share/plasma/desktoptheme/katze
ok "Plasma style has its id" jq -e '.KPlugin.Id == "katze"' "$THEME/metadata.json"
ok "Plasma style has its taskbar" gzip -t "$THEME/widgets/tasks.svgz"
# With a colors file, the panel would ignore the color scheme and the accent
ok "Plasma style follows the color scheme" not test -e "$THEME/colors"
ok "Plasma style is the default" grep -q '^name=katze$' /etc/xdg/plasmarc
ok "dark color scheme is installed" grep -q '^Name=Katze Dark$' /usr/share/color-schemes/KatzeDark.colors
# Plasma writes black here when the accent is lighter than #34AAE8
ok "dark selection has white text" test "$(sed -n '/^\[Colors:Selection\]$/,/^$/s/^ForegroundNormal=//p' /usr/share/color-schemes/KatzeDark.colors)" = 255,255,255
ok "light color scheme is installed" grep -q '^Name=Katze Light$' /usr/share/color-schemes/KatzeLight.colors
ok "color scheme is the default" grep -q '^ColorScheme=KatzeDark$' /etc/xdg/kdeglobals
LOOKS=/usr/share/plasma/look-and-feel
ok "only Breeze and Katze global themes" test "$(find "$LOOKS" -mindepth 1 -maxdepth 1 -printf '%f\n' | grep -vcE '^(org\.kde\.breeze.*|katze-(dark|light))$')" = 0
for look in dark:KatzeDark:katze-mono light:KatzeLight:katze-mono-light; do
  IFS=: read -r variant scheme icons <<<"$look"
  ok "Katze ${variant^} has its id" jq -e ".KPlugin.Id == \"katze-$variant\"" "$LOOKS/katze-$variant/metadata.json"
  ok "Katze ${variant^} sets its colors" grep -q "^ColorScheme=$scheme\$" "$LOOKS/katze-$variant/contents/defaults"
  ok "Katze ${variant^} sets its icons" grep -q "^Theme=$icons\$" "$LOOKS/katze-$variant/contents/defaults"
  ok "Katze ${variant^} sets the Plasma style" grep -q '^name=katze$' "$LOOKS/katze-$variant/contents/defaults"
  ok "Katze ${variant^} has a 56 px panel" grep -q 'panel.height = 56' "$LOOKS/katze-$variant/contents/layouts/org.kde.plasma.desktop-layout.js"
  ok "Katze ${variant^} has a translucent panel" grep -q '^panel.opacity = "translucent"$' "$LOOKS/katze-$variant/contents/layouts/org.kde.plasma.desktop-layout.js"
  ok "Katze ${variant^} has the desktop switcher" grep -q 'org.kde.plasma.pager' "$LOOKS/katze-$variant/contents/layouts/org.kde.plasma.desktop-layout.js"
  ok "Katze ${variant^} scales the tray icons" grep -q 'scaleIconsToFit' "$LOOKS/katze-$variant/contents/layouts/org.kde.plasma.desktop-layout.js"
  ok "Katze ${variant^} has a preview" test -s "$LOOKS/katze-$variant/contents/previews/preview.png"
  ok "$icons follows the color scheme" grep -q '^FollowsColorScheme=true$' "/usr/share/icons/$icons/index.theme"
  ok "$icons has the browser" test -s "/usr/share/icons/$icons/apps/scalable/brave-origin.svg"
  ok "$icons has a Flatpak that is not installed yet" test -s "/usr/share/icons/$icons/apps/scalable/dev.zed.Zed.svg"
  for preview in exec folder document user-trash help-browser preferences-system; do
    ok "$icons has $preview for System Settings' preview" test -s "/usr/share/icons/$icons/apps/scalable/$preview.svg"
    ok "$icons draws $preview without opacity" not grep -q ' opacity="' "/usr/share/icons/$icons/apps/scalable/$preview.svg"
  done
  for small in user-trash utilities-terminal org.kde.dolphin; do
    ok "$icons draws $small without the shape when small" grep -q 'ColorScheme-Text' "/usr/share/icons/$icons/apps/22/$small.svg"
  done
  ok "$icons declares its small icons" grep -q '^\[apps/22\]$' "/usr/share/icons/$icons/index.theme"
  for scale in 2 3; do
    ok "$icons has its small icons for a screen scaled ${scale}x" test -s "/usr/share/icons/$icons/apps/22@${scale}x/user-trash.svg"
    ok "$icons declares them" grep -q "^\[apps/22@${scale}x\]\$" "/usr/share/icons/$icons/index.theme"
  done
  ok "$icons has the tray names" test -s "/usr/share/icons/$icons/apps/symbolic/yakuake-symbolic.svg"
  # An icon named preferences-system would otherwise replace every preferences-system-* of Breeze
  ok "$icons keeps Breeze's longer names" test -e "/usr/share/icons/$icons/breeze/preferences/32/preferences-system-bluetooth.svg"
  ok "$icons has no broken links" test -z "$(find "/usr/share/icons/$icons" -xtype l -print -quit)"
  ok "$icons is valid XML" icons_parse "/usr/share/icons/$icons"
done
ok "package koko" rpm -q koko
for type in image/png image/jpeg image/webp; do
  ok "$type opens in Koko" opens_images_with "$type" org.kde.koko.desktop
done
ok "Koko has its Katze icon" test -s /usr/share/icons/katze-mono/apps/scalable/org.kde.koko.svg
# Made at build time from Breeze's. If Breeze changed and the build left it out, that is a
# warning in the build log, not a failure here: updates must keep flowing.
panel_is_ours_or_breezes() {
  local file=/usr/share/plasma/desktoptheme/katze/$1/panel-background.svg
  [[ ! -e $file ]] && return 0
  grep -q 'opacity:0.92' "$file" && python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$file"
}
for panel in widgets translucent/widgets; do
  ok "the panel is 92% opaque, or Breeze's ($panel)" panel_is_ours_or_breezes "$panel"
done
ok "Katze Dark is the default global theme" grep -q '^LookAndFeelPackage=katze-dark$' /etc/xdg/kdeglobals
ok "an update says what it changes" update_changes
ok "icon generator runs" python3 /usr/libexec/katze/katze-mono.py --report
ok "a user's copy of the icons keeps Breeze's special folders" home_theme_keeps_breeze_folders
ok "a user's copy of the icons holds only what the image lacks" home_copy_is_only_whats_new
ok "Plasma finds the icon of a user's own application" lookup_is home katze-smoke-app '*/.local/share/icons/katze-mono/apps/scalable/katze-smoke-app.svg'
for copy in image home; do
  ok "Plasma finds Katze's icon for an application ($copy copy)" lookup_is "$copy" org.kde.dolphin '/usr/share/icons/katze-mono/apps/scalable/org.kde.dolphin.svg'
  ok "Plasma finds Breeze's icon for a special folder ($copy copy)" lookup_is "$copy" folder-documents '*breeze*/places/*/folder-documents.svg'
  ok "Plasma finds Breeze's icon for a longer name ($copy copy)" lookup_is "$copy" preferences-system-bluetooth '*breeze*/preferences-system-bluetooth.svg'
  ok "Plasma finds Katze's Trash ($copy copy)" lookup_is "$copy" user-trash '*/katze-mono/apps/scalable/user-trash.svg'
done
# A new application of the image with no glyph of its own shows up here: give it an alias
ok "no application is left with its initial for an icon" test -z "$(python3 /usr/libexec/katze/katze-mono.py --report --only initial 2>/dev/null | grep '^initial ')"
ok "no application is left with its category's icon" test -z "$(python3 /usr/libexec/katze/katze-mono.py --report --only generic 2>/dev/null | grep '^generic ')"
ok "icon generator draws its preview" python3 /usr/libexec/katze/katze-mono.py --all-aliases --preview /tmp/katze-preview.svg
ok "the icons' look comes from aliases.toml" grep -q '^\[look.dark\]$' /usr/share/katze/katze-mono/aliases.toml
ok "icon generator survives odd icon names" icons_survive_odd_names
ok "a machine can see the interface font" machine_sees_font Inter
ok "interface font is the default" grep -q '^font=Inter,11,' /etc/xdg/kdeglobals
ok "no sub-pixel text in KDE" grep -q '^XftSubPixel=none$' /etc/xdg/kdeglobals
ok "Plasma's session reads /etc/xdg first" grep -q 'XDG_CONFIG_DIRS=/etc/xdg:' /etc/xdg/plasma-workspace/env/env.sh
ok "a new user gets the interface font" kde_default kdeglobals General font Inter,11,
ok "a new user gets the menu font" kde_default kdeglobals General menuFont Inter,11,
ok "a new user gets no sub-pixel text" kde_default kdeglobals General XftSubPixel none
ok "a new user gets the Katze icons" kde_default kdeglobals Icons Theme katze-mono
ok "a new user gets the color scheme" kde_default kdeglobals General ColorScheme KatzeDark
ok "a new user gets the Plasma style" kde_default plasmarc Theme name katze
ok "a new user gets the global theme" kde_default kdeglobals KDE LookAndFeelPackage katze-dark
ok "a new user gets two virtual desktops" kde_default kwinrc Desktops Number 2
ok "virtual desktops are stacked" kde_default kwinrc Desktops Rows 2
# These checks run as root, which would read a file users cannot
ok "users can read the Breeze defaults" test "$(stat -c %a /etc/xdg/breezerc)" = 644
ok "windows have no outline" kde_default breezerc Common OutlineEnabled false
ok "windows have a medium shadow" kde_default breezerc Common ShadowSize ShadowMedium
ok "menus are translucent" kde_default breezerc Style MenuOpacity 79
ok "Dark Mode switches to Katze Dark" kde_default kdeglobals KDE DefaultDarkLookAndFeel katze-dark
ok "Dark Mode switches back to Katze Light" kde_default kdeglobals KDE DefaultLightLookAndFeel katze-light
ok "Slack launcher forwards links" all_exec_have /usr/share/katze/applications/com.slack.Slack.desktop "--file-forwarding com.slack.Slack"
ok "update notification restarts through Plasma" grep -q 'org.kde.Shutdown' /usr/libexec/katze/update-notify.sh
ok "no sub-pixel text in fontconfig" not test -e /etc/fonts/conf.d/10-sub-pixel-rgb-for-kde.conf
ok "Calibri documents use Carlito" font_for Calibri Carlito
ok "Cambria documents use Caladea" font_for Cambria Caladea
ok "Konsole uses the Katze colors" grep -qx 'ColorScheme=Katze' /usr/share/konsole/katze.profile
ok "the Katze color scheme for Konsole is there" grep -qx 'Color=17,23,27' /usr/share/konsole/Katze.colorscheme
ok "the prompt uses the Katze color" grep -q 'fg:#34aae8' /usr/share/katze/starship.toml
ok "Konsole uses the terminal font" grep -q '^Font=MesloLGS Nerd Font,' /usr/share/konsole/katze.profile
ok "build time is recorded" grep -qE '^[0-9]+$' /usr/share/katze/build-time

for launcher in "${LAUNCHERS[@]}"; do
  ok "no Wayland flag in $launcher" no_exec_has "/usr/share/applications/$launcher.desktop" --ozone-platform
done
for dir in /usr/lib/google/chrome /usr/lib/brave.com/brave-origin; do
  ok "system title bar in $dir" jq -e '.browser.custom_chrome_frame == false' "$dir/initial_preferences"
  ok "Qt colors in $dir" jq -e '.extensions.theme.system_theme == 2' "$dir/initial_preferences"
done

ok "signature policy for our registry" jq -e '.transports.docker["ghcr.io/ysantalla"][0].type == "sigstoreSigned"' /etc/containers/policy.json
ok "nothing unsigned is accepted by default" jq -e '.default == [{"type": "reject"}]' /etc/containers/policy.json
ok "signature key is present" test -s /usr/share/katze/cosign.pub
ok "sigstore attachments are enabled" grep -q use-sigstore-attachments /etc/containers/registries.d/katze.yaml

case "$name" in
  base)
    for launcher in "${LAUNCHERS[@]}"; do
      ok "no Intel flags in $launcher" no_exec_has "/usr/share/applications/$launcher.desktop" "$ENCODE"
    done
    ;;
  xps16-da16260)
    for pkg in libva-intel-media-driver libva-utils powertop lm_sensors igt-gpu-tools kernel-tools; do
      ok "package $pkg" rpm -q "$pkg"
    done
    ok "turbostat is on PATH" command -v turbostat
    ok "thermald waits for its sensors" test -x /usr/libexec/katze/thermald-wait.sh
    ok "thermald drop-in is read" thermald_waits
    for profile in powersave balanced balanced-battery performance; do
      ok "tuned profile katze-xps-$profile" test -x "/usr/lib/tuned/profiles/katze-xps-$profile/script.sh"
      ok "tuned-ppd uses katze-xps-$profile" grep -q "=katze-xps-$profile\$" /etc/tuned/ppd.conf
    done
    ok "tuned-ppd leaves our profiles alone" grep -qx 'sysfs_acpi_monitor=false' /etc/tuned/ppd.conf
    ok "platform profiles reach each handler" platform_profile_works
    ok "the screen turns off after 3 minutes on AC" screen_off_after AC 180
    ok "the screen turns off after 2 minutes on battery" screen_off_after Battery 120
    for pkg in python3-gobject-base gstreamer1-plugins-bad-free libcamera-gstreamer pipewire-gstreamer; do
      ok "package $pkg" rpm -q "$pkg"
    done
    ok "the camera relay is enabled" test -L /etc/systemd/user/pipewire.service.wants/katze-camera.service
    ok "the camera relay finds its libraries" camera_loads
    ok "WirePlumber leaves the camera to the relay" grep -q 'monitor.libcamera = disabled' /usr/share/wireplumber/wireplumber.conf.d/60-katze-camera.conf
    for launcher in "${LAUNCHERS[@]}"; do
      ok "browser camera through PipeWire in $launcher" all_exec_have "/usr/share/applications/$launcher.desktop" WebRtcPipeWireCamera
      ok "Intel flags in $launcher" all_exec_have "/usr/share/applications/$launcher.desktop" "$ENCODE"
    done
    ;;
  *)
    echo "FAIL unknown image $name"
    failures=$((failures + 1))
    ;;
esac

echo "failures: $failures"
(( failures == 0 ))
