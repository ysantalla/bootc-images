#!/usr/bin/env bash
# Runs ONCE at image build time (never on the machine).
set -euxo pipefail

# 1. Packages (one per line in packages.txt)
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' /ctx/packages.txt)
dnf5 -y install "${PKGS[@]}"

# Next steps for this machine go here (one at a time, once base is stable):
#   - auto-boost (RAPL PL2 60 W on AC under load) as a systemd service in /usr
#   - .dellptl kernel for IPU7 webcam / IR / ISH (needs initramfs + Secure Boot signing)

dnf5 clean all
