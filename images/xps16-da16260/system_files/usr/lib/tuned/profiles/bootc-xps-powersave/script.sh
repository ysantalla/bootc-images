#!/usr/bin/env bash
# Called by tuned with "start" or "stop". Nothing to undo on stop: the next profile sets both handlers.
set -euo pipefail
[[ ${1:-} == start ]] || exit 0
exec /usr/libexec/bootc-images/platform-profile.sh quiet low-power
