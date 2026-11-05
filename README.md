# bootc-images

Personal bootc images, built daily, signed with cosign and published to `ghcr.io/ysantalla`.

| Image | FROM | What it adds |
|---|---|---|
| `base` | `ghcr.io/ublue-os/kinoite-main:45` | Incus, Brave Origin, Flatpaks, auto-updates. Codecs and Podman come from kinoite-main. No Docker, no libvirt |
| `xps16-da16260` | `ghcr.io/ysantalla/base:45` | Dell XPS 16 (2026) DA16260: Intel VA-API driver for the Arc B390 |

`base` is hardware-agnostic. Each machine gets its own image named after its model, containing only what that hardware needs.

## What base includes

| Component | How |
|---|---|
| KDE Plasma, codecs (ffmpeg), Podman | From `kinoite-main` |
| Incus | System containers and VMs (`--vm`). `incus.socket` enabled; group and subuid set up at boot |
| Brave Origin | Official RPM (`brave-origin`), no Rewards/Wallet/VPN/AI. Installed in `/usr/lib/brave.com`, linked to `/opt` via `tmpfiles.d` |
| Flatpaks | Zed, GNOME Boxes (for test VMs). List in `flatpaks.list` |
| Updates | `ysantalla-update.timer`: downloads every ~12 h (on AC only), applied on reboot |

## Layout

```
.github/workflows/
  build.yml                  base → xps16-da16260 (daily, on push, manual)
  reusable-build.yml         build + push to GHCR + cosign signature
images/
  base/
    Containerfile
    build_files/             build-time only, not shipped in the image
      build.sh               packages, Brave, services
      brave.sh               Brave Origin + /opt workaround
      packages.txt           incus
    system_files/            copied as-is to / in the image
      usr/libexec/ysantalla/           setup.sh, flatpaks.sh
      usr/lib/systemd/system/          ysantalla-* services and timer
      usr/lib/tmpfiles.d/              ysantalla-brave.conf
      usr/share/ysantalla/flatpaks.list
  xps16-da16260/
    Containerfile
    build_files/
      build.sh
      packages.txt           intel-media-driver, libva-utils
bib/config.example.toml      user for test VMs
mise.toml                    local tasks + cosign
```

## 1. One-time setup

```bash
mise trust && mise install        # installs cosign for this repo

# Signing key WITHOUT a password (press Enter twice)
cosign generate-key-pair

git init -b main
git add .
git status                        # cosign.pub listed, cosign.key NOT listed
git commit -m "Initial bootc images"

gh repo create ysantalla/bootc-images --public --source . --remote origin
gh secret set SIGNING_SECRET < cosign.key
git push -u origin main
```

`cosign.key` is git-ignored. Keep it in your password manager and delete it from disk.

The repo is public, so GitHub disables the daily schedule after 60 days without repository activity. It warns by email; re-enable the workflow if that happens.

After the first build, check that the images pull without credentials (`skopeo inspect docker://ghcr.io/ysantalla/base:45`). If not, make the `base` and `xps16-da16260` packages **public** in GHCR.

## 2. Test in a VM before touching real hardware

```bash
mise run vm base                   # output/base/qcow2/disk.qcow2
mise run vm xps16-da16260          # builds local base first if missing, then the XPS layer
mise run iso xps16-da16260         # installer ISO
```

Open the `.qcow2` in GNOME Boxes and log in with the user from `bib/config.toml`.

## 3. Install on a machine

Option A: boot the ISO from `mise run iso <image>`.

Option B: from an existing Kinoite install:

```bash
sudo bootc switch ghcr.io/ysantalla/xps16-da16260:latest
systemctl reboot
```

Log out and back in once so the `incus-admin` group takes effect. Then, the first time:

```bash
incus admin init --minimal
```

## 4. Verify

```bash
bootc status                                   # current image and rollback
rpm-ostree status                              # no LayeredPackages
systemctl status ysantalla-setup ysantalla-flatpaks
systemctl list-timers ysantalla-update.timer
id -nG                                         # includes incus-admin
incus list
flatpak list --system
vainfo | grep -E 'iHD|H264|HEVC|AV1'           # xps16-da16260 only: hardware decode
```

## Day to day

```bash
sudo bootc upgrade             # download now (applied on reboot)
sudo bootc rollback            # go back to the previous version
sudo ostree admin pin 0        # pin a deployment you know is good
sudo bootc switch ghcr.io/ysantalla/xps16-da16260:45-20261201   # go back to a specific build
sudo bootc usr-overlay         # TEMPORARY writable /usr to try something out
```

## Changing an image

- **New package:** add it to `images/<image>/build_files/packages.txt`.
- **New Flatpak:** add it to `images/base/system_files/usr/share/ysantalla/flatpaks.list`. Installed on next boot.
- **Script or service:** put it under `system_files/usr/...` and enable it in `build.sh`.
- **New machine:** copy `images/xps16-da16260` to `images/<model>`, adjust it, and add a job to `build.yml`.
- **Fedora upgrade:** change `FEDORA_VERSION` in both Containerfiles, `build.yml` and `mise.toml`.

Rules:

- Nothing in `/var` from a Containerfile (it's only copied on first install). Use `tmpfiles.d`.
- Nothing in `/opt`. Prefer Flatpak for apps that install there, or use the `brave.sh` pattern.
- Our files go in `/usr`; `/etc` only for defaults that can be overridden locally.

## Notes

- Fedora 45 shipped on 2026-11-03. If `kinoite-main:45` doesn't exist yet, use `44`.
- The build disables `rpm-ostreed-automatic.timer` and `uupd.timer` if present, so there's only one updater.
- Brave Origin updates with the image (daily build), not from the machine: Brave's repo is disabled in `/etc/yum.repos.d`.
- Flatpak apps don't use the host's codecs or VA-API driver; they use their runtime's (`ffmpeg-full` and the Intel VA-API extension).
- Planned for `xps16-da16260`, one step at a time: auto-boost service (RAPL PL2), then the `.dellptl` kernel (IPU7 webcam, IR, ISH) with Secure Boot signing.
