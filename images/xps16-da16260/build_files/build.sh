#!/usr/bin/env bash
# Runs ONCE at image build time (never on the machine).
set -euxo pipefail

# 1. Packages (one per line in packages.txt)
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' /ctx/packages.txt)
dnf5 -y install "${PKGS[@]}"

# 2. Intel hardware video in the native browsers (Chromium does not officially support VA-API on Linux),
# and the camera through PipeWire, where katze-camera.service offers it
FLAGS=--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL,WebRtcPipeWireCamera
for file in \
  /usr/share/applications/google-chrome.desktop \
  /usr/share/applications/com.google.Chrome.desktop \
  /usr/share/applications/brave-origin.desktop \
  /usr/share/applications/com.brave.Origin.desktop; do
  sed -i -E "s|^(Exec=/usr/bin/[a-z-]+)|\\1 ${FLAGS}|" "$file"
  grep -q "^Exec=.*${FLAGS}" "$file"
  if grep '^Exec=' "$file" | grep -qvF -- "$FLAGS"; then
    echo "Exec line without flags in $file" >&2
    exit 1
  fi
done

# 3. Power profiles: KDE's slider picks our tuned profiles, which reach Dell's thermal modes.
# tuned-ppd treats a change of the legacy platform_profile it did not make as a firmware hotkey
# and switches back, which undoes power saver on this machine, so that monitor is off.
PPD=/etc/tuned/ppd.conf
sed -i -E \
  -e 's/^sysfs_acpi_monitor=.*/sysfs_acpi_monitor=false/' \
  -e 's/^power-saver=.*/power-saver=katze-xps-powersave/' \
  -e 's/^performance=.*/performance=katze-xps-performance/' \
  -e '/^\[profiles\]/,/^\[battery\]/ s/^balanced=.*/balanced=katze-xps-balanced/' \
  -e '/^\[battery\]/,$ s/^balanced=.*/balanced=katze-xps-balanced-battery/' \
  "$PPD"
for line in sysfs_acpi_monitor=false power-saver=katze-xps-powersave balanced=katze-xps-balanced \
  performance=katze-xps-performance balanced=katze-xps-balanced-battery; do
  grep -qx "$line" "$PPD"
done

# 4. OLED: the screen dims and turns off early, so a still picture does not stay lit.
# Defaults for a new user, in /etc/xdg: System Settings > Power Management overrides them.
display() { # display <power state> <key> <value>
  kwriteconfig6 --file /etc/xdg/powerdevilrc --group "$1" --group Display --key "$2" "$3"
}
display AC DimDisplayIdleTimeoutSec 120
display AC TurnOffDisplayIdleTimeoutSec 180
display Battery DimDisplayIdleTimeoutSec 60
display Battery TurnOffDisplayIdleTimeoutSec 120
grep -q '^TurnOffDisplayIdleTimeoutSec=180$' /etc/xdg/powerdevilrc

# 5. The internal camera, offered from our own process (camera.py)
systemctl --global enable katze-camera.service

# Next steps for this machine go here, one at a time. CLAUDE.md section 10 has the roadmap
# and docs/xps16-checklist.md what to check on the machine first.

dnf5 clean all
rm -rf /var/log/dnf5.log /var/lib/dnf
