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
repo_disabled() { grep -q '^enabled=0' "/etc/yum.repos.d/$1.repo" && ! grep -q '^enabled=1' "/etc/yum.repos.d/$1.repo"; }

# Every Exec line of a launcher carries (or lacks) a flag
all_exec_have() { grep -q '^Exec=' "$1" && ! grep '^Exec=' "$1" | grep -qvF -- "$2"; }
no_exec_has() { ! grep '^Exec=' "$1" | grep -qF -- "$2"; }

LAUNCHERS=(google-chrome com.google.Chrome brave-origin com.brave.Origin)
ENCODE=--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL

for pkg in incus okular zsh yakuake firefox google-chrome-stable brave-origin tailscale jq; do
  ok "package $pkg" rpm -q "$pkg"
done
for pkg in toolbox distrobox; do
  ok "package $pkg is absent" not rpm -q "$pkg"
done

for unit in incus.socket tailscaled.service bootc-setup.service bootc-flatpaks.service bootc-update.timer; do
  ok "enabled $unit" enabled "$unit"
done
for unit in bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer uupd.timer; do
  ok "not enabled $unit" not enabled "$unit"
done
for unit in bootc-update-notify.service bootc-update-notify.path bootc-desktop-entries.service bootc-image-age.timer; do
  ok "user enabled $unit" user_enabled "$unit"
done

for repo in google-chrome brave-browser tailscale; do
  ok "repo $repo is disabled" repo_disabled "$repo"
done

ok "/opt links to var/opt" test "$(readlink /opt)" = var/opt
for script in /usr/libexec/bootc-images/*.sh; do
  ok "executable $script" test -x "$script"
done
ok "starship runs" starship --version
ok "factory prompt keeps its icons" grep -q $'\xee\x82\xb0' /usr/share/bootc-images/starship.toml
ok "Nerd Font is installed" test -s /usr/share/fonts/jetbrains-mono-nerd/JetBrainsMonoNerdFontMono-Regular.ttf
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
