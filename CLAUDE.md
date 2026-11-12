# CLAUDE.md

Guidance for Claude Code (and any other contributor) working in this repository.
Read it fully before changing anything. `README.md` is the user-facing guide; this file explains how the project is built, the rules it follows, and how to make changes safely.

---

## 1. Project overview

`bootc-images` produces personal, immutable operating system images for the owner's machines. Each image is an OCI container image that [bootc](https://bootc-dev.github.io/bootc/) deploys as a full OS: atomic updates, a read-only `/usr`, and one-command rollback.

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
- **Incus:** system containers and KVM virtual machines (`incus launch ... --vm`). The `incus` RPM does not pull in QEMU, so `packages.txt` adds it, and Incus VMs need `qemu-device-display-virtio-vga`. The `bootc-incus` firewalld zone lets instances get IPv4 and DNS.
- **Brave Origin:** native RPM (`brave-origin`), the stripped-down Brave without Rewards, Wallet, VPN or AI features.
- **Google Chrome:** native RPM (`google-chrome-stable`), used for video calls. Same `/opt` handling as Brave (`chrome.sh`).
- **Browser defaults** (`browsers.sh`): `initial_preferences` asks for the system title bar and Qt colors on first run, in new profiles only. Both browsers chose Wayland without any flag in a VM (Chrome and Brave on `45.20261106`), so the image sets none.
- **Docker commands:** `podman-docker` makes `docker` run Podman, and `docker compose` runs the real Compose through the per-user `podman.socket`. `DOCKER_HOST` points graphical sessions at that socket (`environment.d`). `60-bootc-compose.conf` silences the provider notice.
- **Plasma style:** `breeze-custom` and the `BreezeDarkCustom` color scheme in `system_files`, moved here from `ysantalla/plasma-tips`, with Breeze's dark icons. `plasma-theme.sh` makes them the default for new users. The owner's Tela icon theme is not included.
- **Interface fonts:** Inter 11 in `/etc/xdg/kdeglobals`, with no sub-pixel text in KDE or fontconfig, since OLED panels often lack RGB stripes (`plasma-theme.sh`). Noto stays the system sans-serif.
- **Okular:** native RPM.
- **Haruna:** native RPM. It plays through `mpv-libs` and the full ffmpeg, both from negativo17 via `kinoite-main`. `yt-dlp` comes as a weak dependency.
- **Office fonts:** Carlito and Caladea, with the same metrics as Calibri and Cambria. Liberation already covers Arial, Times New Roman and Courier New. Microsoft's fonts stay out because this image is public; Fedora's `mscore-fonts` is an unrelated MuseScore package.
- **Terminal:** zsh with autosuggestions and syntax highlighting, Starship with a Powerlevel10k-style factory prompt, MesloLGS Nerd Font, Konsole and Yakuake defaults (`shell.sh`), and `fastfetch` for a system summary. Personal settings go in `~/.zshrc`, and `~/.config/starship.toml` replaces the factory prompt. Its icons are Private Use characters that editors and copying can lose, so check them after editing (`grep -c $'\ue0b0'`).
- **Tailscale:** private network between the owner's devices (`tailscale.sh`). Login is done once on each machine with `sudo tailscale up`.
- **Firewall:** the default zone `bootc-laptop` only lets in DHCPv6, mDNS, KDE Connect and GNOME Network Displays. Trusted networks go to `FedoraWorkstation` by hand, and the tailnet is accepted.
- **System Flatpaks** from a declarative list (Zed, Slack, ONLYOFFICE, GNOME Network Displays).
- **Flatpak launchers:** Slack and ONLYOFFICE get the owner's launch arguments through `bootc-desktop-entries.service` and Flatpak overrides through `bootc-flatpak-overrides.conf`.
- **Zed window borders:** `ZED_WINDOW_DECORATIONS=server` in `bootc-flatpak-overrides.conf` makes KWin draw them. Zed keeps its own bar below, and the variable overrides Zed's `window_decorations` setting. Seen working with that setting on the owner's machine, not yet through the override.
- **First-boot and every-boot setup:** the `incus-admin` group and subuid/subgid ranges.
- **Our own update timer** (wall-clock, every 6 h, `Persistent=true`, skipped on battery and metered connections), which replaces any upstream updater, plus a desktop notification when an update is ready. It only announces: it never reboots by itself. A daily user timer warns if the running image is over 14 days old.
- **Signature policy:** `signing.sh` adds our registry and key to `policy.json`. Machines only enforce it after `bootc switch --enforce-container-sigpolicy`.

**`xps16-da16260` adds:** `libva-intel-media-driver` and `libva-utils` for hardware video decode (H.264, HEVC, VP9, AV1) on the Arc B390, which `kinoite-main` also ships today and stay listed so this machine keeps them, plus `powertop`, `lm_sensors`, `igt-gpu-tools` and `kernel-tools` (`turbostat`) to measure battery, temperature, GPU use and package power on this hardware. Its `build.sh` also adds Intel video flags to the browser launchers.

### Explicit non-goals

These are deliberate choices. Do not add them back without the owner asking:
- **The Docker engine** (`moby-engine`, `docker-ce`): Podman is the engine. `podman-docker` and `docker-compose` only give it Docker's commands.
- **libvirt / virt-manager / GNOME Boxes**: Incus handles VMs. Showing a VM's screen needs a viewer, which the image does not have yet (section 11).
- **Toolbx / Distrobox**: removed from `kinoite-main` on purpose; Incus handles containers.
- **Package layering on hosts** (`rpm-ostree install`): every change goes through the image.
- **Out-of-tree kernels in `base`.**
- **Compilers in `base`** (`gcc`, `make`, `cmake`): projects that need them run in an Incus container, because the owner wants a minimal base.
- **`mise` in the image:** it is installed per user with `curl https://mise.run | sh`.

---

## 2. Repository layout

```
.
├── CLAUDE.md                          this file
├── README.md                          user-facing setup and usage guide
├── mise.toml                          local tasks + tool versions (cosign)
├── cosign.pub                         public signing key (committed, copied into the base image)
├── tests/smoke.sh                     checks a built image from the inside, in CI before publishing
├── .gitignore                         output/, bib/config.toml, cosign.key
├── bib/
│   └── config.example.toml            user for test VMs built with bootc-image-builder
├── .github/
│   ├── keys/ublue-os.pub              Universal Blue's public key, to verify kinoite-main
│   └── workflows/
│       ├── build.yml                  orchestrator: base → machine images
│       └── reusable-build.yml         verify FROM → build → test → push to GHCR → cosign sign and verify
└── images/
    ├── base/
    │   ├── Containerfile
    │   ├── build_files/               build-time only, NOT shipped in the image
    │   │   ├── build.sh               entry point: packages, browsers, terminal, Plasma style, services, font cache
    │   │   ├── brave.sh               Brave Origin install + /opt workaround
    │   │   ├── chrome.sh              Google Chrome install + /opt workaround
    │   │   ├── browsers.sh            first-run browser preferences
    │   │   ├── signing.sh             signature policy for machines that opt in
    │   │   ├── shell.sh               Starship, Nerd Font (pinned, sha256) and terminal defaults
    │   │   ├── plasma-theme.sh        makes the Plasma style, colors and fonts the default
    │   │   ├── tailscale.sh           Tailscale from its official repo
    │   │   └── packages.txt           extra RPMs, one per line
    │   └── system_files/              copied verbatim to / in the image
    │       └── usr/
    │           ├── libexec/bootc-images/ setup.sh, flatpaks.sh, update-*.sh, image-age.sh, desktop-entries.sh
    │           ├── lib/systemd/system/ bootc-*.service / .timer
    │           ├── lib/systemd/user/  bootc-update-notify.*, bootc-image-age.*, bootc-desktop-entries.service
    │           ├── lib/tmpfiles.d/    bootc-brave.conf, bootc-chrome.conf, bootc-flatpak-overrides.conf
    │           ├── lib/environment.d/ 60-bootc-docker-host.conf
    │           ├── lib/firewalld/zones/ bootc-incus.xml, bootc-laptop.xml, bootc-tailscale.xml
    │           ├── share/bootc-images/ flatpaks.list, zshrc, starship.toml, applications/, cosign.pub
    │           ├── share/containers/containers.conf.d/ 60-bootc-compose.conf
    │           ├── share/konsole/     bootc-images.profile
    │           ├── share/plasma/desktoptheme/ breeze-custom
    │           └── share/color-schemes/ BreezeDarkCustom.colors
    └── xps16-da16260/
        ├── Containerfile
        └── build_files/
            ├── build.sh
            └── packages.txt
```

### Build pattern (every image follows it)

1. A `ctx` stage (`FROM scratch`) holds `build_files/`. It is bind-mounted during the build, so build scripts **never end up in the image**.
2. `system_files/` is copied to `/` in `base`. `xps16-da16260` has no `COPY` line or `chmod` yet, so the first machine script or unit (auto-boost) must add both.
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
- **Scripts** go in `/usr/libexec/bootc-images/`. **Units** go in `/usr/lib/systemd/system/` and are enabled in `build.sh`. **Static data** goes in `/usr/share/bootc-images/`.
- **Runtime state** goes in `/var/lib/bootc-images/`, created by the script that uses it or by `tmpfiles.d`.
- **Users and groups:** prefer `sysusers.d`. Groups from packages can live in `/usr/lib/group` (nss-altfiles), and those installed with `dnf5` during our build can land in the image's `/etc/group` instead, which is where `incus-admin` was. `usermod -aG` only works once the group is in `/etc/group` and `/etc/gshadow`. That is why `setup.sh` syncs `incus-admin`. Reuse that pattern for any new group.
- **RPMs that install into `/opt`:** follow `brave.sh`. Create a real `/opt`, install, move the result to `/usr/lib/<vendor>`, restore the `/opt -> var/opt` symlink, and add an `L` line in `tmpfiles.d`.
- **Third-party repos** added at build time must end up **disabled** (`enabled=0`). Updates arrive through the image, never from the host.

---

## 4. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Machine image | `<line><size>-<model>`, lowercase, from the vendor model | `xps16-da16260` |
| Our systemd units | `bootc-<purpose>.service/.timer` | `bootc-update.timer` |
| Our directories | `bootc-images` namespace under `/usr/libexec`, `/usr/share`, `/var/lib` | `/usr/share/bootc-images/flatpaks.list` |
| tmpfiles.d / sysusers.d | `bootc-<purpose>.conf` | `bootc-brave.conf` |
| Image tags | `latest`, `<fedora>`, `<fedora>-<YYYYMMDD>` | `45-20261201` |

The `bootc-` prefix shares a namespace with upstream bootc units such as `bootc-update-ca-trust.service`, so check a new name does not collide. `ysantalla` only names the GitHub owner and registry.

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

Add its Flathub ID to `images/base/system_files/usr/share/bootc-images/flatpaks.list`. `bootc-flatpaks.service` installs it on the next boot whenever the list's hash changes. It only adds; it never removes.

For custom launch arguments, add a `.desktop` to `usr/share/bootc-images/applications/` with `TryExec=/var/lib/flatpak/exports/bin/<id>` and `X-Bootc-Images-Managed=true`. Flatpak's exports come before `/usr/share` in `XDG_DATA_DIRS`, so `bootc-desktop-entries.service` copies it to `~/.local/share/applications` at login. Files there without the marker are the user's and are never replaced. Flatpak overrides go in `bootc-flatpak-overrides.conf`.

### Add a script or service

1. Script: `system_files/usr/libexec/bootc-images/<name>.sh`, using `#!/usr/bin/env bash` and `set -euo pipefail`. It must be **idempotent** if it runs on boot.
2. Unit: `system_files/usr/lib/systemd/system/bootc-<name>.service`.
3. Enable it in that image's `build.sh` (`systemctl enable ...`, or `systemctl --global enable ...` for units in `lib/systemd/user`).
4. Watch for ordering cycles: do not order a normal service `Before=` a socket unit (sockets start before `basic.target`).
5. Do not make a long boot task `Type=oneshot` under `multi-user.target`: the boot would wait for it. `bootc-flatpaks.service` uses `Type=exec` for that reason.

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
- **On pull requests,** nothing is pushed. The `base` job also builds `xps16-da16260` FROM its local base, so machine changes are validated. A new machine image has to replace that name or add its own step.
- **`tests/smoke.sh`** runs inside each built image before it is pushed. Add a check there when you add something that must stay true.
- **Actions are pinned by SHA** and Dependabot proposes updates. CI's cosign stays on 2.x (`cosign-release`, independent of the installer action's version), because enforcing machines were tested against its `.sig` format. `mise.toml`'s cosign 3.x is only for local key generation.
- **`reusable-build.yml`** verifies the `FROM` image, builds with buildah, pushes to the `staging` tag on GHCR using `GITHUB_TOKEN` (the owner is lowercased), signs the digest with cosign using the `SIGNING_SECRET` and `COSIGN_PASSWORD` secrets, and verifies the signature with `cosign.pub`, so a bad key fails the build. Only then does it move `latest`, `<fedora>` and the dated tag to that digest with `skopeo copy --preserve-digests`. Machines never follow `staging`.
- **Images are public** on GHCR, so machines pull without credentials.
- **The repo is public,** so GitHub disables the schedule after 60 days without repository activity, and hosts would silently stop getting updates. Re-enable the workflow if GitHub warns about it.

A failed build, test or signature never reaches a machine: `latest` only moves after the signature is verified. A failure while moving the tags can leave them on different digests, all signed.

---

## 7. Validation checklist

Run these before considering a change done. Never claim something was tested if it wasn't.

```bash
# Shell scripts
shellcheck tests/*.sh images/*/build_files/*.sh images/*/system_files/usr/libexec/bootc-images/*.sh

# Workflows and TOML
python3 -c "import yaml,glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"
python3 -c "import tomllib; tomllib.load(open('mise.toml','rb')); tomllib.load(open('bib/config.example.toml','rb'))"

# Units (on a systemd host)
systemd-analyze verify images/base/system_files/usr/lib/systemd/system/bootc-*

# Real test: build, then boot it in a VM
mise run build <image>
mise run vm <image>
```

On a machine running the image:

```bash
sudo bootc status                # current image + rollback target
rpm-ostree status                # must show no LayeredPackages
systemctl --failed               # nothing from bootc-*
systemctl list-timers bootc-update.timer
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
| `thunderbirdtr/xps-fedora` COPR | 7.2.15 `.dellptl` | Fedora's version on 2026-11-04, with hardware patches. See below |

No readable source named a 7.3 or 7.4 change for this model with the 388H. Phoronix pages could not be read directly, so the 7.4 items come from search summaries: IPU7 and IPU7.5 support in the IPU6 driver, Intelligent Bias Control v3 for Xe3, and GPU cold reset recovery.

### `xps-fedora` (`.dellptl`)

The project documents this model and board with an X7 358H, not the 388H, so confirm its findings on this machine first. It reports, on stock Fedora: VRR not detected, PSR glitches and link errors, RGB camera with raw nodes only, and no IR camera driver. Audio, Wi-Fi, Bluetooth, touchpad and keyboard light work. It is a small project, apparently with one maintainer.

It targets a Fedora install using `dnf`, signing kernels and modules locally with an akmods key, which does not fit a read-only `/usr`. If it is needed, reuse it in stages, in this image only: the kernel first (VRR, PSR, IR sensor), then the thermal fix from `dell-xps-ptl-config`, and the camera last, since that needs an IPU7 module built in the image and closed Intel libraries. The build must fail if no `.dellptl` kernel matches the expected version. Review `dell-xps-ptl-config` before starting auto-boost, since it also ships power profiles.

---

## 10. Roadmap

Implement these one at a time, each in its own commit, in `xps16-da16260` only:

1. **Verify base** in a VM and on hardware. See the status below.
   On the XPS, run `mise run power --load 60` on AC first: the profile, RAPL limits and `turbostat` under load decide whether auto-boost is needed at all, since the firmware may already raise the limits in the `performance` profile, or overwrite values written to RAPL.
2. **auto-boost service.** A systemd daemon in `/usr` that sets RAPL PL2 to 60 W on AC power when CPU load is above 40%, and returns to 34 W plus the `balanced` profile otherwise. It polls every 10 s, through `/sys/class/powercap/intel-rapl/intel-rapl:0/constraint_1_power_limit_uw` and `powerprofilesctl`.
3. **`.dellptl` kernel** for the IPU7 webcam, IR face unlock and Intel ISH. This requires regenerating the initramfs (`dracut`) and signing for Secure Boot with an owner-enrolled MOK in CI. **Ask before starting.**
4. **Rechunk `base`** (in progress). Before it, every build published one new ~675 MB layer for `base` and ~51 MB for the machine, measured on 2026-11-07, plus whatever changed in `kinoite-main`'s own unchunked layer. `reusable-build.yml` now runs `rpm-ostree compose build-chunked-oci` on `base` with `--previous-build`, so unchanged packages keep their layers. Tested locally on 2026-11-07, rootless: 201 layers, and two runs gave the same digest. Brave, Chrome and the initramfs get their own layers; the initramfs shares one with unpackaged files (309 MB compressed), which an `user.component` xattr could split. The first update after the switch downloads the whole image once (about 4.2 GB). Machine images are not rechunked: they add their own layer on top. In a VM on 2026-11-07, `bootc switch` to a rechunked `base` fetched 200 layers (4.3 GB), booted with no new failed units and `incus-admin` in place, and `bootc rollback` returned to the previous image. CI on the PR: 201 layers, lint and `tests/smoke.sh` pass, and the build went from about 6 to 13 minutes. Still to check: the real download between two daily builds.

### Status (2026-11-05)

Images build, publish and verify with `cosign.pub`, and pull without credentials.

**Verified in a VM (`base`):** Incus container with IPv4, DNS and internet; Incus VM boots with IPv4, and its agent can take over 60 s to come up (`incus exec` was confirmed later on a KDE guest); `incus-admin` group; Flatpaks; `bootc switch` from a local disk to GHCR; `bootc upgrade`; the update notification, end to end as reported by the owner; zsh, Starship, Konsole profile and Yakuake.

**Verified in a VM (`xps16-da16260`, `45.20261105`, 2026-11-05):** boots from a local disk; `bootc switch` to GHCR; no layered packages; `bootc rollback` in both directions, with the home directory kept; Flatpak install. `bootc switch --enforce-container-sigpolicy` deploys as `ostree-image-signed`, and `bootc upgrade --check` reports no error, but that was the same digest, so no new image has been accepted or refused under it yet.

**Verified in a VM (`xps16-da16260`, `45.20261106`, 2026-11-05):**
- Enforced signatures: an image signed with the current key was accepted through both `bootc switch` and `bootc upgrade`, and an image signed with the old key was refused with a signature error, leaving the deployments unchanged.
- MesloLGS Nerd Font in Konsole, with the prompt icons, after the `fc-cache -f` fix. `tests/smoke.sh` catches the original failure.
- `breeze-custom`, `BreezeDarkCustom` and dark icons without choosing them, on a user who first logged in on an older image. Taskbar indicators follow the accent color.
- `docker run`, and `docker compose up` and `down` with nginx, a published port and a named volume, which survives `down`.
- Haruna opens an HEVC file from Dolphin by default and shows the picture. The owner heard its audio on 2026-11-06. Hardware decode was not checked.

**Verified in a VM (`xps16-da16260`, `45.20261111`, 2026-11-11):** after `bootc upgrade`, it boots kernel 7.3.3-300.fc45 and reaches Plasma on Wayland, as shown by the owner's Info Center. Nothing else was checked on it.

**Verified in a VM (local `base` build, 2026-11-06):** `incus start --console=vga` opened an empty Incus VM's UEFI screen in `spicy`, in a test build with `spice-gtk-tools`. The owner found it ugly, so it is not in the image.

**Verified in a VM, nested (local `base` build, 2026-11-06):** an openSUSE Tumbleweed KDE Incus VM (`images:opensuse/tumbleweed/desktop-kde`) reached Plasma on Wayland, and `incus exec` reached it, with `spice-vdagentd` active. KRDC's nightly Flatpak (`26.11.70`) showed its screen with working input, through a temporary `socat` bridge to port 5930, since KRDC only speaks TCP or `.vv` files. The owner reports other features worked, within the limits of nesting; audio could not be tested. Nothing from KRDC is in the image.

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
- On the XPS: VRR and display glitches (`kscreen-doctor -o`), Intel encode and decode in Chrome (steps in `README.md`), Wayland screen sharing in a real call, temperature, battery and suspend, and the internal camera, which probably does not work with the stock kernel.
- Whether the Intel video flags in `xps16-da16260` are needed, or do anything: compare a real video with and without them on the XPS. `AcceleratedVideoEncoder` may not be the current name, since other sources use `VaapiVideoEncoder`.
- `mcelog.service` failed in the VM, probably because it is a VM. Check it on the XPS.
- The metered check and the old image warning on a real session. Their scripts were only exercised in a container, with stubs.
- Flatpak launchers on a real session: Slack and ONLYOFFICE arguments, and `TryExec` hiding an app that is not installed. The copy logic and overrides were only exercised in a container.
- The system title bar and Qt colors in a real browser. Fresh headless Chrome and Brave profiles with `--force-first-run` wrote both preferences; additional profiles and how the colors look were not checked.
- GNOME Network Displays on KDE with real Wi-Fi and a real display. Some Samsung TVs are reported to need `dnsmasq`, which is not in the image.
- Installing a system from an ISO through a VM viewer.
- Opening a `.rar` in Ark. `unar` is the backend, since neither `rar` nor `unrar` is in the image.

**Verified in a VM, nested (`xps16-da16260` guest of QEMU, 2026-11-06):** `mise run vm-incus base` imported a `base` disk and booted it as `base-test`, with IPv4, and KRDC's nightly Flatpak showed its Plasma welcome screen through the `socat` bridge. A second run left the VM as it was. `incus exec` does not work on these disks (`VM agent isn't currently running`), so use SSH or `incus console`. They have no `spice-vdagent` either, so KRDC warns about it, and clipboard and resizing should not work. Audio, and running the whole flow on the XPS, are untested.

**Decided by the owner:** hosts use `:latest` (2026-11-05). A Fedora upgrade still only happens when `FEDORA_VERSION` changes here.

**Also decided by the owner:** `incus-startup.service` stays disabled (2026-11-06). Instances are started by hand: Incus is meant for running large stacks with resource limits, so they cannot starve video calls, and nothing needs to start at boot.

**Firewall, decided by the owner (2026-11-07):** the default zone is `bootc-laptop`: DHCPv6, mDNS, KDE Connect, and TCP 7236 and 7250 for GNOME Network Displays, which the owner also uses away from home. Trusted home networks are set to `FedoraWorkstation` by hand. `tailscale0` is in `bootc-tailscale`, which accepts everything. Validated with `firewall-offline-cmd --check-config` only: KDE Connect, Network Displays, Tailscale and Incus forwarding under the new default zone are untested. The Network Displays ports come from Miracast, not from its documentation.

**VM viewer, decided by the owner (2026-11-06):** KRDC, KDE's own viewer, once it ships with SPICE. The image has no VM viewer until then. See section 11.

**Decisions pending from the owner:**
- Secure Boot on the XPS, which decides whether `.dellptl` needs MOK signing in CI.
- Whether to use the internal camera or a USB webcam for video calls.

**Known small improvements, not applied:**
- A second update staged while the first notification is still open is not announced, because `notify-send` is still waiting. The restart applies the newest one anyway.
- A wrong ID in `flatpaks.list` makes `bootc-flatpaks.service` retry every hour without end.
- Nothing prunes old tags on GHCR.
- `mise run build` reuses a stale local base.

---

## 11. VM viewers

Reviewed on 2026-11-06, with Incus 6.23 and Fedora 45. **The owner chose KRDC.** Unless a row says it was run, this comes from reading source code and measuring packages.

The image has no viewer yet. Without one, Incus prints the socket URI and waits, while `incus exec` and the text console still work.

### How Incus opens a VM's screen

`incus console --type=vga` and `incus start --console=vga` run the first viewer they find, in this order: `console_spice_command` from `~/.config/incus/config.yml` (`SOCKET` becomes the full URI), `remote-viewer`, `spicy`. On Linux the viewer always gets a private Unix socket as `spice+unix://<path>`, with no password.

- `remote-viewer` wins if both it and `spicy` are installed.
- The viewer must stay in the foreground: Incus closes the socket when it exits, and kills it when the console ends.
- Only one console per instance, unless `--force` is used.
- Clipboard and resize need `spice-vdagent` in the guest. `incus-agent` plays no part.

### Options

| Option | Reaches Incus | Cost on `base` | Notes | Status |
|---|---|---|---|---|
| `spicy` (`spice-gtk-tools`) | Yes | 2 MiB | GTK3. No Ctrl+Alt+Del action. Run: UEFI screen | Rejected by the owner: ugly |
| `remote-viewer` (`virt-viewer`) | Yes | 40 MiB, with libvirt libraries and no daemon | Header bar cannot be hidden in a window. Can send key combinations | Fallback for USB or Ctrl+Alt+Del |
| KRDC 26.08 (Fedora today) | No | 4 MiB | No SPICE plugin | Wait |
| KRDC nightly Flatpak | Through a TCP bridge | 8.4 MB, plus a 415 MB runtime | Real Plasma look. No USB or shared folders in its code. Run: see the status above | **Chosen**, once it ships |
| Remmina | Only with a script (`unix:///path`) | 9 MiB | Separate manager window | Not worth it |
| Field Monitor | Flatpak needs a socket permission | 81.4 MB | libadwaita | Not a fit |
| GNOME Connections | No, TCP only | 5 MiB | | No |
| `incus-ui-canonical` | Yes, through the API | About 4.6 MB | No Fedora package, and it targets Incus 7. Fits remote access, not daily use | Plan B |
| `lxc/incus-ui` | Not yet | | New official UI with no instance support, and it requires Incus 7 | Wait |
| QEMU's GTK window | No | | QEMU runs as a daemon under `incusd`, with no access to the session | Discarded |
| VNC through `raw.qemu` | Unsupported | | Upstream does not plan VNC. Not tried | Discarded |
| Karton, virt-manager | No | | Need the libvirt stack, a non-goal | Excluded |

### Testing images on a machine running the image

The owner tests branches on the XPS with Incus and KRDC, not with `vm-up`, which needs QEMU's GTK and PipeWire modules that the image does not have.

```bash
mise run vm base
mise run vm-incus base --cpus 8 --memory 16GiB   # defaults: 4 vCPUs, 8GiB
incus console base-test --type=vga
incus delete -f base-test                        # needed after rebuilding the disk
```

After a rebuild, `vm-incus` refuses to start until the old VM is erased. Hardware checks still need `mise run switch-local`, since a VM cannot see the Intel GPU.

### Adopting KRDC after KDE Gear 26.12

KRDC's plugin is in `release/26.12` with `WITH_SPICE` on by default. Gear 26.12 tarballs are due on 2026-12-03. Fedora's `krdc.spec` has no `spice-glib` dependency yet.

1. See whether Fedora ships it: `dnf5 repoquery krdc`, then look for `krdc_spiceplugin.so` in the package. If so, add `krdc` to `packages.txt`. If only Flathub has it, add `org.kde.krdc` to `flatpaks.list`.
2. See whether upstream accepts sockets: `spice/spiceviewfactory.cpp` and `spice/spiceview.cpp` in `network/krdc`. They only used `host` and `port` on 2026-11-06, while spice-glib has a `unix-path` property.
3. Without socket support, use this bridge as `remote-viewer` in a directory on `PATH`, with `flatpak run` replaced by `krdc` for the RPM. Its port has no password, so any local program can open the console. In the image it would go in `/usr/libexec/bootc-images/`, set through `console_spice_command`, which is per user.

   ```bash
   #!/usr/bin/env bash
   socket="${1#spice+unix://}"
   socat TCP-LISTEN:5930,bind=127.0.0.1,fork,reuseaddr "UNIX-CONNECT:$socket" &
   trap "kill \$! 2>/dev/null" EXIT
   sleep 1
   flatpak run org.kde.krdc//master spice://127.0.0.1:5930
   ```

4. To try it before Fedora ships it, install the nightly from `https://cdn.kde.org/flatpak/krdc-nightly/krdc-nightly.flatpakrepo`, with Flathub added for the runtime.
5. Test a guest with `images:opensuse/tumbleweed/desktop-kde`, which comes with `spice-vdagent`. Use `-c security.secureboot=false`.
6. On the XPS, check **Grab Keys** with Alt+Tab and Meta, Ctrl+Alt+Del, audio, clipboard both ways, resizing, and sharpness at the panel's scale.

KRDC's code has no USB redirection or shared folders. If those are needed, add a second viewer for that.

## 12. References

- bootc: <https://bootc-dev.github.io/bootc/>
- Fedora bootc docs: <https://docs.fedoraproject.org/en-US/bootc/>
- Universal Blue image template: <https://github.com/ublue-os/image-template>
- bootc-image-builder: <https://github.com/osbuild/bootc-image-builder>
- mise tasks: <https://mise.jdx.dev/tasks/>
- Brave Origin on Linux: <https://brave.com/origin/linux/>
- Incus console command: <https://github.com/lxc/incus/blob/v6.23.0/cmd/incus/console.go>
- KRDC source: <https://invent.kde.org/network/krdc>
- KDE Gear 26.12 schedule: <https://community.kde.org/Schedules/KDE_Gear_26.12_Schedule>
