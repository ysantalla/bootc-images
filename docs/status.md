# Status: what was tested and what was not

Moved out of `CLAUDE.md` on 2026-11-24. The log started on 2026-11-05, and each entry carries its own date. `CLAUDE.md` has the roadmap and the owner's decisions (section 10).

Add a result here when something is tested, and remove it from **Not tested yet**. Never record something as verified if it was not run.

Images build, publish and verify with `cosign.pub`, and pull without credentials.

**Verified in a VM (`base`):** Incus container with IPv4, DNS and internet; Incus VM boots with IPv4, and its agent can take over 60 s to come up (`incus exec` was confirmed later on a KDE guest); `incus-admin` group; Flatpaks; `bootc switch` from a local disk to GHCR; `bootc upgrade`; the update notification, end to end as reported by the owner; zsh, Starship, Konsole profile and Yakuake.

**Verified in a VM (`xps16-da16260`, `45.20261105`, 2026-11-05):** boots from a local disk; `bootc switch` to GHCR; no layered packages; `bootc rollback` in both directions, with the home directory kept; Flatpak install. `bootc switch --enforce-container-sigpolicy` deploys as `ostree-image-signed`, and `bootc upgrade --check` reports no error, but that was the same digest, so no new image has been accepted or refused under it yet.

**Verified in a VM (`xps16-da16260`, `45.20261106`, 2026-11-05):**
- Enforced signatures: an image signed with the current key was accepted through both `bootc switch` and `bootc upgrade`, and an image signed with the old key was refused with a signature error, leaving the deployments unchanged.
- MesloLGS Nerd Font in Konsole, with the prompt icons, after the `fc-cache -f` fix. `tests/smoke.sh` catches the original failure.
- `breeze-custom`, `BreezeDarkCustom` (now `katze` and `KatzeDark`) and dark icons without choosing them, on a user who first logged in on an older image. Taskbar indicators follow the accent color.
- `docker run`, and `docker compose up` and `down` with nginx, a published port and a named volume, which survives `down`.
- Haruna opens an HEVC file from Dolphin by default and shows the picture. The owner heard its audio on 2026-11-06. Hardware decode was not checked.

**Verified in a VM (`xps16-da16260`, `45.20261111`, 2026-11-11):** after `bootc upgrade`, it boots kernel 7.3.3-300.fc45 and reaches Plasma on Wayland, as shown by the owner's Info Center. Nothing else was checked on it.

**Verified in a VM (local `base` build, 2026-11-06):** `incus start --console=vga` opened an empty Incus VM's UEFI screen in `spicy`, in a test build with `spice-gtk-tools`. The owner found it ugly, so it is not in the image.

**Verified in a VM, nested (local `base` build, 2026-11-06):** an openSUSE Tumbleweed KDE Incus VM (`images:opensuse/tumbleweed/desktop-kde`) reached Plasma on Wayland, and `incus exec` reached it, with `spice-vdagentd` active. KRDC's nightly Flatpak (`26.11.70`) showed its screen with working input, through a temporary `socat` bridge to port 5930, since KRDC only speaks TCP or `.vv` files. The owner reports other features worked, within the limits of nesting; audio could not be tested. Nothing from KRDC is in the image.

**Verified in a VM, nested (`xps16-da16260` guest of QEMU, 2026-11-06):** `mise run vm-incus base` imported a `base` disk and booted it as `base-test`, with IPv4, and KRDC's nightly Flatpak showed its Plasma welcome screen through the `socat` bridge. A second run left the VM as it was. `incus exec` does not work on these disks (`VM agent isn't currently running`), so use SSH or `incus console`. They have no `spice-vdagent` either, so KRDC warns about it, and clipboard and resizing should not work. Audio, and running the whole flow on the XPS, are untested.

**Not tested yet:**
- Nothing is verified on the real XPS.
- `mise run power` with `sudo` and real RAPL. Only its load was run on its own: interrupting it leaves no `yes` running once `--load` seconds pass.
- `incus admin init` with a btrfs pool, as `README.md` now says, instead of `--minimal`'s `dir` pool. The prompts it describes come from Incus's interactive init, not from a run.
- `docker compose` on the owner's real projects, which use profiles, health checks and builds. Rootless Podman can behave differently from Docker on low ports, bind mount permissions and SELinux labels.
- A user created after the Plasma defaults shipped.
- Inter and no sub-pixel text in a real session, and on the XPS panel. `tests/smoke.sh` reads them as a user with an empty home, with the config path Plasma sets.
- Intel hardware decode in Haruna on the XPS. `vm-up` sound was heard in YouTube and in Haruna, in the VM.
- Installing stock Kinoite and running `bootc switch`, the path `README.md` recommends. All VM results started from a bootc-image-builder disk.
- **Restart now** in the update notification. It now calls Plasma's `org.kde.Shutdown` `logoutAndReboot` and falls back to `systemctl reboot`; neither the call nor the prompt for unsaved work was tried in a session.
- A published build after the action updates of 2026-11-06 (`podman-login` 2, `push-to-registry` 3, `buildah-build` 3, `cosign-installer` 4 with cosign 2.5.2): check that an enforcing machine accepts it and that layers are still reused.
- The Slack launcher in a real session. It gained `--file-forwarding`, which `man flatpak-run` says `@@u %U @@` needs. Check that it opens `slack://` links.
- Zed's taskbar icon was missing once in a VM and later appeared, cause unknown.
- Microsoft fonts in `~/.local/share/fonts` as seen by the ONLYOFFICE Flatpak.
- On the XPS: VRR and display glitches (`kscreen-doctor -o`), Intel encode and decode in Chrome (steps in `README.md`), Wayland screen sharing in a real call, temperature, battery and suspend, and the internal camera: sources disagree on whether it gives a picture with the stock kernel (`docs/xps16-checklist.md`).
- Whether the Intel video flags in `xps16-da16260` are needed, or do anything: compare a real video with and without them on the XPS. Chromium's own `vaapi.md` uses `AcceleratedVideoEncoder`; the `Vaapi*` names are said to be from before Chromium 131.
- `mcelog.service` failed in the VM, probably because it is a VM. Check it on the XPS.
- The metered check and the old image warning on a real session. Their scripts were only exercised in a container, with stubs.
- Flatpak launchers on a real session: Slack and ONLYOFFICE arguments, and `TryExec` hiding an app that is not installed. The copy logic and overrides were only exercised in a container.
- The system title bar and Qt colors in a real browser. Fresh headless Chrome and Brave profiles with `--force-first-run` wrote both preferences; additional profiles and how the colors look were not checked.
- GNOME Network Displays on KDE with real Wi-Fi and a real display. Some Samsung TVs are reported to need `dnsmasq`, which is not in the image.
- Installing a system from an ISO through a VM viewer.
- Opening a `.rar` in Ark. `unar` is the backend, since neither `rar` nor `unrar` is in the image.
- Booting an image with the Katze theme: a new user getting Katze Dark with its 56 px panel, two virtual desktops created from `/etc/xdg/kwinrc`, `katze-icons.service` at login, and the first-boot wizard (`plasma-setup`) without Fedora's theme folders. CI built it and ran `tests/smoke.sh` on 2026-11-24; the themes were only seen in a VM with the files installed for its user.
- The thermald drop-in and the `katze-xps-*` tuned profiles on real hardware. A VM has no platform-profile handlers, and thermald does not run there.

## Known small improvements, not applied

- A second update staged while the first notification is still open is not announced, because `notify-send` is still waiting. The restart applies the newest one anyway.
- A wrong ID in `flatpaks.list` makes `katze-flatpaks.service` retry every hour without end.
- Nothing prunes old tags on GHCR.
- `mise run build` reuses a stale local base.
