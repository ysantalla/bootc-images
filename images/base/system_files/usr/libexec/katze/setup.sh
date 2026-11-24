#!/usr/bin/env bash
# Runs on every boot (idempotent). Gets Incus ready for wheel users.
set -euo pipefail

GROUPS_TO_SYNC=(incus-admin)

# On atomic systems, package groups live in /usr/lib/group.
# usermod only works if they also exist in /etc/group and /etc/gshadow.
for g in "${GROUPS_TO_SYNC[@]}"; do
  if ! grep -q "^${g}:" /etc/group; then
    line=$(grep "^${g}:" /usr/lib/group || true)
    if [[ -n "$line" ]]; then
      echo "$line" >> /etc/group
    else
      echo "warning: group $g not found in /etc/group or /usr/lib/group" >&2
    fi
  fi
  if grep -q "^${g}:" /etc/group && ! grep -q "^${g}:" /etc/gshadow; then
    echo "${g}:!::" >> /etc/gshadow
  fi
done

# Add every admin user (wheel) to those groups
members=$(getent group wheel | cut -d: -f4 | tr ',' ' ')
for u in $members; do
  # A stale wheel entry for a deleted user must not abort the subuid/subgid step
  if ! id "$u" &>/dev/null; then
    echo "warning: wheel member $u does not exist, skipping" >&2
    continue
  fi
  for g in "${GROUPS_TO_SYNC[@]}"; do
    if grep -q "^${g}:" /etc/group && ! id -nG "$u" | tr ' ' '\n' | grep -qx "$g"; then
      usermod -aG "$g" "$u"
    fi
  done
done

# UID/GID ranges for Incus containers
for f in /etc/subuid /etc/subgid; do
  touch "$f"
  grep -q '^root:' "$f" || echo 'root:1000000:1000000000' >> "$f"
done
