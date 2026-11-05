#!/usr/bin/env bash
# ExecCondition for bootc-update.service: a non-zero exit skips the download.
# Each image costs hundreds of MB, so do not fetch it over a metered connection.
# NetworkManager's Metered property: 1 = yes, 3 = guessed yes. Without NetworkManager, allow it.
set -euo pipefail

state=$(busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager \
  org.freedesktop.NetworkManager Metered 2>/dev/null) || exit 0

case "$state" in
  "u 1" | "u 3")
    echo "Metered connection: skipping the image download"
    exit 1
    ;;
esac
