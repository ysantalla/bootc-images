# Images, updates and signatures

Building and publishing, `bootc switch`, upgrades and rollback, the signature policy, and the update notification.

## Verified

Images build, publish and verify with `cosign.pub`, and pull without credentials.

**Verified in a VM (`base`):** Incus container with IPv4, DNS and internet; Incus VM boots with IPv4, and its agent can take over 60 s to come up (`incus exec` was confirmed later on a KDE guest); `incus-admin` group (the user is no longer put in it since 2026-11-26); Flatpaks; `bootc switch` from a local disk to GHCR; `bootc upgrade`; the update notification, end to end as reported by the owner; zsh, Starship, Konsole profile and Yakuake.

**Verified in a VM (`xps16-da16260`, `45.20261105`, 2026-11-05):** boots from a local disk; `bootc switch` to GHCR; no layered packages; `bootc rollback` in both directions, with the home directory kept; Flatpak install. `bootc switch --enforce-container-sigpolicy` deploys as `ostree-image-signed`, and `bootc upgrade --check` reports no error, but that was the same digest, so no new image has been accepted or refused under it yet.

**Verified in a VM (`xps16-da16260`, `45.20261106`, 2026-11-05):**
- Enforced signatures: an image signed with the current key was accepted through both `bootc switch` and `bootc upgrade`, and an image signed with the old key was refused with a signature error, leaving the deployments unchanged.

**Verified in a VM (`xps16-da16260`, `45.20261111`, 2026-11-11):** after `bootc upgrade`, it boots kernel 7.3.3-300.fc45 and reaches Plasma on Wayland, as shown by the owner's Info Center. Nothing else was checked on it.

**Verified in the same VM (2026-11-24), after the signing key was rotated:**
- A plain `bootc switch` to `ghcr.io/ysantalla/base:latest`, without `--enforce-container-sigpolicy`, was refused ("invalid signature") while the VM ran an image with the old key. With the new key downloaded to `/etc/pki/containers` and the policy pointed at it, the same switch fetched 200 layers (4.3 GB) and the VM booted `45.20261124` from the registry, with Koko, the teal schemes and the panel backgrounds in it. `mcelog.service` is the only failed unit.
- On that image, with the policy back on the key it ships: `bootc upgrade --check` reports no changes, and with the policy pointed at another key it is refused. So the signature is checked on every pull, whatever the origin says.
- The daily warning about unsigned updates (`image-signature.sh`) said the opposite and is removed.

**Verified in the VM (2026-11-24):** after the switch to the registry, `katze-update.timer` fetched a newer image by itself and the VM booted it on the next restart. Later that day an image downloaded with `bootc upgrade` was applied by `systemctl reboot`, and one downloaded after a restart waited for the next.

## Not tested yet

- The change list in the update notification (`update-changes.sh`): it needs two published images that both carry `/usr/share/katze/changelog`.
- `pins.yml` and `prune.yml` on GitHub: opening the issue, and deleting versions, which may need the package to give this repository the Admin role.
- A pull request of documentation only: that the skipped `base / build` satisfies the required check.

- What `--enforce-container-sigpolicy` adds on top of that, and the two-step key rotation in `README.md`.
- Installing stock Kinoite and running `bootc switch`, the path `README.md` recommends. All VM results started from a bootc-image-builder disk.
- **Restart now** in the update notification. It now calls Plasma's `org.kde.Shutdown` `logoutAndReboot` and falls back to `systemctl reboot`; neither the call nor the prompt for unsaved work was tried in a session.
- A published build after the action updates of 2026-11-06 (`podman-login` 2, `push-to-registry` 3, `buildah-build` 3, `cosign-installer` 4 with cosign 2.5.2): check that an enforcing machine accepts it and that layers are still reused.
- The metered check and the old image warning on a real session. Their scripts were only exercised in a container, with stubs.

## Known small improvements, not applied

- A second update staged while the first notification is still open is not announced, because `notify-send` is still waiting. The restart applies the newest one anyway.
- A wrong ID in `flatpaks.list` makes `katze-flatpaks.service` retry every hour without end.
- `mise run build` reuses a stale local base.
