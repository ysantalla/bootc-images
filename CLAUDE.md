# CLAUDE.md

Guidance for Claude Code (and any other contributor) working in this repository.
Read it fully before changing anything. `README.md` is the user-facing guide; this file explains how the project is built, the rules it follows, and how to make changes safely.

---

## 1. Project overview

`katze-os` produces personal, immutable operating system images for the owner's machines. Each image is an OCI container image that [bootc](https://bootc-dev.github.io/bootc/) deploys as a full OS: atomic updates, a read-only `/usr`, and one-command rollback.

- **Owner:** `ysantalla` (GitHub)
- **Registry:** `ghcr.io/ysantalla/<image>`
- **Desktop:** KDE Plasma (Fedora Kinoite family)
- **Build:** GitHub Actions, daily, signed with cosign
- **Goal:** a near-stock, robust system that never needs manual package layering on the machine. Everything that lives in `/usr` is defined here, in code.

### Images

| Image | FROM | Purpose |
|---|---|---|
| `base` | `ghcr.io/ublue-os/kinoite-main:${FEDORA_VERSION}` | Hardware-agnostic layer shared by every machine |
| `xps16-da16260` | `ghcr.io/ysantalla/base:${FEDORA_VERSION}` | Dell XPS 16 (2026), model DA16260 |

The layering is strict: **`base` contains nothing hardware-specific**, and machine images contain **only** what their hardware needs.

### What each layer provides

**From `kinoite-main` (upstream, not ours):** KDE Plasma, full ffmpeg codecs, Podman, Flathub, bootc.

**`base` adds:**
- **Incus:** system containers and KVM virtual machines (`incus launch ... --vm`). The `incus` RPM does not pull in QEMU, so `packages.txt` adds it, and Incus VMs need `qemu-device-display-virtio-vga`. The `katze-incus` firewalld zone only gives instances DHCP and DNS, so they cannot reach the host's other ports, and the `katze-incus-out` policy lets them reach other networks. The `katze-incus-private` policy runs before it and rejects private addresses (RFC 1918, Tailscale's 100.64.0.0/10, link-local, IPv6 unique local), so an instance reaches the internet but not the local network or the tailnet. Tested in a VM on 2026-11-21 and 2026-11-24 with containers and IPv4 only: Incus VMs, IPv6 and a real tailnet are untested.
- **Brave Origin:** native RPM (`brave-origin`), the stripped-down Brave without Rewards, Wallet, VPN or AI features.
- **Google Chrome:** native RPM (`google-chrome-stable`), used for video calls. Same `/opt` handling as Brave (`chrome.sh`).
- **Browser defaults** (`browsers.sh`): `initial_preferences` asks for the system title bar and Qt colors on first run, in new profiles only. Both browsers chose Wayland without any flag in a VM (Chrome and Brave on `45.20261106`), so the image sets none.
- **Docker commands:** `podman-docker` makes `docker` run Podman, and `docker compose` runs the real Compose through the per-user `podman.socket`. `DOCKER_HOST` points graphical sessions at that socket (`environment.d`). `60-katze-compose.conf` silences the provider notice.
- **Katze theme:** two global themes, Katze Dark and Katze Light, in `system_files`. Each sets a color scheme (`KatzeDark`, `KatzeLight`), the `katze` Plasma style, a Katze Mono icon theme and a desktop layout: one panel, 56 px thick and always translucent, so it stays apart from a maximized window, with the virtual desktop switcher next to the tray and tray icons that scale with the panel. `plasma-theme.sh` also gives a new user two virtual desktops, one above the other, since Plasma hides the switcher with only one. `plasma-theme.sh` makes Katze Dark the default for new users and removes Fedora's global themes (their package stays, since `plasma-workspace` requires it), so only Breeze's and Katze's are offered. The Dark Mode switch in the panel, and switching at night, go between the two (`DefaultDarkLookAndFeel`, `DefaultLightLookAndFeel`). The layout only reaches a new user, or someone who applies the theme with its desktop layout. Applying a global theme clears a custom accent color.
- **Katze's color:** a blue, `#34AAE8` (52,170,232), in both color schemes. The owner chose it on 2026-11-25 over the teal `#00B09A`. The schemes hold what Plasma writes when that accent is applied to Breeze's colors with `TintFactor=0.05`, plus `[Colors:Header][Inactive]`, which Plasma leaves alone and takes `[Colors:Header]`'s accent. So the selection is a darker blue with white text in Katze Dark, and a light blue with black text in Katze Light. Plasma picks that text by contrast, and no scheme or style can force it: `#34AAE8` is the lightest shade of its hue that keeps white, and Breeze's own `#3DAEE9` gives black. A custom accent still works on top. The login screen (Plasma Login Manager) takes the color from the image's default scheme, unless settings were copied to it from System Settings.
- **`katze` Plasma style:** Breeze with the owner's taskbar indicators and a panel that is 92% opaque instead of 85% (`plasma-theme.sh` makes its two files from the Breeze of each build, see the style's `README.md`), moved here from `ysantalla/plasma-tips` (it was `breeze-custom`). It has no `colors` file on purpose: with one, the panel and the launcher keep those colors whatever the scheme and accent are.
- **Windows and menus:** `plasma-theme.sh` sets the owner's Breeze choices in `/etc/xdg/breezerc`: no outline around windows, a medium shadow and menus 79% opaque. They reach a user without these keys in `~/.config/breezerc`.
- **Katze Mono icons:** `katze-mono.py` draws one icon per application, a thin line glyph on a rounded shape, painted by the color scheme and the accent. `plasma-theme.sh` runs it at build time for the image's applications and for every alias, which covers Flatpaks that are not installed yet, into `/usr/share/icons/katze-mono` and `katze-mono-light`. `katze-icons.service` runs it at login for the user's own applications, into the same themes in the home directory. It also draws the run, folder, document and trash icons, which System Settings uses to preview an icon theme, so the Trash takes the shape too. Choices are in `usr/share/katze/katze-mono/aliases.toml`, and its `README.md` has the design rules and what was learned about Plasma: tray names, shortened names, colors. A panel that is already running keeps the icons it has drawn until `plasma-plasmashell.service` restarts. The owner's Tela icon theme is not included.
- **Interface fonts:** Inter 11 in `/etc/xdg/kdeglobals`, with no sub-pixel text in KDE or fontconfig, since OLED panels often lack RGB stripes (`plasma-theme.sh`). Noto stays the system sans-serif.
- **Koko:** native RPM, the image viewer KDE proposes as Gwenview's successor, chosen by the owner on 2026-11-24 over Gwenview. Fedora has 26.08, where it is called Photos; 26.12 arrives through the daily build. `build.sh` makes it the default for images in Fedora's `kde-mimeapps.list`, which names Gwenview: without that they opened in a browser.
- **Okular:** native RPM.
- **KCalc:** native RPM, 3 MiB. `kinoite-main` ships no calculator.
- **Haruna:** native RPM. It plays through `mpv-libs` and the full ffmpeg, both from negativo17 via `kinoite-main`. `yt-dlp` comes as a weak dependency.
- **Office fonts:** Carlito and Caladea, with the same metrics as Calibri and Cambria. Liberation already covers Arial, Times New Roman and Courier New. Microsoft's fonts stay out because this image is public; Fedora's `mscore-fonts` is an unrelated MuseScore package.
- **Terminal:** zsh with autosuggestions and syntax highlighting, Starship with a Powerlevel10k-style factory prompt, MesloLGS Nerd Font, Konsole and Yakuake defaults (`shell.sh`), a `Katze` color scheme for Konsole (Breeze's palette on the theme's background, with Katze's blue as the bright blue), and `fastfetch` for a system summary. Personal settings go in `~/.zshrc`, and `~/.config/starship.toml` replaces the factory prompt. Its icons are Private Use characters that editors and copying can lose, so check them after editing (`grep -c $'\ue0b0'`).
- **Tailscale:** private network between the owner's devices (`tailscale.sh`). Login is done once on each machine with `sudo tailscale up`.
- **Firewall:** the default zone `katze-laptop` only lets in DHCPv6, mDNS, KDE Connect and GNOME Network Displays. Trusted networks go to `FedoraWorkstation` by hand, and the tailnet is accepted.
- **System Flatpaks** from a declarative list (Zed, Slack, ONLYOFFICE, GNOME Network Displays).
- **Flatpak launchers:** Slack and ONLYOFFICE get the owner's launch arguments through `katze-desktop-entries.service` and Flatpak overrides through `katze-flatpak-overrides.conf`.
- **Zed window borders:** `ZED_WINDOW_DECORATIONS=server` in `katze-flatpak-overrides.conf` makes KWin draw them. Zed keeps its own bar below, and the variable overrides Zed's `window_decorations` setting. Seen working with that setting on the owner's machine, not yet through the override.
- **First-boot and every-boot setup:** the `incus-admin` group, with nobody in it, and subuid/subgid ranges. That group is root without a password, so Incus is used with `sudo`; `setup.sh` took out, once, the wheel users that images before 2026-11-25 added (marker `/var/lib/katze/incus-admin-cleared`). A restricted project per user is planned (`docs/secrets-and-devbox.md`, section 8.2).
- **Our own update timer** (wall-clock, every 6 h, `Persistent=true`, skipped on battery and metered connections), which replaces any upstream updater, plus a desktop notification when an update is ready, which lists up to five of the changes the new image brings: CI writes the last commits that touch `images/` to `/usr/share/katze/changelog`, and `update-changes.sh` shows the ones the running image does not have. It only announces: it never reboots by itself. A daily user timer warns if the running image is over 14 days old.
- **Signature policy:** `signing.sh` adds our registry and key to `policy.json`, whose default, from Universal Blue, is to reject. So a machine running the image checks our signature on every pull from `ghcr.io/ysantalla`, with or without `--enforce-container-sigpolicy`: on 2026-11-24 a plain `bootc switch` and a plain `bootc upgrade` were both refused when the key did not match. Only the first switch from stock Kinoite, whose own policy accepts anything, is not checked. `mise run switch` still passes the flag, which makes bootc refuse an origin whose policy would accept unsigned images (from bootc's documentation, not tried). **A key rotation therefore locks out every installed machine**: see `README.md`, "Rotating the signing key".

**`xps16-da16260` adds:** `libva-intel-media-driver` and `libva-utils` for hardware video decode (H.264, HEVC, VP9, AV1) on the Arc B390, which `kinoite-main` also ships today and stay listed so this machine keeps them, plus `powertop`, `lm_sensors`, `igt-gpu-tools` and `kernel-tools` (`turbostat`) to measure battery, temperature, GPU use and package power on this hardware. Its `build.sh` also adds Intel video and camera flags to the browser launchers, and makes the screen dim and turn off early for the OLED panel: off after 3 minutes on AC and 2 on battery, as PowerDevil defaults in `/etc/xdg/powerdevilrc` that a user can change.

It also carries two fixes adapted from `onuralpszr/xps-fedora` (commit `98e8400`), which reports both problems on an X7 358H. Neither is confirmed on this machine yet:
- **thermald:** a drop-in runs `thermald-wait.sh`, which waits up to 30 s for RAPL, coretemp and the `TCPU` zone, because thermald otherwise gives up on Panther Lake until the next boot.
- **Power profiles:** four `katze-xps-*` tuned profiles call `platform-profile.sh`, which sets Dell's thermal mode (`dell-pc`) and Intel's SoC power slider separately, since the legacy `platform_profile` only offers what both share. `build.sh` points `/etc/tuned/ppd.conf` at them and turns off `sysfs_acpi_monitor`. The image has `tuned-ppd`, not power-profiles-daemon, so there is no `powerprofilesctl`.

And the internal camera: `camera.py` (`katze-camera.service`, a user service) opens it through libcamera at 1440p, in a child process, since 1080p and less use a sensor mode that does not work and abort libcamera. It turns the picture over, scales it to 1080p and offers it as one PipeWire camera, on only while an application uses it and off before a suspend. `60-katze-camera.conf` takes libcamera and the raw IPU7 nodes out of WirePlumber, where the abort restarted the sound, and the browser launchers get `WebRtcPipeWireCamera`. It needs no kernel module and no closed Intel library, unlike xps-fedora and Omarchy.

And the infrared camera's driver, `hm1092`, out of tree and signed with the owner's module key (enrolled as a MOK on this machine), in `/usr/lib/modules/<kernel>/updates`. `katze-hm1092.conf` keeps it from loading by itself. The user can open that camera's nodes, and no udev rule may change it: libcamera drops the normal camera too when one node of the graph is denied. So the driver only starts the sensor for a process with CAP_SYS_RAWIO. `ir-camera` (C, compiled in a stage of the Containerfile) reads it for root: `katze-ir-camera.socket` gives 5 seconds of PGM frames with the lamp on, which the reader, its time limits and `ExecStopPost` turn off. It has not run on the machine.

And face unlock on the lock screen, with that camera: `katze-face` (C, compiled in a stage of the Containerfile against the OpenVINO that dictation installs, plus its ONNX reader) finds the face with YuNet and describes it with SFace, both from opencv_zoo and pinned in `face/build.sh`, on the CPU. `sudo /usr/libexec/katze/katze-face add <user>` registers 5 frames each time (128 numbers each, no picture) in `/var/lib/katze/face/<uid>`, and `test` shows how close each frame comes. The lock screen runs PAM as the user, so it cannot read the camera: `/etc/pam.d/kde-fingerprint`, which kscreenlocker tries next to the password while its prompt is shown, runs `katze-face-check`, which asks `katze-face.socket` (anyone may ask, only about themselves: the service reads the uid from the socket). Two frames in a row with a cosine similarity of 0.5 unlock. Fedora's fingerprint stack is not used there, since this machine's reader has no libfprint driver, and `build.sh` changes the prompt's "(or scan your fingerprint on the reader)" to "(or look at the camera)", untranslated, with a warning if Plasma changes that text. A user with no face registered sees nothing new. Login, sudo and the disk do not use it. It has not run on the machine.

And voice dictation in Spanish on the NPU or the GPU: Voxtype (its ONNX binary has OpenVINO) with Intel's OpenVINO GenAI SDK, both pinned in `dictation.sh`, and Fedora's `intel-npu-driver`. Fedora's OpenVINO has no NPU plugin, and the SDK brings the NPU's compiler, so Intel's own driver package is not needed. The GPU needs `intel-opencl`, which brings clang and LLVM libraries. The NPU is the default, Voxtype goes on with the GPU and then the CPU without it, and `dictation-setup.sh gpu` or `npu` changes it. The model (`whisper-large-v3-turbo-int8`, 790 MB) is not in the image: `dictation-setup.sh` downloads it once for each user, checked by sha256, and `katze-dictation.service` waits for it. Meta+H starts and stops (`kglobalaccel`). The text is pasted with ydotool instead of typed, since ydotool has no á or ñ on a US layout. Settings are in `/etc/voxtype/config.toml`, which a `~/.config/voxtype/config.toml` replaces. Nothing said leaves the machine.

### Explicit non-goals

These are deliberate choices. Do not add them back without the owner asking:
- **The Docker engine** (`moby-engine`, `docker-ce`): Podman is the engine. `podman-docker` and `docker-compose` only give it Docker's commands.
- **libvirt / virt-manager / GNOME Boxes**: Incus handles VMs. Showing a VM's screen needs a viewer, which the image does not have yet (`docs/vm-viewers.md`).
- **Toolbx / Distrobox**: removed from `kinoite-main` on purpose; Incus handles containers.
- **Package layering on hosts** (`rpm-ostree install`): every change goes through the image.
- **Out-of-tree kernels in `base`.**
- **Compilers in `base`** (`gcc`, `make`, `cmake`): projects that need them run in an Incus container, because the owner wants a minimal base.
- **`mise` in the image:** it is installed per user with `curl https://mise.run | sh`.
- **Kernels, packages or modules from third-party projects** (xps-fedora's `.dellptl`, Omarchy's patches): they are references to audit. What is needed is ported by hand and built here.
- **More secrets software** (KeePassXC, 1Password, aws-vault, gitleaks): the owner wants secrets handled with what the image already ships, KWallet, `secret-tool`, OpenSSH and `ksshaskpass` (2026-11-08). See `docs/secrets-and-devbox.md`.

---

## 2. Repository layout

```
.
├── CLAUDE.md                          this file
├── README.md                          user-facing setup and usage guide
├── mise.toml                          local tasks + tool versions (cosign)
├── cosign.pub                         public signing key (committed, copied into the base image)
├── tests/smoke.sh                     checks a built image from the inside, in CI before publishing
├── tests/check-pins.sh, check-kernel.sh  what pins.yml and kernel-watch.yml run
├── tests/xps16-vrr.sh                 on the XPS: one boot with VRR through an edited EDID (results in docs/status)
├── docs/
│   ├── status/                        what was tested and what was not, one file per subject
│   ├── xps16-plan.md                  the owner's plan for the XPS (not implemented)
│   ├── xps16-checklist.md             checks to run on the XPS
│   ├── vm-viewers.md                  VM viewer research and the KRDC plan
│   └── secrets-and-devbox.md          plan for secrets, AI agents and per-project dev containers (not implemented)
├── devbox/                            drafts for that plan: cloud-init and Incus profile of the dev image
├── .gitignore                         output/, bib/config.toml, cosign.key
├── bib/
│   └── config.example.toml            user for test VMs built with bootc-image-builder
├── .github/
│   ├── keys/ublue-os.pub              Universal Blue's public key, to verify kinoite-main
│   ├── scripts/prune-registry.py      what prune.yml runs: which builds to keep and which to delete
│   ├── scripts/sign-module.py         what module.yml runs next to the module key
│   └── workflows/
│       ├── build.yml                  orchestrator: base → machine images
│       ├── pins.yml                   weekly: an issue when a download pinned in shell.sh has a newer release
│       ├── kernel-watch.yml           weekly: an issue when the kernel or Fedora moves on something the XPS waits for
│       ├── module.yml                 the XPS's hm1092 module: build job without secrets, sign job
│       ├── prune.yml                  weekly: delete builds older than a month from GHCR
│       └── reusable-build.yml         build job: verify FROM → build → test → push to staging; sign job: cosign sign, verify, move tags
└── images/
    ├── base/
    │   ├── Containerfile
    │   ├── build_files/               build-time only, NOT shipped in the image
    │   │   ├── build.sh               entry point: packages, browsers, terminal, Katze theme, services, font cache
    │   │   ├── brave.sh               Brave Origin install + /opt workaround
    │   │   ├── chrome.sh              Google Chrome install + /opt workaround
    │   │   ├── browsers.sh            first-run browser preferences
    │   │   ├── signing.sh             signature policy: our registry only with our signature
    │   │   ├── shell.sh               Starship, Nerd Font (pinned, sha256) and terminal defaults
    │   │   ├── plasma-theme.sh        Katze Dark as the default, Katze Mono icons, fonts
    │   │   ├── tailscale.sh           Tailscale from its official repo
    │   │   └── packages.txt           extra RPMs, one per line
    │   └── system_files/              copied verbatim to / in the image
    │       └── usr/
    │           ├── libexec/katze/ setup.sh, flatpaks.sh, update-*.sh (state, allowed, notify, changes), image-age.sh, desktop-entries.sh, icons.sh, katze-mono.py
    │           ├── lib/systemd/system/ katze-*.service / .timer
    │           ├── lib/systemd/user/  katze-update-notify.*, katze-image-age.*, katze-desktop-entries.service, katze-icons.service
    │           ├── lib/tmpfiles.d/    katze-brave.conf, katze-chrome.conf, katze-flatpak-overrides.conf
    │           ├── lib/environment.d/ 60-katze-docker-host.conf
    │           ├── lib/firewalld/zones/ katze-incus.xml, katze-laptop.xml, katze-tailscale.xml
    │           ├── lib/firewalld/policies/ katze-incus-out.xml, katze-incus-private.xml
    │           ├── share/katze/ flatpaks.list, zshrc, starship.toml, applications/, cosign.pub
    │           ├── share/containers/containers.conf.d/ 60-katze-compose.conf
    │           ├── share/konsole/     katze.profile
    │           ├── share/katze/katze-mono/ aliases.toml, glyphs/, README.md
    │           ├── share/plasma/desktoptheme/ katze
    │           ├── share/plasma/look-and-feel/ katze-dark, katze-light
    │           └── share/color-schemes/ KatzeDark.colors, KatzeLight.colors
    └── xps16-da16260/
        ├── Containerfile
        ├── build_files/
        │   ├── build.sh
        │   ├── dictation.sh               Voxtype and the OpenVINO GenAI SDK (pinned, sha256)
        │   ├── hm1092.sh                  builds the infrared camera's driver, unsigned (module.yml runs it)
        │   ├── ir-camera/                 the infrared camera's reader, in C
        │   ├── face/                      face unlock: katze-face, katze-face-check and the build stage's build.sh
        │   ├── hm1092/                    that driver, its audit and the public half of the module key
        │   └── packages.txt
        └── system_files/usr/
            ├── libexec/katze/  thermald-wait.sh, platform-profile.sh, camera.py, dictation-setup.sh
            ├── lib/systemd/user/  katze-camera.service, katze-dictation.service, katze-ydotoold.service
            ├── lib/modprobe.d/    katze-hm1092.conf
            ├── lib/systemd/system/ katze-ir-camera.socket, katze-ir-camera@.service, katze-face.socket, katze-face@.service
            ├── share/wireplumber/wireplumber.conf.d/ 60-katze-camera.conf
            ├── lib/systemd/system/thermald.service.d/ katze-wait-sensors.conf
            └── lib/tuned/profiles/    katze-xps-powersave, -balanced, -balanced-battery, -performance
```

### Build pattern (every image follows it)

1. A `ctx` stage (`FROM scratch`) holds `build_files/`. It is bind-mounted during the build, so build scripts **never end up in the image**.
2. `system_files/` is copied to `/` in `base` and in `xps16-da16260`. Scripts keep their executable bit from git.
3. `build.sh` runs with `/var/cache` as a cache mount and `/tmp` as tmpfs.
4. `bootc container lint` runs last. **It must pass.** Never remove it.

---

## 3. bootc filesystem rules (critical)

Most bugs in bootc images come from writing to the wrong place. Follow these rules in every change.

| Path | Behavior on update | Rule |
|---|---|---|
| `/usr` | Replaced from the image, read-only at runtime | **Our files go here**: binaries, scripts, units, data |
| `/etc` | 3-way merge: local edits are kept, new image defaults are merged in | Only defaults the user may override locally |
| `/var` | Persistent; **the image only seeds it on the first install** | Never rely on image content in `/var`; create it with `tmpfiles.d` |
| `/opt` | Symlink to `/var/opt` | RPMs that install here need the `brave.sh` pattern |
| `/home` | Symlink to `/var/home` | Never touch it from the image |

Concrete rules:
- **Scripts** go in `/usr/libexec/katze/`. **Units** go in `/usr/lib/systemd/system/` and are enabled in `build.sh`. **Static data** goes in `/usr/share/katze/`.
- **Runtime state** goes in `/var/lib/katze/`, created by the script that uses it or by `tmpfiles.d`.
- **Users and groups:** prefer `sysusers.d`. Groups from packages can live in `/usr/lib/group` (nss-altfiles), and those installed with `dnf5` during our build can land in the image's `/etc/group` instead, which is where `incus-admin` was. `usermod -aG` only works once the group is in `/etc/group` and `/etc/gshadow`. That is why `setup.sh` syncs `incus-admin`. Reuse that pattern for any new group.
- **RPMs that install into `/opt`:** follow `brave.sh`. Create a real `/opt`, install, move the result to `/usr/lib/<vendor>`, restore the `/opt -> var/opt` symlink, and add an `L` line in `tmpfiles.d`.
- **Third-party repos** added at build time must end up **disabled** (`enabled=0`). Updates arrive through the image, never from the host.

---

## 4. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Machine image | `<line><size>-<model>`, lowercase, from the vendor model | `xps16-da16260` |
| Our systemd units | `katze-<purpose>.service/.timer` | `katze-update.timer` |
| Our directories | `katze` namespace under `/usr/libexec`, `/usr/share`, `/var/lib` | `/usr/share/katze/flatpaks.list` |
| tmpfiles.d / sysusers.d | `katze-<purpose>.conf` | `katze-brave.conf` |
| Image tags | `latest`, `<fedora>`, `<fedora>-<YYYYMMDD>` | `45-20261201` |

The project was `bootc-images` until 2026-11-23. Its `bootc-` prefix shared a namespace with upstream bootc units such as `bootc-update-ca-trust.service`, which `katze-` avoids. The repository is `katze-os`; inside the image the name is `katze`. Images keep their names on GHCR, and `ysantalla` only names the GitHub owner and registry.

All code, comments, unit descriptions and docs are in **English**.

---

## 5. Common tasks

All local tasks are defined in `mise.toml`. They need `mise` and rootful `podman` (via `sudo`).

```bash
mise tasks                          # list tasks
mise run build base                 # build an image locally
mise run build xps16-da16260        # builds local base first if missing
mise run vm base                    # qcow2 disk → output/base/qcow2/disk.qcow2
mise run vm-up base                 # boot the test VM, keeping its contents
mise run vm-reset base              # erase the test VM's copy, after asking
mise run vm-incus base              # boot that disk as an Incus VM, on a machine running the image
mise run iso xps16-da16260          # installer ISO
mise run switch-local base          # switch THIS machine to a local build (the name is required)
mise run switch xps16-da16260       # switch THIS machine to the published image, requiring its signature
mise run power --load 60            # THIS machine: profile, RAPL limits, turbostat idle and under load → output/power/
mise run icons:preview              # one picture of the icons in both themes; --set dark.tint=0.3 tries a look
mise run theme:screenshots          # previews of both themes and the README's pictures, from the running test VM
mise run clean                      # remove output/, after asking
```

### Add a package

1. Add one line to `images/<image>/build_files/packages.txt`.
2. Hardware-specific? It goes in the machine image, never in `base`.
3. Run `mise run build <image>` and confirm the build and the lint pass.

### Add a font

RPM fonts need nothing else. A font installed by a script must exist before the `fc-cache -f` in `base`'s `build.sh`, or machines will not see it: `/usr` is read-only and its mtimes are 0, so the stale cache still looks valid. A machine image that installs one by script needs its own `fc-cache -f`. Running as root in a container hides this, so check with `tests/smoke.sh`.

### Add a Flatpak

Add its Flathub ID to `images/base/system_files/usr/share/katze/flatpaks.list`. `katze-flatpaks.service` installs it on the next boot whenever the list's hash changes. It only adds; it never removes.

For custom launch arguments, add a `.desktop` to `usr/share/katze/applications/` with `TryExec=/var/lib/flatpak/exports/bin/<id>` and `X-Katze-Managed=true`. Flatpak's exports come before `/usr/share` in `XDG_DATA_DIRS`, so `katze-desktop-entries.service` copies it to `~/.local/share/applications` at login. Files there without the marker are the user's and are never replaced. Flatpak overrides go in `katze-flatpak-overrides.conf`.

### Add a script or service

1. Script: `system_files/usr/libexec/katze/<name>.sh`, using `#!/usr/bin/env bash` and `set -euo pipefail`. It must be **idempotent** if it runs on boot.
2. Unit: `system_files/usr/lib/systemd/system/katze-<name>.service`.
3. Enable it in that image's `build.sh` (`systemctl enable ...`, or `systemctl --global enable ...` for units in `lib/systemd/user`).
4. Watch for ordering cycles: do not order a normal service `Before=` a socket unit (sockets start before `basic.target`).
5. Do not make a long boot task `Type=oneshot` under `multi-user.target`: the boot would wait for it. `katze-flatpaks.service` uses `Type=exec` for that reason.

### Add a new machine

1. `cp -r images/xps16-da16260 images/<model>` and strip it down to what the new hardware needs.
2. Add a job to `.github/workflows/build.yml` with `needs: base`, mirroring the XPS job.
3. Add a `case` for it in `tests/smoke.sh`: an unknown name fails the build.
4. Update the image table in `README.md` and in this file.

### Bump the Fedora version

`FEDORA_VERSION` appears in **four places**. Change them together, in one commit:
- `images/base/Containerfile`
- `images/xps16-da16260/Containerfile` (and any other machine image)
- `.github/workflows/build.yml` (each job's `fedora_version`)
- `mise.toml` (`[env]`)

---

## 6. CI/CD

- **`build.yml`** runs on push to `main` (excluding `*.md` and `docs/`), on pull requests, daily at 08:30 UTC (after Universal Blue's builds), and on manual dispatch.
- **`base`** is built first. Machine images use `needs: base` and build `FROM` the base that was just pushed.
- **The `FROM` image is verified before each build:** `kinoite-main` against `.github/keys/ublue-os.pub`, and our `base` against `cosign.pub`. It is pulled by digest, and the build steps use `--pull=never`, so the build uses the verified copy. If Universal Blue rotates its key the build fails: replace the key with `/etc/pki/containers/ublue-os.pub` from the new image, after checking it against `cosign.pub` in `ublue-os/main`.
- **`base` is rechunked** after the build (`rechunk: true`), with the image's own rpm-ostree and `--previous-build` pointing at the published tag. It re-adds the labels, since `--rootfs` drops them, and lints the result.
- **`squash: false`** stays on the build steps. `buildah-build` v3 squashes by default, which would make machines download the whole image on every update.
- **One build date per run,** set by the `lint` job, so tags match across images.
- **`main` is protected:** no force-pushes or deletion, and pull requests need `lint` and `base / build` to pass. The owner can still bypass it.
- **`lint`** runs first and blocks publishing: `shellcheck`, TOML, and `cosign.pub` matching the copy in the image.
- **A pull request of documentation only** (`docs/` and the Markdown files at the root) builds no image: `lint` runs, and `base / build` reports as skipped, which satisfies the required check. A `README.md` under `images/` is shipped in the image, so it builds.
- **On pull requests,** nothing is pushed and the `sign` job is skipped, so a change to that job is first exercised on `main`. The `base` job also builds `xps16-da16260` FROM its local base, so machine changes are validated. A new machine image has to replace that name or add its own step.
- **`tests/smoke.sh`** runs inside each built image before it is pushed. Add a check there when you add something that must stay true.
- **`pins.yml`** runs on Mondays: `tests/check-pins.sh` compares the versions pinned in `shell.sh` (Starship, Nerd Fonts) and `dictation.sh` (Voxtype, OpenVINO GenAI) with their latest releases, and the workflow keeps one issue open while any is behind. It changes no file.
- **`kernel-watch.yml`** runs on Mondays: `tests/check-kernel.sh` looks for what the XPS waits on: VRR on its panel (the EDID parser reading DisplayID's Adaptive-Sync block, an EDID quirk for the LG panel, or a second Intel quirk for the DA16260, in Linux master and drm-tip), a `VIDEO_HM1092` driver in master or the media tree's `next`, Linux 7.4 in Fedora 45's updates, and Fedora bug 2563275 (the camera's rotation) leaving `NEW`. It opens one issue per subject the first time, with the steps to follow, never reopens one the owner closed, and changes no file. A new subject is a key in that script.
- **`prune.yml`** runs on Mondays and deletes old builds from GHCR with `.github/scripts/prune-registry.py`: dated tags older than 30 days (the newest seven always stay), untagged manifests, and the signatures of what is gone. `latest`, `staging` and the Fedora tag are never touched, nor anything from the last two days. Started by hand it only lists, unless asked to delete.
- **Actions are pinned by SHA** and Dependabot proposes updates. CI's cosign stays on 2.x (`cosign-release`, independent of the installer action's version), because enforcing machines were tested against its `.sig` format. `mise.toml`'s cosign 3.x is only for local key generation.
- **`reusable-build.yml`** has two jobs. `build` verifies the `FROM` image, builds with buildah and pushes to the `staging` tag on GHCR using `GITHUB_TOKEN` (the owner is lowercased). `sign` signs that digest with cosign and verifies the signature with `cosign.pub`, so a bad key fails the run. Only then does it move `latest`, `<fedora>` and the dated tag to that digest with `skopeo copy --preserve-digests`. Machines never follow `staging`.
- **The signing key is only in the `sign` job.** `SIGNING_SECRET` and `COSIGN_PASSWORD` are secrets of the `signing` environment, which only the `main` branch can use, so a pull request or a manual run on another branch cannot sign, even if it edits the workflow. The `build` job runs code from outside this repo (RPM scriptlets, the image's own rpm-ostree) and never sees the key. Keep both secrets out of the repository-level secrets.
- **`module.yml`** builds the infrared camera's driver for the kernel of the base just published and signs it. The `build` job runs the compiler and has no secrets; the `sign` job has `MODULE_KEY` and `MODULE_KEY_PASSWORD` from the `signing` environment and only runs openssl through `sign-module.py`, whose output is the same as the kernel's `sign-file`. It signs what the build job left, so a compromised build could get a module signed that the owner's machine accepts. The machine image is built without the module when this fails, or when its kernel does not match: the build log has a warning and `tests/smoke.sh` a note. Pull requests only compile it.
- **Only `main` publishes.** A pull request, or a manual run on another branch, builds and tests without pushing.
- **Images are public** on GHCR, so machines pull without credentials.
- **The repo is public,** so GitHub disables the schedule after 60 days without repository activity, and hosts would silently stop getting updates. Re-enable the workflow if GitHub warns about it.

A failed build, test or signature never reaches a machine: `latest` only moves after the signature is verified. A failure while moving the tags can leave them on different digests, all signed.

---

## 7. Validation checklist

Run these before considering a change done. Never claim something was tested if it wasn't.

```bash
# Shell scripts
shellcheck tests/*.sh images/*/build_files/*.sh images/*/system_files/usr/libexec/katze/*.sh

# Workflows and TOML
python3 -c "import yaml,glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"
python3 -c "import tomllib; tomllib.load(open('mise.toml','rb')); tomllib.load(open('bib/config.example.toml','rb'))"

# Units (on a systemd host)
systemd-analyze verify images/base/system_files/usr/lib/systemd/system/katze-*

# Real test: build, then boot it in a VM
mise run build <image>
mise run vm <image>
```

On a machine running the image:

```bash
sudo bootc status                # current image + rollback target
rpm-ostree status                # must show no LayeredPackages
systemctl --failed               # nothing from katze-*
systemctl list-timers katze-update.timer
id -nG                           # does not include incus-admin
vainfo | grep iHD                # xps16-da16260 only
```

---

## 8. Safety rules

- **Never commit `cosign.key`**, `bib/config.toml`, or any credential. Only `cosign.pub` is committed.
- **Never remove `bootc container lint`** from a Containerfile.
- **Never use `:latest` for the upstream base.** Pin `FEDORA_VERSION`.
- **Never add a second updater.** `build.sh` disables `rpm-ostreed-automatic.timer` and `uupd.timer` on purpose. `bootc-fetch-apply-updates.timer` comes disabled upstream and reboots the machine, so keep it that way. The update notification only announces. `flatpak-system-update.timer` from upstream stays, because it only updates Flatpaks.
- **Never run `rpm-ostree install`** (layering) on hosts as a fix. Fix it in the image.
- **Never write into `/var` or `/home` from a Containerfile.**
- **Ask the owner before:**
  - swapping the kernel
  - touching Secure Boot / MOK
  - changing signing policy (`/etc/containers/policy.json`)
  - removing an image
  - force-pushing
  - anything that could stop a machine from booting or updating.
- **Keep changes small and in separate commits.** Image changes are easy to roll back on the host, but CI history is how the owner audits what changed.

---

## 9. Hardware context: `xps16-da16260`

| Component | Detail |
|---|---|
| Model | Dell XPS 16 (2026), DA16260, board 0W09YJ |
| CPU | Intel Core Ultra X9 388H (Panther Lake H), 16 cores |
| GPU | Intel Arc B390 (Xe3), `xe` kernel driver, Mesa |
| Display | 16" tandem OLED, 3200×2000, 20–120 Hz VRR |
| Memory / storage | 64 GB LPDDR5X-9600 (soldered), 1 TB NVMe |
| Reference project | [onuralpszr/xps-fedora](https://github.com/onuralpszr/xps-fedora) (COPR `thunderbirdtr/xps-fedora`, `kernel-*.dellptl`) |

Panther Lake is new hardware. Prefer upstream Fedora kernel and Mesa support, and add workarounds only when something is confirmed broken.

### Kernel options

Reviewed on 2026-11-04, when the image had Fedora's 7.2.15. The owner does not want a kernel swap for now, so do not propose one unprompted. Linux 7.4 was at rc1 and arrives through the daily build once Fedora ships it.

Fedora's kernel moved to 7.3.3-300.fc45 in the `45.20261111` image, through the daily build, with no change here. The other rows were not checked again, so their versions are from 2026-11-04.

| Option | Version seen | Notes |
|---|---|---|
| Fedora `updates` | 7.3.3 (2026-11-11) | Default. No extra work |
| Fedora Koji build | 7.3.1-200.fc45 | Built by Fedora, but pinned by hand and gets no patches until bumped. Now older than the default |
| `@kernel-vanilla/stable` COPR | 7.3.1 | Needs an owner MOK, or Secure Boot off |
| `@kernel-vanilla/mainline` COPR | 7.4 pre-release | Too risky for the main machine |
| `thunderbirdtr/xps-fedora` COPR | 7.2.15 `.dellptl` | Ruled out by the owner on 2026-11-23. Still on 7.2.15 on 2026-11-21. See below |

The research of 2026-11-21 found two upstream commits that name the DA16260 (a Panel Replay quirk, in 7.2 and later, and a fix in 7.4); nothing names the 388H. It also found the 7.4 items below in commits of v7.4-rc3, and Fedora 45 on 7.3.4. Links and the checks that follow from them are in `docs/xps16-checklist.md`. The 7.4 items: IPU7 and IPU7.5 support in the IPU6 driver, Intelligent Bias Control v3 for Xe3, and GPU cold reset recovery.

### `xps-fedora` (`.dellptl`)

The project documents this model on board 0VRKYR with an X7 358H, not the 388H, so confirm its findings on this machine first. It reports, on stock Fedora: VRR not detected, PSR glitches and link errors, RGB camera with raw nodes only, and no IR camera driver. Audio, Wi-Fi, Bluetooth, touchpad and keyboard light work. It is a small project, apparently with one maintainer.

It targets a Fedora install using `dnf`, signing kernels and modules locally with an akmods key, which does not fit a read-only `/usr`. The owner decided against its `.dellptl` kernel on 2026-11-23 (section 10): it is a reference to audit, and anything needed from it is ported by hand and built in this repo. The thermal and power fixes in section 1 came from its `dell-xps-ptl-config`.

---

## 10. Roadmap

Implement these one at a time, each in its own commit, in `xps16-da16260` only:

1. **Verify base** in a VM and on hardware. See `docs/status/`, and `docs/xps16-checklist.md` for the checks to run on the XPS.
   On the XPS, run `mise run power --load 60` on AC first: the profile, RAPL limits and `turbostat` under load decide whether auto-boost is needed at all, since the firmware may already raise the limits in the `performance` profile, or overwrite values written to RAPL.
2. **auto-boost service.** A systemd daemon in `/usr` that raises the sustained RAPL limit, PL1 (`constraint_0_power_limit_uw`), on AC power when CPU load is above 40%, and returns to the stock value plus the `balanced` profile otherwise, polling every 10 s. The owner changed the target from PL2 to PL1 on 2026-11-23: Dell is said to hold about 35 W sustained with bursts near 65 W, so the bursts are already there. Neither figure is measured on this machine, so read the real limits before choosing values: `grep . /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_*_power_limit_uw`. The image has no `powerprofilesctl` (section 1), so the profile changes through tuned. The design is open: `docs/xps16-checklist.md` has the case against a load-polling daemon.
3. **IR face unlock** (in progress: the driver, the reader and `katze-face` are in, nothing of it has run on the machine), on branches `xps-ir-face`, `xps-ir-reader` and `xps-ir-unlock`. The owner decided on 2026-11-23 against the `.dellptl` kernel: the Himax HM1092 sensor's driver is forked into this repo, trimmed, and built in CI against the image's kernel, signed with the owner's MOK in a job of its own (decided on 2026-11-25; done: section 6, `module.yml`). Howdy was the plan; it is not in Fedora and needs dlib built, so the owner chose on 2026-11-25 our own `katze-face` with OpenVINO instead, on the lock screen only. The IPU7 stack may abort s2idle, so suspend is validated first. The IPU7 webcam and Intel ISH have no plan. **Ask before starting:** it touches Secure Boot and MOK.
4. **Secrets and per-project dev containers.** Mostly `base` and per-user setup, not this machine image. Researched on 2026-11-08, nothing implemented: see `docs/secrets-and-devbox.md`, which has the decisions, the test plan for the VM and the XPS, and the repo changes to make afterwards. Tested in a VM on 2026-11-21 (its section 8.1): the keyring, the `devbox` image with rootless `docker compose`, and that the `katze-incus` zone lets instances reach every port on the host, with a tighter zone and policy that fix it.
5. **Rechunk `base`** (in progress). Before it, every build published one new ~675 MB layer for `base` and ~51 MB for the machine, measured on 2026-11-07, plus whatever changed in `kinoite-main`'s own unchunked layer. `reusable-build.yml` now runs `rpm-ostree compose build-chunked-oci` on `base` with `--previous-build`, so unchanged packages keep their layers. Tested locally on 2026-11-07, rootless: 201 layers, and two runs gave the same digest. Brave, Chrome and the initramfs get their own layers; the initramfs shares one with unpackaged files (309 MB compressed), which an `user.component` xattr could split. The first update after the switch downloads the whole image once (about 4.2 GB). Machine images are not rechunked: they add their own layer on top. In a VM on 2026-11-07, `bootc switch` to a rechunked `base` fetched 200 layers (4.3 GB), booted with no new failed units and `incus-admin` in place, and `bootc rollback` returned to the previous image. CI on the PR: 201 layers, lint and `tests/smoke.sh` pass, and the build went from about 6 to 13 minutes. Still to check: the real download between two daily builds.
6. **Audit for bugs and security gaps.** Asked by the owner on 2026-11-24, not started, and its scope is not set yet. An earlier audit was merged as `audit-fixes`.

### Status and plans

- **What was tested and what was not:** `docs/status/`, one file per subject (its `README.md` lists them). Read the subject's file before saying something works, and add to it when something is tested.
- **The owner's plan for the XPS** (first day, encryption, swap, battery, voice dictation): `docs/xps16-plan.md`. Disk unlock and voice dictation are done; the rest is not implemented.
- **Checks to run on the XPS:** `docs/xps16-checklist.md`.
- **VM viewers,** and how to test images on a machine running the image: `docs/vm-viewers.md`.

### Decisions by the owner

**Image tag (2026-11-05):** hosts use `:latest`. A Fedora upgrade still only happens when `FEDORA_VERSION` changes here.

**Incus at boot (2026-11-06):** `incus-startup.service` stays disabled. Instances are started by hand: Incus is meant for running large stacks with resource limits, so they cannot starve video calls, and nothing needs to start at boot.

**Firewall (2026-11-07):** the default zone is `katze-laptop`: DHCPv6, mDNS, KDE Connect, and TCP 7236 and 7250 for GNOME Network Displays, which the owner also uses away from home. Trusted home networks are set to `FedoraWorkstation` by hand. `tailscale0` is in `katze-tailscale`, which accepts everything. Validated with `firewall-offline-cmd --check-config` only: KDE Connect, Network Displays, Tailscale and Incus forwarding under the new default zone are untested. The Network Displays ports come from Miracast, not from its documentation.

**VM viewer (2026-11-06):** KRDC, KDE's own viewer, once it ships with SPICE. The image has no VM viewer until then. See `docs/vm-viewers.md`.

**Secrets and agents (2026-11-08):** no new software for secrets; KWallet stays the Secret Service provider; AI agents run in an Incus container per project, with one Claude Code account each; one minimal `devbox` image for every project. Details in `docs/secrets-and-devbox.md`.

**VRR on the XPS (2026-11-25):** wait for the kernel. The panel can do 20 to 120 Hz, tried for one boot with an edited EDID, but keeping that EDID would mean regenerating the initramfs in the machine image (about 240 MB more in every daily update) for a file that only fits this panel. `kernel-watch.yml` says when a kernel change could fix it. Details in `docs/xps16-checklist.md`, "VRR".

**Pending:**
- Whether the internal camera, through `camera.py`, is good enough for video calls, or a USB webcam is.
- The open questions in `docs/secrets-and-devbox.md`, section 10: password manager, a FIDO2 key, IAM Identity Center, which projects keep their development credentials in Parameter Store, and cloned or mounted code in project containers.

---

## 11. References

- bootc: <https://bootc-dev.github.io/bootc/>
- Fedora bootc docs: <https://docs.fedoraproject.org/en-US/bootc/>
- Universal Blue image template: <https://github.com/ublue-os/image-template>
- bootc-image-builder: <https://github.com/osbuild/bootc-image-builder>
- mise tasks: <https://mise.jdx.dev/tasks/>
- Brave Origin on Linux: <https://brave.com/origin/linux/>
