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
- **Incus:** system containers and KVM virtual machines (`incus launch ... --vm`). The `incus` RPM does not pull in QEMU, so `packages.txt` adds it, and Incus VMs need `qemu-device-display-virtio-vga`. The `katze-incus` firewalld zone only gives instances DHCP and DNS, so they cannot reach the host's other ports, and the `katze-incus-out` policy lets them reach other networks. Tested in a VM on 2026-11-21 with containers only: Incus VMs, IPv6 and the tailnet are untested.
- **Brave Origin:** native RPM (`brave-origin`), the stripped-down Brave without Rewards, Wallet, VPN or AI features.
- **Google Chrome:** native RPM (`google-chrome-stable`), used for video calls. Same `/opt` handling as Brave (`chrome.sh`).
- **Browser defaults** (`browsers.sh`): `initial_preferences` asks for the system title bar and Qt colors on first run, in new profiles only. Both browsers chose Wayland without any flag in a VM (Chrome and Brave on `45.20261106`), so the image sets none.
- **Docker commands:** `podman-docker` makes `docker` run Podman, and `docker compose` runs the real Compose through the per-user `podman.socket`. `DOCKER_HOST` points graphical sessions at that socket (`environment.d`). `60-katze-compose.conf` silences the provider notice.
- **Katze theme:** two global themes, Katze Dark and Katze Light, in `system_files`. Each sets a color scheme (`KatzeDark`, `KatzeLight`), the `katze` Plasma style, a Katze Mono icon theme and a desktop layout: one panel, 56 px thick, with the virtual desktop switcher next to the tray and tray icons that scale with the panel. `plasma-theme.sh` also gives a new user two virtual desktops, one above the other, since Plasma hides the switcher with only one. `plasma-theme.sh` makes Katze Dark the default for new users and removes Fedora's global themes (their package stays, since `plasma-workspace` requires it), so only Breeze's and Katze's are offered. The Dark Mode switch in the panel, and switching at night, go between the two (`DefaultDarkLookAndFeel`, `DefaultLightLookAndFeel`). The layout only reaches a new user, or someone who applies the theme with its desktop layout. Applying a global theme clears a custom accent color.
- **`katze` Plasma style:** Breeze with the owner's taskbar indicators, moved here from `ysantalla/plasma-tips` (it was `breeze-custom`). It has no `colors` file on purpose: with one, the panel and the launcher keep those colors whatever the scheme and accent are.
- **Katze Mono icons:** `katze-mono.py` draws one icon per application, a thin line glyph on a rounded shape, painted by the color scheme and the accent. `plasma-theme.sh` runs it at build time for the image's applications and for every alias, which covers Flatpaks that are not installed yet, into `/usr/share/icons/katze-mono` and `katze-mono-light`. `katze-icons.service` runs it at login for the user's own applications, into the same themes in the home directory. Choices are in `usr/share/katze/katze-mono/aliases.toml`, and its `README.md` has the design rules and what was learned about Plasma: tray names, shortened names, colors. A panel that is already running keeps the icons it has drawn until `plasma-plasmashell.service` restarts. The owner's Tela icon theme is not included.
- **Interface fonts:** Inter 11 in `/etc/xdg/kdeglobals`, with no sub-pixel text in KDE or fontconfig, since OLED panels often lack RGB stripes (`plasma-theme.sh`). Noto stays the system sans-serif.
- **Okular:** native RPM.
- **Haruna:** native RPM. It plays through `mpv-libs` and the full ffmpeg, both from negativo17 via `kinoite-main`. `yt-dlp` comes as a weak dependency.
- **Office fonts:** Carlito and Caladea, with the same metrics as Calibri and Cambria. Liberation already covers Arial, Times New Roman and Courier New. Microsoft's fonts stay out because this image is public; Fedora's `mscore-fonts` is an unrelated MuseScore package.
- **Terminal:** zsh with autosuggestions and syntax highlighting, Starship with a Powerlevel10k-style factory prompt, MesloLGS Nerd Font, Konsole and Yakuake defaults (`shell.sh`), and `fastfetch` for a system summary. Personal settings go in `~/.zshrc`, and `~/.config/starship.toml` replaces the factory prompt. Its icons are Private Use characters that editors and copying can lose, so check them after editing (`grep -c $'\ue0b0'`).
- **Tailscale:** private network between the owner's devices (`tailscale.sh`). Login is done once on each machine with `sudo tailscale up`.
- **Firewall:** the default zone `katze-laptop` only lets in DHCPv6, mDNS, KDE Connect and GNOME Network Displays. Trusted networks go to `FedoraWorkstation` by hand, and the tailnet is accepted.
- **System Flatpaks** from a declarative list (Zed, Slack, ONLYOFFICE, GNOME Network Displays).
- **Flatpak launchers:** Slack and ONLYOFFICE get the owner's launch arguments through `katze-desktop-entries.service` and Flatpak overrides through `katze-flatpak-overrides.conf`.
- **Zed window borders:** `ZED_WINDOW_DECORATIONS=server` in `katze-flatpak-overrides.conf` makes KWin draw them. Zed keeps its own bar below, and the variable overrides Zed's `window_decorations` setting. Seen working with that setting on the owner's machine, not yet through the override.
- **First-boot and every-boot setup:** the `incus-admin` group and subuid/subgid ranges.
- **Our own update timer** (wall-clock, every 6 h, `Persistent=true`, skipped on battery and metered connections), which replaces any upstream updater, plus a desktop notification when an update is ready. It only announces: it never reboots by itself. A daily user timer warns if the running image is over 14 days old.
- **Signature policy:** `signing.sh` adds our registry and key to `policy.json`. Machines only enforce it after `bootc switch --enforce-container-sigpolicy`. Until then, the daily user timer also warns that updates from our registry are not checked for a signature (`image-signature.sh`).

**`xps16-da16260` adds:** `libva-intel-media-driver` and `libva-utils` for hardware video decode (H.264, HEVC, VP9, AV1) on the Arc B390, which `kinoite-main` also ships today and stay listed so this machine keeps them, plus `powertop`, `lm_sensors`, `igt-gpu-tools` and `kernel-tools` (`turbostat`) to measure battery, temperature, GPU use and package power on this hardware. Its `build.sh` also adds Intel video flags to the browser launchers, and makes the screen dim and turn off early for the OLED panel: off after 3 minutes on AC and 2 on battery, as PowerDevil defaults in `/etc/xdg/powerdevilrc` that a user can change.

It also carries two fixes adapted from `onuralpszr/xps-fedora` (commit `98e8400`), which reports both problems on an X7 358H. Neither is confirmed on this machine yet:
- **thermald:** a drop-in runs `thermald-wait.sh`, which waits up to 30 s for RAPL, coretemp and the `TCPU` zone, because thermald otherwise gives up on Panther Lake until the next boot.
- **Power profiles:** four `katze-xps-*` tuned profiles call `platform-profile.sh`, which sets Dell's thermal mode (`dell-pc`) and Intel's SoC power slider separately, since the legacy `platform_profile` only offers what both share. `build.sh` points `/etc/tuned/ppd.conf` at them and turns off `sysfs_acpi_monitor`. The image has `tuned-ppd`, not power-profiles-daemon, so there is no `powerprofilesctl`.

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
├── docs/
│   ├── status.md                      what was tested and what was not, by date
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
│   └── workflows/
│       ├── build.yml                  orchestrator: base → machine images
│       └── reusable-build.yml         build job: verify FROM → build → test → push to staging; sign job: cosign sign, verify, move tags
└── images/
    ├── base/
    │   ├── Containerfile
    │   ├── build_files/               build-time only, NOT shipped in the image
    │   │   ├── build.sh               entry point: packages, browsers, terminal, Katze theme, services, font cache
    │   │   ├── brave.sh               Brave Origin install + /opt workaround
    │   │   ├── chrome.sh              Google Chrome install + /opt workaround
    │   │   ├── browsers.sh            first-run browser preferences
    │   │   ├── signing.sh             signature policy for machines that opt in
    │   │   ├── shell.sh               Starship, Nerd Font (pinned, sha256) and terminal defaults
    │   │   ├── plasma-theme.sh        Katze Dark as the default, Katze Mono icons, fonts
    │   │   ├── tailscale.sh           Tailscale from its official repo
    │   │   └── packages.txt           extra RPMs, one per line
    │   └── system_files/              copied verbatim to / in the image
    │       └── usr/
    │           ├── libexec/katze/ setup.sh, flatpaks.sh, update-*.sh, image-age.sh, image-signature.sh, desktop-entries.sh, icons.sh, katze-mono.py
    │           ├── lib/systemd/system/ katze-*.service / .timer
    │           ├── lib/systemd/user/  katze-update-notify.*, katze-image-age.*, katze-desktop-entries.service, katze-icons.service
    │           ├── lib/tmpfiles.d/    katze-brave.conf, katze-chrome.conf, katze-flatpak-overrides.conf
    │           ├── lib/environment.d/ 60-katze-docker-host.conf
    │           ├── lib/firewalld/zones/ katze-incus.xml, katze-laptop.xml, katze-tailscale.xml
    │           ├── lib/firewalld/policies/ katze-incus-out.xml
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
        │   └── packages.txt
        └── system_files/usr/
            ├── libexec/katze/  thermald-wait.sh, platform-profile.sh
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

- **`build.yml`** runs on push to `main` (excluding `*.md`), on pull requests, daily at 08:30 UTC (after Universal Blue's builds), and on manual dispatch.
- **`base`** is built first. Machine images use `needs: base` and build `FROM` the base that was just pushed.
- **The `FROM` image is verified before each build:** `kinoite-main` against `.github/keys/ublue-os.pub`, and our `base` against `cosign.pub`. It is pulled by digest, and the build steps use `--pull=never`, so the build uses the verified copy. If Universal Blue rotates its key the build fails: replace the key with `/etc/pki/containers/ublue-os.pub` from the new image, after checking it against `cosign.pub` in `ublue-os/main`.
- **`base` is rechunked** after the build (`rechunk: true`), with the image's own rpm-ostree and `--previous-build` pointing at the published tag. It re-adds the labels, since `--rootfs` drops them, and lints the result.
- **`squash: false`** stays on the build steps. `buildah-build` v3 squashes by default, which would make machines download the whole image on every update.
- **One build date per run,** set by the `lint` job, so tags match across images.
- **`main` is protected:** no force-pushes or deletion, and pull requests need `lint` and `base / build` to pass. The owner can still bypass it.
- **`lint`** runs first and blocks publishing: `shellcheck`, TOML, and `cosign.pub` matching the copy in the image.
- **On pull requests,** nothing is pushed and the `sign` job is skipped, so a change to that job is first exercised on `main`. The `base` job also builds `xps16-da16260` FROM its local base, so machine changes are validated. A new machine image has to replace that name or add its own step.
- **`tests/smoke.sh`** runs inside each built image before it is pushed. Add a check there when you add something that must stay true.
- **Actions are pinned by SHA** and Dependabot proposes updates. CI's cosign stays on 2.x (`cosign-release`, independent of the installer action's version), because enforcing machines were tested against its `.sig` format. `mise.toml`'s cosign 3.x is only for local key generation.
- **`reusable-build.yml`** has two jobs. `build` verifies the `FROM` image, builds with buildah and pushes to the `staging` tag on GHCR using `GITHUB_TOKEN` (the owner is lowercased). `sign` signs that digest with cosign and verifies the signature with `cosign.pub`, so a bad key fails the run. Only then does it move `latest`, `<fedora>` and the dated tag to that digest with `skopeo copy --preserve-digests`. Machines never follow `staging`.
- **The signing key is only in the `sign` job.** `SIGNING_SECRET` and `COSIGN_PASSWORD` are secrets of the `signing` environment, which only the `main` branch can use, so a pull request or a manual run on another branch cannot sign, even if it edits the workflow. The `build` job runs code from outside this repo (RPM scriptlets, the image's own rpm-ostree) and never sees the key. Keep both secrets out of the repository-level secrets.
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
id -nG                           # includes incus-admin
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
| Model | Dell XPS 16 (2026), DA16260, board 0VRKYR |
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

The project documents this model and board with an X7 358H, not the 388H, so confirm its findings on this machine first. It reports, on stock Fedora: VRR not detected, PSR glitches and link errors, RGB camera with raw nodes only, and no IR camera driver. Audio, Wi-Fi, Bluetooth, touchpad and keyboard light work. It is a small project, apparently with one maintainer.

It targets a Fedora install using `dnf`, signing kernels and modules locally with an akmods key, which does not fit a read-only `/usr`. The owner decided against its `.dellptl` kernel on 2026-11-23 (section 10): it is a reference to audit, and anything needed from it is ported by hand and built in this repo. The thermal and power fixes in section 1 came from its `dell-xps-ptl-config`.

---

## 10. Roadmap

Implement these one at a time, each in its own commit, in `xps16-da16260` only:

1. **Verify base** in a VM and on hardware. See `docs/status.md`, and `docs/xps16-checklist.md` for the checks to run on the XPS.
   On the XPS, run `mise run power --load 60` on AC first: the profile, RAPL limits and `turbostat` under load decide whether auto-boost is needed at all, since the firmware may already raise the limits in the `performance` profile, or overwrite values written to RAPL.
2. **auto-boost service.** A systemd daemon in `/usr` that raises the sustained RAPL limit, PL1 (`constraint_0_power_limit_uw`), on AC power when CPU load is above 40%, and returns to the stock value plus the `balanced` profile otherwise, polling every 10 s. The owner changed the target from PL2 to PL1 on 2026-11-23: Dell is said to hold about 35 W sustained with bursts near 65 W, so the bursts are already there. Neither figure is measured on this machine, so read the real limits before choosing values: `grep . /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_*_power_limit_uw`. The image has no `powerprofilesctl` (section 1), so the profile changes through tuned. The design is open: `docs/xps16-checklist.md` has the case against a load-polling daemon.
3. **IR face unlock,** on a branch named `xps-ir-face`. The owner decided on 2026-11-23 against the `.dellptl` kernel: the Himax HM1092 sensor's driver is forked into this repo, trimmed, and built in the Containerfile against the image's kernel, signed with the owner's MOK during the build. Howdy uses it on the lock screen only, forced to the IR node. The IPU7 stack may abort s2idle, so suspend is validated first. The IPU7 webcam and Intel ISH have no plan. **Ask before starting:** it touches Secure Boot and MOK.
4. **Secrets and per-project dev containers.** Mostly `base` and per-user setup, not this machine image. Researched on 2026-11-08, nothing implemented: see `docs/secrets-and-devbox.md`, which has the decisions, the test plan for the VM and the XPS, and the repo changes to make afterwards. Tested in a VM on 2026-11-21 (its section 8.1): the keyring, the `devbox` image with rootless `docker compose`, and that the `katze-incus` zone lets instances reach every port on the host, with a tighter zone and policy that fix it.
5. **Rechunk `base`** (in progress). Before it, every build published one new ~675 MB layer for `base` and ~51 MB for the machine, measured on 2026-11-07, plus whatever changed in `kinoite-main`'s own unchunked layer. `reusable-build.yml` now runs `rpm-ostree compose build-chunked-oci` on `base` with `--previous-build`, so unchanged packages keep their layers. Tested locally on 2026-11-07, rootless: 201 layers, and two runs gave the same digest. Brave, Chrome and the initramfs get their own layers; the initramfs shares one with unpackaged files (309 MB compressed), which an `user.component` xattr could split. The first update after the switch downloads the whole image once (about 4.2 GB). Machine images are not rechunked: they add their own layer on top. In a VM on 2026-11-07, `bootc switch` to a rechunked `base` fetched 200 layers (4.3 GB), booted with no new failed units and `incus-admin` in place, and `bootc rollback` returned to the previous image. CI on the PR: 201 layers, lint and `tests/smoke.sh` pass, and the build went from about 6 to 13 minutes. Still to check: the real download between two daily builds.
6. **Audit for bugs and security gaps.** Asked by the owner on 2026-11-24, not started, and its scope is not set yet. An earlier audit was merged as `audit-fixes`.

### Status and plans

- **What was tested and what was not:** `docs/status.md`. Read it before saying something works, and add to it when something is tested.
- **The owner's plan for the XPS** (first day, encryption, swap, battery, voice dictation): `docs/xps16-plan.md`. None of it is implemented.
- **Checks to run on the XPS:** `docs/xps16-checklist.md`.
- **VM viewers,** and how to test images on a machine running the image: `docs/vm-viewers.md`.

### Decisions by the owner

**Image tag (2026-11-05):** hosts use `:latest`. A Fedora upgrade still only happens when `FEDORA_VERSION` changes here.

**Incus at boot (2026-11-06):** `incus-startup.service` stays disabled. Instances are started by hand: Incus is meant for running large stacks with resource limits, so they cannot starve video calls, and nothing needs to start at boot.

**Firewall (2026-11-07):** the default zone is `katze-laptop`: DHCPv6, mDNS, KDE Connect, and TCP 7236 and 7250 for GNOME Network Displays, which the owner also uses away from home. Trusted home networks are set to `FedoraWorkstation` by hand. `tailscale0` is in `katze-tailscale`, which accepts everything. Validated with `firewall-offline-cmd --check-config` only: KDE Connect, Network Displays, Tailscale and Incus forwarding under the new default zone are untested. The Network Displays ports come from Miracast, not from its documentation.

**VM viewer (2026-11-06):** KRDC, KDE's own viewer, once it ships with SPICE. The image has no VM viewer until then. See `docs/vm-viewers.md`.

**Secrets and agents (2026-11-08):** no new software for secrets; KWallet stays the Secret Service provider; AI agents run in an Incus container per project, with one Claude Code account each; one minimal `devbox` image for every project. Details in `docs/secrets-and-devbox.md`.

**Pending:**
- Whether to use the internal camera or a USB webcam for video calls.
- The open questions in `docs/secrets-and-devbox.md`, section 10: password manager, a FIDO2 key, IAM Identity Center, which projects keep their development credentials in Parameter Store, and cloned or mounted code in project containers.

---

## 11. References

- bootc: <https://bootc-dev.github.io/bootc/>
- Fedora bootc docs: <https://docs.fedoraproject.org/en-US/bootc/>
- Universal Blue image template: <https://github.com/ublue-os/image-template>
- bootc-image-builder: <https://github.com/osbuild/bootc-image-builder>
- mise tasks: <https://mise.jdx.dev/tasks/>
- Brave Origin on Linux: <https://brave.com/origin/linux/>
