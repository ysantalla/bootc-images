#!/usr/bin/env bash
# First-run preferences for the native browsers. Runs after chrome.sh and brave.sh.
set -euxo pipefail

# Use the system title bar and Qt colors (system_theme 2), so both follow Plasma.
# Browsers read this on first run, so existing profiles keep their settings.
for dir in /usr/lib/google/chrome /usr/lib/brave.com/brave-origin; do
  echo '{"browser":{"custom_chrome_frame":false},"extensions":{"theme":{"system_theme":2}}}' > "$dir/initial_preferences"
done
