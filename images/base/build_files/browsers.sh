#!/usr/bin/env bash
# Launcher flags and first-run preferences for the native browsers. Runs after chrome.sh and brave.sh.
# Both RPMs ship two .desktop files. The build fails if a vendor change stops the flags from applying.
set -euxo pipefail

FLAGS=--ozone-platform=wayland

add_flags() {
  local bin=$1 file=$2
  sed -i -E "s|^Exec=/usr/bin/${bin}( \|\$)|Exec=/usr/bin/${bin} ${FLAGS}\1|" "$file"
  grep -q "^Exec=.*${FLAGS}" "$file"
  if grep '^Exec=' "$file" | grep -qvF -- "$FLAGS"; then
    echo "Exec line without flags in $file" >&2
    exit 1
  fi
}

add_flags google-chrome-stable /usr/share/applications/google-chrome.desktop
add_flags google-chrome-stable /usr/share/applications/com.google.Chrome.desktop
add_flags brave-origin-stable /usr/share/applications/brave-origin.desktop
add_flags brave-origin-stable /usr/share/applications/com.brave.Origin.desktop

# Use the system title bar. Browsers read this on first run, so existing profiles keep their setting.
for dir in /usr/lib/google/chrome /usr/lib/brave.com/brave-origin; do
  echo '{"browser":{"custom_chrome_frame":false}}' > "$dir/initial_preferences"
done
