#!/usr/bin/env bash
# Katze Mono for this user's own applications: web apps, Flatpaks installed for
# the user, anything that arrived after the image was built. The image already
# has the icons of its own applications in /usr/share/icons; these are written
# to the same themes in the home directory, and Plasma reads both.
set -euo pipefail

generator=/usr/libexec/katze/katze-mono.py
for variant in dark light; do
  python3 "$generator" --follow-accent --variant "$variant" > /dev/null
done
