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
- **Incus:** system containers and KVM virtual machines (`incus launch ... --vm`).
- **Brave Origin:** native RPM (`brave-origin`), the stripped-down Brave without Rewards, Wallet, VPN or AI features.
- **Google Chrome:** native RPM (`google-chrome-stable`), used for video calls. Same `/opt` handling as Brave (`chrome.sh`).
- **System Flatpaks** from a declarative list (Zed).
- **First-boot and every-boot setup:** the `incus-admin` group and subuid/subgid ranges.
- **Our own update timer**, which replaces any upstream updater.

**`xps16-da16260` adds:** `libva-intel-media-driver` and `libva-utils` for hardware video decode (H.264, HEVC, VP9, AV1) on the Arc B390.

### Explicit non-goals

These are deliberate choices. Do not add them back without the owner asking:
- **Docker**: Podman is the container engine.
- **libvirt / virt-manager / GNOME Boxes**: Incus handles VMs, including GUI ones (`--console=vga`).
- **Toolbx / Distrobox**: removed from `kinoite-main` on purpose; Incus handles containers.
- **Package layering on hosts** (`rpm-ostree install`): every change goes through the image.
- **Out-of-tree kernels in `base`.**

---

## 2. Repository layout

```
.
├── CLAUDE.md                          this file
├── README.md                          user-facing setup and usage guide
├── mise.toml                          local tasks + tool versions (cosign)
├── cosign.pub                         public signing key (committed)
├── .gitignore                         output/, bib/config.toml, cosign.key
├── bib/
│   └── config.example.toml            user for test VMs built with bootc-image-builder
├── .github/workflows/
│   ├── build.yml                      orchestrator: base → machine images
│   └── reusable-build.yml             build → push to GHCR → cosign sign
└── images/
    ├── base/
    │   ├── Containerfile
    │   ├── build_files/               build-time only, NOT shipped in the image
    │   │   ├── build.sh               entry point: packages, Brave, services
    │   │   ├── brave.sh               Brave Origin install + /opt workaround
    │   │   ├── chrome.sh              Google Chrome install + /opt workaround
    │   │   └── packages.txt           extra RPMs, one per line
    │   └── system_files/              copied verbatim to / in the image
    │       └── usr/
    │           ├── libexec/ysantalla/ setup.sh, flatpaks.sh
    │           ├── lib/systemd/system/ ysantalla-*.service / .timer
    │           ├── lib/tmpfiles.d/    ysantalla-brave.conf
    │           └── share/ysantalla/   flatpaks.list
    └── xps16-da16260/
        ├── Containerfile
        └── build_files/
            ├── build.sh
            └── packages.txt
```

### Build pattern (every image follows it)

1. A `ctx` stage (`FROM scratch`) holds `build_files/`. It is bind-mounted during the build, so build scripts **never end up in the image**.
2. `system_files/` (when present) is copied to `/`.
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
- **Scripts** go in `/usr/libexec/ysantalla/`. **Units** go in `/usr/lib/systemd/system/` and are enabled in `build.sh`. **Static data** goes in `/usr/share/ysantalla/`.
- **Runtime state** goes in `/var/lib/ysantalla/`, created by the script that uses it or by `tmpfiles.d`.
- **Users and groups:** prefer `sysusers.d`. Groups shipped by packages live in `/usr/lib/group` (nss-altfiles); `usermod -aG` only works once the group is in `/etc/group` and `/etc/gshadow`. That is why `setup.sh` syncs `incus-admin`. Reuse that pattern for any new group.
- **RPMs that install into `/opt`:** follow `brave.sh`. Create a real `/opt`, install, move the result to `/usr/lib/<vendor>`, restore the `/opt -> var/opt` symlink, and add an `L` line in `tmpfiles.d`.
- **Third-party repos** added at build time must end up **disabled** (`enabled=0`). Updates arrive through the image, never from the host.

---

## 4. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Machine image | `<line><size>-<model>`, lowercase, from the vendor model | `xps16-da16260` |
| Our systemd units | `ysantalla-<purpose>.service/.timer` | `ysantalla-update.timer` |
| Our directories | `ysantalla` namespace under `/usr/libexec`, `/usr/share`, `/var/lib` | `/usr/share/ysantalla/flatpaks.list` |
| tmpfiles.d / sysusers.d | `ysantalla-<purpose>.conf` | `ysantalla-brave.conf` |
| Image tags | `latest`, `<fedora>`, `<fedora>-<YYYYMMDD>` | `45-20261201` |

All code, comments, unit descriptions and docs are in **English**.

---

## 5. Common tasks

All local tasks are defined in `mise.toml`. They need `mise` and rootful `podman` (via `sudo`).

```bash
mise tasks                          # list tasks
mise run build base                 # build an image locally
mise run build xps16-da16260        # builds local base first if missing
mise run vm base                    # qcow2 disk → output/base/qcow2/disk.qcow2 (boot steps in README)
mise run iso xps16-da16260          # installer ISO
mise run switch-local base          # switch THIS machine to a local build
mise run switch xps16-da16260       # switch THIS machine to the published image
mise run clean                      # remove output/
```

### Add a package

1. Add one line to `images/<image>/build_files/packages.txt`.
2. Hardware-specific? It goes in the machine image, never in `base`.
3. Run `mise run build <image>` and confirm the build and the lint pass.

### Add a Flatpak

Add its Flathub ID to `images/base/system_files/usr/share/ysantalla/flatpaks.list`. `ysantalla-flatpaks.service` installs it on the next boot whenever the list's hash changes. It only adds; it never removes.

### Add a script or service

1. Script: `system_files/usr/libexec/ysantalla/<name>.sh`, using `#!/usr/bin/env bash` and `set -euo pipefail`. It must be **idempotent** if it runs on boot.
2. Unit: `system_files/usr/lib/systemd/system/ysantalla-<name>.service`.
3. Enable it in that image's `build.sh` (`systemctl enable ...`).
4. Watch for ordering cycles: do not order a normal service `Before=` a socket unit (sockets start before `basic.target`).

### Add a new machine

1. `cp -r images/xps16-da16260 images/<model>` and strip it down to what the new hardware needs.
2. Add a job to `.github/workflows/build.yml` with `needs: base`, mirroring the XPS job.
3. Update the image table in `README.md` and in this file.

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
- **On pull requests,** only `base` is built and nothing is pushed. Machine images are skipped because the new base is not published.
- **`reusable-build.yml`** builds with buildah, pushes to GHCR using `GITHUB_TOKEN` (the owner is lowercased), and signs the digest with cosign using the `SIGNING_SECRET` secret.
- **Images are public** on GHCR, so machines pull without credentials.

A failed build never reaches a machine: hosts keep running the last good image.

---

## 7. Validation checklist

Run these before considering a change done. Never claim something was tested if it wasn't.

```bash
# Shell scripts
shellcheck images/*/build_files/*.sh images/*/system_files/usr/libexec/ysantalla/*.sh

# Workflows and TOML
python3 -c "import yaml,glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"
python3 -c "import tomllib; tomllib.load(open('mise.toml','rb')); tomllib.load(open('bib/config.example.toml','rb'))"

# Units (on a systemd host)
systemd-analyze verify images/base/system_files/usr/lib/systemd/system/ysantalla-*

# Real test: build, then boot it in a VM
mise run build <image>
mise run vm <image>
```

On a machine running the image:

```bash
bootc status                     # current image + rollback target
rpm-ostree status                # must show no LayeredPackages
systemctl --failed               # nothing from ysantalla-*
systemctl list-timers ysantalla-update.timer
id -nG                           # includes incus-admin
vainfo | grep iHD                # xps16-da16260 only
```

---

## 8. Safety rules

- **Never commit `cosign.key`**, `bib/config.toml`, or any credential. Only `cosign.pub` is committed.
- **Never remove `bootc container lint`** from a Containerfile.
- **Never use `:latest` for the upstream base.** Pin `FEDORA_VERSION`.
- **Never add a second updater.** `build.sh` disables `rpm-ostreed-automatic.timer` and `uupd.timer` on purpose.
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

---

## 10. Roadmap

Implement these one at a time, each in its own commit, in `xps16-da16260` only:

1. **Verify base** in a VM and on hardware: Incus, Brave Origin, Flatpaks, updates and rollback.
2. **auto-boost service.** A systemd daemon in `/usr` that sets RAPL PL2 to 60 W on AC power when CPU load is above 40%, and returns to 34 W plus the `balanced` profile otherwise. It polls every 10 s, through `/sys/class/powercap/intel-rapl/intel-rapl:0/constraint_1_power_limit_uw` and `powerprofilesctl`.
3. **`.dellptl` kernel** for the IPU7 webcam, IR face unlock and Intel ISH. This requires regenerating the initramfs (`dracut`) and signing for Secure Boot with an owner-enrolled MOK in CI. **Ask before starting.**
4. **Optional: enforce signed images** on hosts with `policy.json` and `registries.d` pointing at `cosign.pub`.

---

## 11. References

- bootc: <https://bootc-dev.github.io/bootc/>
- Fedora bootc docs: <https://docs.fedoraproject.org/en-US/bootc/>
- Universal Blue image template: <https://github.com/ublue-os/image-template>
- bootc-image-builder: <https://github.com/osbuild/bootc-image-builder>
- mise tasks: <https://mise.jdx.dev/tasks/>
- Brave Origin on Linux: <https://brave.com/origin/linux/>
