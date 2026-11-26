# The Katze theme and its icons

The global themes, color schemes, Plasma style, Katze Mono icons, fonts and the terminal's look.

## Verified

**Verified in a VM (`xps16-da16260`, `45.20261106`, 2026-11-05):**
- MesloLGS Nerd Font in Konsole, with the prompt icons, after the `fc-cache -f` fix. `tests/smoke.sh` catches the original failure.
- `breeze-custom`, `BreezeDarkCustom` (now `katze` and `KatzeDark`) and dark icons without choosing them, on a user who first logged in on an older image. Taskbar indicators follow the accent color.

**Verified in a VM (local `base` build of `main`, `45.20261124`, 2026-11-24), on a new disk and a user created by the first-boot wizard:**
- `plasma-setup` ran to its end with Fedora's theme folders removed, and the user reached Plasma.
- The new user got Katze Dark without choosing it: global theme `katze-dark`, scheme `KatzeDark`, Plasma style `katze`, icons `katze-mono`, Inter 11 and no sub-pixel text, read from the session with its own `XDG_CONFIG_DIRS`.
- One panel, 56 px thick, with the virtual desktop switcher next to the tray and `scaleIconsToFit`. KWin reports two virtual desktops in two rows.
- `katze-icons.service` ran at login (1.3 s of CPU) and wrote both themes to the home directory. It ran before `katze-flatpaks.service` finished, four minutes into the first boot.
- The four Flatpaks installed, and the Slack and ONLYOFFICE launchers were copied to the user's applications.
- `incus-admin` for the user (as images did then; since 2026-11-26 nobody is in it), no layered packages, `katze-laptop` as the default zone with `incusbr0` in `katze-incus`.
- Failed units: `mcelog.service`, as before, and the user's `grub-boot-success.service` (`grub2-set-bootflag`: "Creating tmpfile failed: Read-only file system"), which is Fedora's and not ours.
- SSH into the VM needs `sudo firewall-cmd --add-service=ssh` besides enabling `sshd`: the default zone does not let it in.

**Verified in the same VM (2026-11-24):** `panel.opacity = "translucent"`, set through Plasma's scripting on the running panel, keeps the panel translucent under a maximized Konsole, where the default made it opaque in the window's color. The owner chose it over a thin line on the panel's edge. The edited layout file, run through the same scripting, made a 56 px panel with seven widgets and that opacity; no new user has started with it yet.

**Verified in the same VM (2026-11-24):** the teal color schemes, installed in the user's home with no custom accent: Katze Dark gives a selection of 5,129,115 with white text, Katze Light 76,199,184 with black text, and panel, launcher, Dolphin, Discover and the icons follow them. The owner then chose a panel 92% opaque (over 85%, 89% and 96%) and 40% of accent in the dark icons' shape (over 16% and 28%), looking at them under a maximized Dolphin. The theme's previews and the README pictures were taken from that session, with all of it.

**Seen by the owner in the VM on the published image (2026-11-24):** Documents, Downloads, Music and the other special folders, and Network in the side panel, drawn with Katze's `folder` instead of Breeze's. The home copy of the icon theme, written at login, did not declare the directories of Breeze icons that the image's copy links (0 `breeze/places` sections against 10). Introduced with `folder` in #45; fixed in the generator.

**Seen by the owner in the VM (2026-11-24), from a copy in the home directory:** every Katze Mono icon as the glyph alone below 32 px. He asked for it after the Trash in Dolphin's side panel and the terminal and disk usage entries of its menu stood out with their shape among Breeze's line icons ("perfecto").

**Verified in the VM (2026-11-24), on its screen scaled 1.5:** with only `apps/22` (8 to 31 px), Dolphin's side panel still drew the Trash with the shape. Raising that directory's limit to 35 changed nothing and to 47 fixed it, so the panel asks for 44 px: 22 at twice the size. With `apps/22@2x` declared as a link to `apps/22` and the limit back at 31, the Trash is the glyph alone and the panel's icons keep the shape.

**Verified in the VM on the published image (`base`, `45.20261124`, the build of #61, 2026-11-24):** after `bootc upgrade` and a restart, with every test copy removed from the user's home.
- `katze-icons.service` ran at login and removed the full copy of the icon theme an earlier image had written to the home directory: nothing of Katze is left there, and the session is Katze Dark with `KatzeDark`, `katze-mono` and no custom accent.
- Plasma's lookup (`kiconfinder6`, in the session) returns the image's icons for Dolphin, the terminal, Koko and the Trash, and Breeze's for `folder-documents`.
- The image has 80 icons and their 80 small ones, `apps/22@2x` linked to `apps/22`, the 10 `breeze/places` sections, both panel backgrounds made from Breeze at 92%, and the `Katze` color scheme named by Konsole's profile.
- The owner had approved the look from copies in the home directory earlier that day: the accent edge, the glyphs in the text color on both themes, and the lines at 1.35 and 1.6.

**Checked on the XPS (2026-11-25), by reading the values Plasma 6.8.3 writes, not by eye:**
- On Katze Dark, accent `#3DAEE9` gives a selection of 47,128,170 with black text (white's contrast there is 4.39) and `#34AAE8` gives 41,125,169 with white (4.56). On Katze Light both give black.
- The blue schemes were made with `plasma-apply-colorscheme` in a throwaway home. The same steps with `#00B09A` gave the teal schemes exactly, except for four keys in `[Colors:Header][Inactive]` that were edited by hand in both.

## Not tested yet

- The `Katze` color scheme in Konsole and Yakuake, and the prompt's colors, by eye on an image. The owner saw them from copies in the home directory.
- The blue schemes (`#34AAE8`, 2026-11-25) in an image: a new user, the login screen, Konsole and the prompt. The themes' previews and the README pictures still show the teal.
- The Breeze defaults in `/etc/xdg/breezerc` for a new user. They were chosen on the XPS on 2026-11-25, in the owner's `breezerc`.
- Inter and no sub-pixel text in a real session, and on the XPS panel. `tests/smoke.sh` reads them as a user with an empty home, with the config path Plasma sets.
- Katze Light as a whole desktop, and switching at night, on an image. The owner saw on 2026-11-24, in the test VM, that the Dark Mode switch names Katze; the icon theme's light variant was seen in System Settings.
- Icons for Flatpaks that finish installing after the first login: `katze-icons.service` only runs at login.
- Zed's taskbar icon was missing once in a VM and later appeared, cause unknown.
