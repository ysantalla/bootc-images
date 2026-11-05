#!/usr/bin/env bash
# Runs ONCE at image build time (never on the machine).
set -euxo pipefail

# 1. Packages (one per line in packages.txt)
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' /ctx/packages.txt)
dnf5 -y install "${PKGS[@]}"

# Not used here: Incus covers containers (also removes the Toolbx login message)
dnf5 -y remove toolbox distrobox

# 2. Native Brave Origin (official RPM, with the /opt workaround)
/ctx/brave.sh

# Native Google Chrome (same /opt workaround)
/ctx/chrome.sh

# zsh, Starship, Nerd Font, Konsole and Yakuake defaults
/ctx/shell.sh

# Tailscale, from its official repo
/ctx/tailscale.sh

# 3. Make our scripts executable
chmod 0755 /usr/libexec/bootc-images/*.sh

# 4. Exactly one updater: ours (avoid two timers fighting each other)
systemctl disable rpm-ostreed-automatic.timer 2>/dev/null || true
systemctl disable uupd.timer 2>/dev/null || true

# 5. Services
systemctl enable \
  incus.socket \
  tailscaled.service \
  bootc-setup.service \
  bootc-flatpaks.service \
  bootc-update.timer

# Per-user: announces a downloaded update at login and when one arrives
systemctl --global enable \
  bootc-update-notify.service \
  bootc-update-notify.path

dnf5 clean all
