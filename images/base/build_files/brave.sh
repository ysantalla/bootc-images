#!/usr/bin/env bash
# Native Brave Origin (official RPM, no Rewards/Wallet/VPN/AI), not a Flatpak.
# The RPM installs into /opt, which on atomic systems is /var/opt (not shipped with the image).
# Workaround: install into a real /opt during the build, move it to /usr/lib and link it back with tmpfiles.
set -euxo pipefail

# Temporary real /opt
rm -f /opt
mkdir -p /opt

dnf5 config-manager addrepo \
  --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
dnf5 -y install brave-origin

# Move it into /usr (shipped with the image, read-only)
mv /opt/brave.com /usr/lib/brave.com

# Restore /opt -> var/opt like any Fedora atomic system
rmdir /opt
ln -s var/opt /opt

# The machine never queries Brave's repo: updates arrive with the image
sed -i 's/^enabled=.*/enabled=0/' /etc/yum.repos.d/brave-browser.repo
