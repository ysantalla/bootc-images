#!/usr/bin/env bash
# Warns the logged-in user when this machine follows our registry without requiring the
# image's signature. The image carries the policy and the key, but a machine only enforces
# them after `bootc switch --enforce-container-sigpolicy`, and nothing else shows the gap.
set -euo pipefail

REGISTRY=ghcr.io/ysantalla

# Works without root. Anything unexpected (no rpm-ostree, another format) stays quiet.
ref=$(rpm-ostree status --booted --json 2>/dev/null |
  jq -r '.deployments[] | select(.booted) | ."container-image-reference" // empty' 2>/dev/null) || exit 0

# Local builds and other registries are the owner's tests, not what updates come from
[[ "$ref" == *"$REGISTRY/"* ]] || exit 0
[[ "$ref" == ostree-image-signed:* ]] && exit 0

image=${ref##*"$REGISTRY/"}
notify-send --app-name="System update" --icon=dialog-warning \
  "Updates are not checked for a signature" \
  "Run once: sudo bootc switch --enforce-container-sigpolicy $REGISTRY/$image"
