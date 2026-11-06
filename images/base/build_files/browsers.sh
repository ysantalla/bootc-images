#!/usr/bin/env bash
# First-run preferences for the native browsers. Runs after chrome.sh and brave.sh.
set -euxo pipefail

# Use the system title bar. Browsers read this on first run, so existing profiles keep their setting.
for dir in /usr/lib/google/chrome /usr/lib/brave.com/brave-origin; do
  echo '{"browser":{"custom_chrome_frame":false}}' > "$dir/initial_preferences"
done
