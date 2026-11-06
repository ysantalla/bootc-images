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
enabled() { [[ "$(systemctl is-enabled "$1" 2>/dev/null)" == enabled ]]; }
user_enabled() { [[ "$(systemctl --global is-enabled "$1" 2>/dev/null)" == enabled ]]; }
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
font_has() { [[ -n "$(fc-list "$1:charset=$2" family)" ]]; }
font_for() { [[ "$(fc-match -f '%{family}' "$1")" == "$2"* ]]; }
repo_disabled() { grep -q '^enabled=0' "/etc/yum.repos.d/$1.repo" && ! grep -q '^enabled=1' "/etc/yum.repos.d/$1.repo"; }

# Every Exec line of a launcher carries (or lacks) a flag
all_exec_have() { grep -q '^Exec=' "$1" && ! grep '^Exec=' "$1" | grep -qvF -- "$2"; }
no_exec_has() { ! grep '^Exec=' "$1" | grep -qF -- "$2"; }

LAUNCHERS=(google-chrome com.google.Chrome brave-origin com.brave.Origin)
ENCODE=--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL

for pkg in incus okular haruna podman-docker docker-compose zsh yakuake firefox google-chrome-stable brave-origin tailscale jq; do
  ok "package $pkg" rpm -q "$pkg"
done
for pkg in toolbox distrobox moby-engine docker-cli; do
  ok "package $pkg is absent" not rpm -q "$pkg"
done

for unit in incus.socket tailscaled.service bootc-setup.service bootc-flatpaks.service bootc-update.timer; do
  ok "enabled $unit" enabled "$unit"
done
for unit in bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer uupd.timer; do
  ok "not enabled $unit" not enabled "$unit"
done
for unit in bootc-update-notify.service bootc-update-notify.path bootc-desktop-entries.service bootc-image-age.timer podman.socket; do
  ok "user enabled $unit" user_enabled "$unit"
done

for repo in google-chrome brave-browser tailscale; do
  ok "repo $repo is disabled" repo_disabled "$repo"
done

ok "/opt links to var/opt" test "$(readlink /opt)" = var/opt
for script in /usr/libexec/bootc-images/*.sh; do
  ok "executable $script" test -x "$script"
done
# Read once: with pipefail, `ffmpeg | grep -q` fails when grep stops reading early
DECODERS=$(ffmpeg -hide_banner -decoders 2>/dev/null)
for decoder in h264 hevc vp9 av1 mpeg2video aac ac3 eac3 dca truehd flac opus; do
  ok "ffmpeg decodes $decoder" has_decoder "$decoder"
done
ok "docker is Podman" podman_docker
ok "docker compose has the real Compose" test -x /usr/libexec/docker/cli-plugins/docker-compose
ok "starship runs" starship --version
ok "factory prompt keeps its icons" grep -q $'\xee\x82\xb0' /usr/share/bootc-images/starship.toml
# Must run before the fc-list and fc-match calls below, which can rewrite the cache as root
ok "a machine can see the terminal font" machine_sees_font "MesloLGS Nerd Font"
# A Tibetan font also defines U+F30A, so an unusable terminal font shows a wrong icon instead of a blank
ok "terminal font has the Fedora icon" font_has "MesloLGS Nerd Font" f30a
ok "terminal font has the prompt separator" font_has "MesloLGS Nerd Font" e0b0
THEME=/usr/share/plasma/desktoptheme/breeze-custom
ok "Plasma style has its id" jq -e '.KPlugin.Id == "breeze-custom"' "$THEME/metadata.json"
ok "Plasma style has its taskbar" gzip -t "$THEME/widgets/tasks.svgz"
ok "Plasma style is the default" grep -q '^name=breeze-custom$' /etc/xdg/plasmarc
ok "Plasma style is in the look-and-feel" grep -q '^name=breeze-custom$' /usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop/contents/defaults
ok "color scheme is installed" grep -q '^Name=Breeze Dark Custom' /usr/share/color-schemes/BreezeDarkCustom.colors
ok "color scheme is the default" grep -q '^ColorScheme=BreezeDarkCustom$' /etc/xdg/kdeglobals
ok "Calibri documents use Carlito" font_for Calibri Carlito
ok "Cambria documents use Caladea" font_for Cambria Caladea
ok "Konsole uses the terminal font" grep -q '^Font=MesloLGS Nerd Font,' /usr/share/konsole/bootc-images.profile
ok "build time is recorded" grep -qE '^[0-9]+$' /usr/share/bootc-images/build-time

for launcher in "${LAUNCHERS[@]}"; do
  ok "Wayland flag in $launcher" all_exec_have "/usr/share/applications/$launcher.desktop" --ozone-platform=wayland
done
for dir in /usr/lib/google/chrome /usr/lib/brave.com/brave-origin; do
  ok "system title bar in $dir" jq -e '.browser.custom_chrome_frame == false' "$dir/initial_preferences"
done

ok "signature policy for our registry" jq -e '.transports.docker["ghcr.io/ysantalla"][0].type == "sigstoreSigned"' /etc/containers/policy.json
ok "signature key is present" test -s /usr/share/bootc-images/cosign.pub
ok "sigstore attachments are enabled" grep -q use-sigstore-attachments /etc/containers/registries.d/bootc-images.yaml

case "$name" in
  base)
    for launcher in "${LAUNCHERS[@]}"; do
      ok "no Intel flags in $launcher" no_exec_has "/usr/share/applications/$launcher.desktop" "$ENCODE"
    done
    ;;
  xps16-da16260)
    for pkg in libva-intel-media-driver libva-utils powertop lm_sensors igt-gpu-tools; do
      ok "package $pkg" rpm -q "$pkg"
    done
    for launcher in "${LAUNCHERS[@]}"; do
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
