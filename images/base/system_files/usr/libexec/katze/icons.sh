#!/usr/bin/env bash
# Katze Mono for this user's own applications: web apps, Flatpaks installed for
# the user, anything that arrived after the image was built. The image already
# has the icons of its own applications in /usr/share/icons; these are written
# to the same themes in the home directory, and Plasma reads both.
#
# --only-new: only the icons the image does not have. A user with nothing of
# their own gets no copy at all, and an older copy that this script wrote is
# removed. Icons kept in both places shadowed the image's and went stale
# between an update and the next login.
set -euo pipefail

generator=/usr/libexec/katze/katze-mono.py
for variant in dark light; do
  python3 "$generator" --follow-accent --only-new --variant "$variant" > /dev/null
done
