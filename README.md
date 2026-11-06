# bootc-images

Personal bootc images, built daily, signed with cosign and published to `ghcr.io/ysantalla`.

| Image | FROM | What it adds |
|---|---|---|
| `base` | `ghcr.io/ublue-os/kinoite-main:45` | Incus, Brave Origin, Google Chrome, terminal setup, Tailscale, Flatpaks, auto-updates with a desktop notification. Codecs and Podman come from kinoite-main. No Docker engine, no libvirt, no Toolbx or Distrobox |
| `xps16-da16260` | `ghcr.io/ysantalla/base:45` | Dell XPS 16 (2026) DA16260: Intel VA-API driver for the Arc B390, and tools to measure battery, temperature and GPU use |

`base` is hardware-agnostic. Each machine gets its own image named after its model, containing only what that hardware needs.

## What base includes

| Component | How |
|---|---|
| KDE Plasma, codecs (ffmpeg), Podman | From `kinoite-main` |
| Incus | System containers and VMs (`--vm`), with QEMU and a firewalld zone for `incusbr0`. `incus.socket` enabled; group and subuid set up at boot |
| Brave Origin | Official RPM (`brave-origin`), no Rewards/Wallet/VPN/AI. Installed in `/usr/lib/brave.com`, linked to `/opt` via `tmpfiles.d` |
| Google Chrome | Official RPM, for video calls. Installed in `/usr/lib/google`, linked to `/opt` via `tmpfiles.d` |
| Browser defaults | Both browsers pick Wayland on their own. `xps16-da16260` adds Intel video flags to the menu launchers, which terminal launches and installed web apps do not get. The system title bar is a first-run preference |
| Docker commands | `docker` and `docker compose` run on rootless Podman, through `podman-docker` and the real Compose. There is no Docker engine, and images and volumes from Docker are not carried over |
| Plasma style | `breeze-custom` and the `BreezeDarkCustom` color scheme from [plasma-tips](https://github.com/ysantalla/plasma-tips), with custom taskbar indicators and dark icons, as the default for new users. Settings already in `~/.config` keep their choice |
| Interface fonts | Inter 11 across KDE, with no sub-pixel text. Noto stays the system sans-serif, and settings already in `~/.config` keep their choice |
| Okular | Native PDF and document viewer |
| Haruna | KDE video player, native, using the image's full ffmpeg (H.264, HEVC, VP9, AV1, DTS and more) and VA-API |
| Office fonts | Carlito and Caladea stand in for Calibri and Cambria with the same metrics, and Liberation covers Arial, Times New Roman and Courier New. Microsoft's own fonts are not in this public image: if you need them, copy them to `~/.local/share/fonts` on each machine and check your license |
| Terminal | zsh, Starship with a Powerlevel10k-style prompt, MesloLGS Nerd Font, Konsole profile and Yakuake (F12). Personal settings go in `~/.zshrc`, and `~/.config/starship.toml` replaces the factory prompt |
| Tailscale | Private network between your devices. `tailscaled` is enabled; run `sudo tailscale up` once to log in |
| Flatpaks | Zed, Slack, ONLYOFFICE and GNOME Network Displays. List in `flatpaks.list`. Slack and ONLYOFFICE get custom launchers and overrides |
| Updates | `bootc-update.timer`: downloads every ~6 h (on AC and non-metered connections only, catching up after suspend), applied on reboot. A desktop notification says when one is ready, and another warns if the running image is over 14 days old |

## Layout

```
.github/workflows/
  build.yml                  lint → base → xps16-da16260 (daily, on push, manual)
  reusable-build.yml         build + test + push to GHCR + cosign signature and verify
tests/smoke.sh               checks each built image from the inside, before it is published
images/
  base/
    Containerfile
    build_files/             build-time only, not shipped in the image
      build.sh               packages, browsers, terminal, services
      brave.sh               Brave Origin + /opt workaround
      chrome.sh              Google Chrome + /opt workaround
      browsers.sh            first-run browser preferences
      signing.sh             signature policy for machines that opt in
      shell.sh               Starship, Nerd Font and terminal defaults
      plasma-theme.sh        Plasma style, pinned to a plasma-tips commit
      tailscale.sh           Tailscale from its official repo
      packages.txt           Incus, QEMU, zsh, Yakuake, Okular
    system_files/            copied as-is to / in the image
      usr/libexec/bootc-images/           setup.sh, flatpaks.sh, update-*.sh, image-age.sh, desktop-entries.sh
      usr/lib/systemd/system/          bootc-* services and timer
      usr/lib/systemd/user/            update notification, old image warning, Flatpak launchers
      usr/lib/tmpfiles.d/              bootc-brave.conf, bootc-chrome.conf, bootc-flatpak-overrides.conf
      usr/lib/firewalld/zones/         bootc-incus.xml
      usr/share/bootc-images/          flatpaks.list, zshrc, starship.toml, applications/, cosign.pub
      usr/share/konsole/               bootc-images.profile
  xps16-da16260/
    Containerfile
    build_files/
      build.sh
      packages.txt           libva-intel-media-driver, libva-utils, powertop, lm_sensors, igt-gpu-tools
bib/config.example.toml      user for test VMs
mise.toml                    local tasks + cosign
```

## 1. One-time setup

```bash
mise trust && mise install        # installs cosign for this repo

# Signing key, with a password that only CI needs
cosign generate-key-pair

git init -b main
git add .
git status                        # cosign.pub listed, cosign.key NOT listed
git commit -m "Initial bootc images"

gh repo create ysantalla/bootc-images --public --source . --remote origin
gh secret set SIGNING_SECRET < cosign.key
gh secret set COSIGN_PASSWORD        # the password you just chose
git push -u origin main
```

`cosign.key` is git-ignored. CI is the only thing that needs it, so delete it from disk once the secrets are set. If a key is lost or exposed, generate a new pair, update both secrets, and commit the new `cosign.pub` in both places it lives: the repo root and `images/base/system_files/usr/share/bootc-images/`. CI checks that they match. Machines enforcing signatures must already run an image with the new key, or they stop updating until you switch them again.

The repo is public, so GitHub disables the daily schedule after 60 days without repository activity. It warns by email; re-enable the workflow if that happens.

After the first build, check that the images pull without credentials (`skopeo inspect docker://ghcr.io/ysantalla/base:45`). If not, make the `base` and `xps16-da16260` packages **public** in GHCR.

## 2. Test in a VM before touching real hardware

```bash
mise run vm base                   # output/base/qcow2/disk.qcow2
mise run vm xps16-da16260          # builds local base first if missing, then the XPS layer
mise run iso xps16-da16260         # installer ISO
```

Test disks are 40 GiB with the current `bib/config.example.toml`. If you already have a `bib/config.toml`, add its `[[customizations.filesystem]]` block by hand, because the file is not updated for you. Change the password there too. A 20 GiB disk fills up with Flatpaks, Incus images and two system versions.

Boot a throwaway copy with QEMU, leaving the built disk untouched, and log in with the user from `bib/config.toml`. The first boot is slow and the screen can stay black for a few minutes. **View → serial0** shows the boot messages meanwhile.

```bash
mise run vm-up xps16-da16260         # boots it, and creates the copy only if it is missing
mise run vm-up xps16-da16260 --gl    # with OpenGL through the host GPU
mise run vm-reset xps16-da16260      # erases the copy, after asking
```

- **Sharp text on a host with fractional scaling:** `vm-up` sets `GDK_BACKEND=x11 GDK_SCALE=1` so the host does not rescale QEMU's window. It needs KDE's XWayland scaling to match the monitor, and the VM stays on Wayland. Set the scale inside the VM to match.
- **Restarting:** use `sudo reboot` and `sudo poweroff` inside the VM. Closing the QEMU window is like pulling the plug.
- **Sound:** `vm-up` plays through the host, with no microphone input.
- **Copying files and text:** run `sudo systemctl enable --now sshd` in the VM, then `ssh -p 2222 yasmany@localhost` and `scp -P 2222` from the host.
- **Updates in the VM:** the disk points at `localhost/<image>:latest`, so `bootc-update.service` fails until you run `sudo bootc switch ghcr.io/ysantalla/<image>:latest`.
- **`--gl`:** gives the VM OpenGL for testing GPU compositing, but no Vulkan. It froze the desktop once, with Plasma and KWin using most of the CPU, so leave it off unless you need it. Do not trust the `Video Decode` line in `chrome://gpu` here: nothing shows video really decoding in hardware.
- **What a VM cannot test:** it has no Intel GPU, and the Intel driver is only in `xps16-da16260`, so `vainfo` fails there. An Incus VM inside this VM is slow, and its agent may take more than a minute to start.

## 3. Install on a machine

**Recommended:** install stock Fedora Kinoite, then switch to the image. You get the normal installer with disk encryption, and the previous system stays in the boot menu.

1. Install `Fedora-Kinoite-Installer-45-1.4.x86_64.iso` from <https://download.fedoraproject.org/pub/fedora/linux/releases/45/Kinoite/x86_64/iso/>. Back up first, enable encryption and create your user.
2. Switch, on AC power and online:

   ```bash
   sudo bootc switch ghcr.io/ysantalla/xps16-da16260:latest
   systemctl reboot
   ```

   If `bootc` is missing, use `sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ysantalla/xps16-da16260:latest`. If it complains about the signature, use `ostree-unverified-registry:` instead of `ostree-image-signed:docker://`.

Log out and back in once so the `incus-admin` group takes effect. Then, the first time:

```bash
incus admin init --minimal
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc
```

**Avoid `mise run iso` on a machine with data.** That installer may erase the disk without asking (not confirmed in its docs). It also includes the `bib/config.toml` user, and it is built from a local image, so you would have to run `bootc switch` afterwards for updates to work. The 40 GiB disk setting may not be accepted for ISOs; if the build rejects it, remove that block from `bib/config.toml`.

### Require signed images (optional)

The image carries the policy and key, but a machine only enforces them after this, once per machine:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/ysantalla/xps16-da16260:latest
```

From then on it refuses unsigned images. Tags built before the key rotation of 2026-11-05 are signed with the old key and will be refused too.

## 4. Verify

```bash
sudo bootc status                              # current image and rollback
rpm-ostree status                              # no LayeredPackages
systemctl status bootc-setup bootc-flatpaks
systemctl list-timers bootc-update.timer
id -nG                                         # includes incus-admin
incus list
flatpak list --system
vainfo | grep -E 'iHD|H264|HEVC|AV1'           # xps16-da16260 only: hardware decode
```

### Hardware video in Chrome (xps16-da16260 only)

1. `vainfo | grep -E 'Driver version|EncSlice'` should show `iHD` and encode profiles.
2. In `chrome://gpu`, check `Video Encode`, `Video Decode` and `Ozone platform`.
3. Test without a camera, pressing **Start** and **Call**:

   ```bash
   google-chrome-stable --use-fake-device-for-media-stream --use-fake-ui-for-media-stream \
     https://webrtc.github.io/samples/src/content/peerconnection/pc1/
   ```

4. In `chrome://webrtc-internals`, under `outbound-rtp`: `powerEfficientEncoder: true` means hardware, while `libvpx`, `OpenH264` or `libaom` as `encoderImplementation` means CPU.
5. Repeat in a real call, because each platform picks its own codec. `nvtop` shows CPU and GPU use.

The image's menu launchers already pass `--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL` on this machine. A browser started from a terminal does not get it, so add the flags to the command above. Feature names change between Chrome versions, and the browser wrappers do not read a flags file, so permanent flags go in the `.desktop` file at build time (`browsers.sh`, and `build.sh` in the machine image).

## Day to day

```bash
sudo bootc upgrade             # download now (applied on reboot)
sudo bootc rollback            # go back to the previous version
sudo ostree admin pin 0        # pin a deployment you know is good
sudo bootc switch ghcr.io/ysantalla/xps16-da16260:45-20261201   # go back to a specific build
sudo bootc usr-overlay         # TEMPORARY writable /usr to try something out
sudo bootc upgrade --check     # look for an update without downloading it
sudo powertop                  # xps16-da16260: what uses the battery (avoid --auto-tune)
sensors                        # xps16-da16260: temperatures and fans
sudo intel_gpu_top             # xps16-da16260: GPU and video engines, may be limited on xe
```

When `bootc-update.timer` downloads an update, a notification shows the version and a **Restart now** button. It never restarts by itself, and it comes back at each login until you restart.

To change the prompt, pick a [Starship preset](https://starship.rs/presets/): `starship preset gruvbox-rainbow -o ~/.config/starship.toml`, then open a new tab. Delete that file to go back to the default.

Projects that need compilers go in an Incus container, not in the image.

## Changing an image

- **New package:** add it to `images/<image>/build_files/packages.txt`.
- **New Flatpak:** add it to `images/base/system_files/usr/share/bootc-images/flatpaks.list`. Installed on next boot.
- **Custom Flatpak launcher:** add a `.desktop` with `TryExec` and `X-Bootc-Images-Managed=true` to `usr/share/bootc-images/applications/`. It is copied to `~/.local/share/applications` at login. A file there without that marker is yours and is left alone, and our copy does not follow changes the app makes to its own launcher.
- **Script or service:** put it under `system_files/usr/...` and enable it in `build.sh`.
- **New machine:** copy `images/xps16-da16260` to `images/<model>`, adjust it, and add a job to `build.yml`.
- **Fedora upgrade:** change `FEDORA_VERSION` in both Containerfiles, `build.yml` and `mise.toml`.
- **Plasma style update:** change `THEME_COMMIT` in `images/base/build_files/plasma-theme.sh` to the new `plasma-tips` commit.
- **Starship or Nerd Font upgrade:** change the version and sha256 in `images/base/build_files/shell.sh`. They do not update by themselves.

Rules:

- Nothing in `/var` from a Containerfile (it's only copied on first install). Use `tmpfiles.d`.
- Nothing in `/opt`. Prefer Flatpak for apps that install there, or use the `brave.sh` pattern.
- Our files go in `/usr`; `/etc` only for defaults that can be overridden locally.

## Notes

- The build disables `rpm-ostreed-automatic.timer` and `uupd.timer` if present, so there's only one updater.
- Brave Origin and Chrome update with the image (daily build), not from the machine: their repos are disabled in `/etc/yum.repos.d`.
- Hosts follow `:latest`, so bumping `FEDORA_VERSION` moves them to the new Fedora release on the next update.
- `ujust` recipes from Universal Blue that use Distrobox or Toolbx no longer work.
- Removing a name from `flatpaks.list` does not uninstall it from existing machines: use `flatpak uninstall`.
- Flatpak apps don't use the host's codecs or VA-API driver; they use their runtime's (`ffmpeg-full` and the Intel VA-API extension).
- Project status, findings and planned work are in `CLAUDE.md`.
