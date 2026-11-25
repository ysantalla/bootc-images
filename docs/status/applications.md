# Applications

Browsers, Flatpaks and their launchers, the Docker commands, and the applications added to the image.

## Verified

**Verified in a VM (`xps16-da16260`, `45.20261106`, 2026-11-05):**
- `docker run`, and `docker compose up` and `down` with nginx, a published port and a named volume, which survives `down`.
- Haruna opens an HEVC file from Dolphin by default and shows the picture. The owner heard its audio on 2026-11-06. Hardware decode was not checked.

## Not tested yet

- Koko opening a picture from Dolphin, and how it looks with the Katze theme. On the published image `45.20261124`, `gio mime` in the session names it for PNG.
- `docker compose` on the owner's real projects, which use profiles, health checks and builds. Rootless Podman can behave differently from Docker on low ports, bind mount permissions and SELinux labels.
- The Slack launcher in a real session. It gained `--file-forwarding`, which `man flatpak-run` says `@@u %U @@` needs. Check that it opens `slack://` links.
- Microsoft fonts in `~/.local/share/fonts` as seen by the ONLYOFFICE Flatpak.
- Flatpak launchers on a real session: Slack and ONLYOFFICE arguments, and `TryExec` hiding an app that is not installed. The copy logic and overrides were only exercised in a container.
- The system title bar and Qt colors in a real browser. Fresh headless Chrome and Brave profiles with `--force-first-run` wrote both preferences; additional profiles and how the colors look were not checked.
- GNOME Network Displays on KDE with real Wi-Fi and a real display. Some Samsung TVs are reported to need `dnsmasq`, which is not in the image.
- Opening a `.rar` in Ark. `unar` is the backend, since neither `rar` nor `unrar` is in the image.
