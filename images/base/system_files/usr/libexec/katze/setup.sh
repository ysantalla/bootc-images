#!/usr/bin/env bash
# Runs on every boot (idempotent). Gets Incus ready: its group, and ID ranges for containers.
# Nobody is put in incus-admin: it controls the Incus daemon, which is root without a password
# (a privileged container with / mounted). Incus is used with sudo until each user gets a
# restricted project (docs/secrets-and-devbox.md, section 8.2).
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

# Earlier images added every wheel user to incus-admin. Take them out once; someone added by hand
# later stays. Groups only change at the next login.
marker=/var/lib/katze/incus-admin-cleared
if [[ ! -e $marker ]] && grep -q '^incus-admin:' /etc/group; then
  for u in $(getent group incus-admin | cut -d: -f4 | tr ',' ' '); do
    gpasswd -d "$u" incus-admin >/dev/null && echo "removed $u from incus-admin: use sudo incus"
  done
  install -d -m 0755 /var/lib/katze
  touch "$marker"
fi

# UID/GID ranges for Incus containers
for f in /etc/subuid /etc/subgid; do
  touch "$f"
  grep -q '^root:' "$f" || echo 'root:1000000:1000000000' >> "$f"
done
