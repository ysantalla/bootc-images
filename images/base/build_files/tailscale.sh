#!/usr/bin/env bash
# Tailscale from its official repo. Login happens on the machine, and its state stays in /var/lib/tailscale.
set -euxo pipefail

dnf5 config-manager addrepo \
  --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 -y install tailscale

# The machine never queries Tailscale's repo: updates arrive with the image
sed -i 's/^enabled=.*/enabled=0/' /etc/yum.repos.d/tailscale.repo
