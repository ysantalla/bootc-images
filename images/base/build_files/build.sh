#!/usr/bin/env bash
# Runs ONCE at image build time (never on the machine).
set -euxo pipefail

# 1. Packages (one per line in packages.txt)
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' /ctx/packages.txt)
dnf5 -y install "${PKGS[@]}"

# Images open in Koko. Plasma's list of defaults names Gwenview, which is not in the image,
# so they opened in a browser. The list is Fedora's: only the name of the viewer changes.
MIMEAPPS=/usr/share/applications/kde-mimeapps.list
grep -q '^image/png=org.kde.gwenview.desktop' "$MIMEAPPS"
sed -i '/^image\//s/org\.kde\.gwenview\.desktop/org.kde.koko.desktop/' "$MIMEAPPS"
grep -q '^image/png=org.kde.koko.desktop' "$MIMEAPPS"
test -f /usr/share/applications/org.kde.koko.desktop

# Not used here: Incus covers containers (also removes the Toolbx login message)
dnf5 -y remove toolbox distrobox

# From kinoite-main, and the owner does not use it
dnf5 -y remove nvtop

# 2. Native Brave Origin (official RPM, with the /opt workaround)
/ctx/brave.sh

# Native Google Chrome (same /opt workaround)
/ctx/chrome.sh

# System title bar for both browsers
/ctx/browsers.sh

# zsh, Starship, Nerd Font, Konsole and Yakuake defaults
/ctx/shell.sh

# Katze Dark as the look of a new user, and Katze Mono icons for the image's applications
/ctx/plasma-theme.sh

# Tailscale, from its official repo
/ctx/tailscale.sh

# Signature policy for machines that opt in
/ctx/signing.sh

# 3. Make our scripts executable
chmod 0755 /usr/libexec/katze/*.sh

# 4. Exactly one updater: ours (avoid two timers fighting each other)
systemctl disable rpm-ostreed-automatic.timer 2>/dev/null || true
systemctl disable uupd.timer 2>/dev/null || true

# Firewall: unknown networks get the strict zone; trusted ones are set to FedoraWorkstation by hand
sed -i 's/^DefaultZone=.*/DefaultZone=katze-laptop/' /etc/firewalld/firewalld.conf
grep -qx 'DefaultZone=katze-laptop' /etc/firewalld/firewalld.conf

# 5. Services
systemctl enable \
  incus.socket \
  tailscaled.service \
  katze-setup.service \
  katze-flatpaks.service \
  katze-update.timer

# Per-user: the API socket that `docker compose` talks to
systemctl --global enable podman.socket

# Quiet the "Emulate Docker CLI" line podman-docker prints on every command
touch /etc/containers/nodocker

# Per-user: announces a downloaded update at login and when one arrives
systemctl --global enable \
  katze-update-notify.service \
  katze-update-notify.path

# Per-user: installs the launchers for Flatpak apps at login
systemctl --global enable katze-desktop-entries.service

# Per-user: warns when the running image is old
systemctl --global enable katze-image-age.timer

# Per-user: Katze Mono icons for the user's own applications
systemctl --global enable katze-icons.service

# Fonts installed outside RPM are missing from the cache RPM scriptlets generate. Machines
# cannot fix it: /usr is read-only, and all its mtimes are 0, so the cache still looks valid.
fc-cache -f

# Read by image-age.sh
date -u +%s > /usr/share/katze/build-time

dnf5 clean all
rm -rf /var/log/dnf5.log /var/lib/dnf
