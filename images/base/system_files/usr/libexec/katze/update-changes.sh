#!/usr/bin/env bash
# Prints what a new image changes: the lines of its change list that the running image's
# list does not have, without the commit hash, at most five and a count of the rest.
# Usage: update-changes.sh <change list of the running image> <change list of the new image>
# Each list is "<hash> <subject>" per line, newest first, written by the build.
# Prints nothing when either list is missing, as on an image built outside CI, or when
# the new image only brings package updates.
set -euo pipefail

running=${1:?change list of the running image}
new=${2:?change list of the new image}
MAX=5

[[ -s $running && -s $new ]] || exit 0

mapfile -t added < <(grep -vxFf "$running" "$new" | cut -d' ' -f2- || true)
(( ${#added[@]} > 0 )) || exit 0

for subject in "${added[@]:0:MAX}"; do
  echo "• $subject"
done
if (( ${#added[@]} > MAX )); then
  echo "… and $(( ${#added[@]} - MAX )) more"
fi
