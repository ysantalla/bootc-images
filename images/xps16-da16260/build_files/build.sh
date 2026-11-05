#!/usr/bin/env bash
# Runs ONCE at image build time (never on the machine).
set -euxo pipefail

# 1. Packages (one per line in packages.txt)
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' /ctx/packages.txt)
dnf5 -y install "${PKGS[@]}"

# 2. Intel hardware video in the native browsers (Chromium does not officially support VA-API on Linux)
FLAGS=--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL
for file in \
  /usr/share/applications/google-chrome.desktop \
  /usr/share/applications/com.google.Chrome.desktop \
  /usr/share/applications/brave-origin.desktop \
  /usr/share/applications/com.brave.Origin.desktop; do
  sed -i -E "s|^(Exec=/usr/bin/[a-z-]+ --ozone-platform=wayland)|\\1 ${FLAGS}|" "$file"
  grep -q "^Exec=.*${FLAGS}" "$file"
  if grep '^Exec=' "$file" | grep -qvF -- "$FLAGS"; then
    echo "Exec line without flags in $file" >&2
    exit 1
  fi
done

# Next steps for this machine go here (one at a time, once base is stable):
#   - auto-boost (RAPL PL2 60 W on AC under load) as a systemd service in /usr
#   - .dellptl kernel for IPU7 webcam / IR / ISH (needs initramfs + Secure Boot signing)

dnf5 clean all
