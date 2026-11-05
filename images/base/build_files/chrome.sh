#!/usr/bin/env bash
# Native Google Chrome (official RPM), used for video calls.
# Same /opt workaround as brave.sh: install into a real /opt, move it to /usr/lib, link it back with tmpfiles.
set -euxo pipefail

# Temporary real /opt
rm -f /opt
mkdir -p /opt

cat > /etc/yum.repos.d/google-chrome.repo <<'REPO'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
REPO

dnf5 -y install google-chrome-stable

# Move it into /usr (shipped with the image, read-only)
mv /opt/google /usr/lib/google

# Restore /opt -> var/opt like any Fedora atomic system
rmdir /opt
ln -s var/opt /opt

# The machine never queries Google's repo: updates arrive with the image
sed -i 's/^enabled=.*/enabled=0/' /etc/yum.repos.d/google-chrome.repo
