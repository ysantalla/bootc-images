# VM viewers

Reviewed on 2026-11-06, with Incus 6.23 and Fedora 45. **The owner chose KRDC.** Unless a row says it was run, this comes from reading source code and measuring packages.

The image has no viewer yet. Without one, Incus prints the socket URI and waits, while `incus exec` and the text console still work.

## How Incus opens a VM's screen

`incus console --type=vga` and `incus start --console=vga` run the first viewer they find, in this order: `console_spice_command` from `~/.config/incus/config.yml` (`SOCKET` becomes the full URI), `remote-viewer`, `spicy`. On Linux the viewer always gets a private Unix socket as `spice+unix://<path>`, with no password.

- `remote-viewer` wins if both it and `spicy` are installed.
- The viewer must stay in the foreground: Incus closes the socket when it exits, and kills it when the console ends.
- Only one console per instance, unless `--force` is used.
- Clipboard and resize need `spice-vdagent` in the guest. `incus-agent` plays no part.

## Options

| Option | Reaches Incus | Cost on `base` | Notes | Status |
|---|---|---|---|---|
| `spicy` (`spice-gtk-tools`) | Yes | 2 MiB | GTK3. No Ctrl+Alt+Del action. Run: UEFI screen | Rejected by the owner: ugly |
| `remote-viewer` (`virt-viewer`) | Yes | 40 MiB, with libvirt libraries and no daemon | Header bar cannot be hidden in a window. Can send key combinations | Fallback for USB or Ctrl+Alt+Del |
| KRDC 26.08 (Fedora today) | No | 4 MiB | No SPICE plugin | Wait |
| KRDC nightly Flatpak | Through a TCP bridge | 8.4 MB, plus a 415 MB runtime | Real Plasma look. No USB or shared folders in its code. Run: see `status/incus-and-network.md` | **Chosen**, once it ships |
| Remmina | Only with a script (`unix:///path`) | 9 MiB | Separate manager window | Not worth it |
| Field Monitor | Flatpak needs a socket permission | 81.4 MB | libadwaita | Not a fit |
| GNOME Connections | No, TCP only | 5 MiB | | No |
| `incus-ui-canonical` | Yes, through the API | About 4.6 MB | No Fedora package, and it targets Incus 7. Fits remote access, not daily use | Plan B |
| `lxc/incus-ui` | Not yet | | New official UI with no instance support, and it requires Incus 7 | Wait |
| QEMU's GTK window | No | | QEMU runs as a daemon under `incusd`, with no access to the session | Discarded |
| VNC through `raw.qemu` | Unsupported | | Upstream does not plan VNC. Not tried | Discarded |
| Karton, virt-manager | No | | Need the libvirt stack, a non-goal | Excluded |

## Testing images on a machine running the image

Two ways. `mise run vm-up <image>` runs the disk with QEMU in the background, with its screen over VNC, since the image's QEMU has no window (GTK) and no PipeWire sound, and `mise run vm-view <image>` shows it in KRDC (README, section 2). Or with Incus and KRDC, as below.

```bash
mise run vm base
mise run vm-incus base --cpus 8 --memory 16GiB   # defaults: 4 vCPUs, 8GiB
sudo incus console base-test --type=vga        # Incus needs sudo: nobody is in incus-admin
sudo incus delete -f base-test                   # needed after rebuilding the disk
```

After a rebuild, `vm-incus` refuses to start until the old VM is erased. Hardware checks still need `mise run switch-local`, since a VM cannot see the Intel GPU.

## Adopting KRDC after KDE Gear 26.12

KRDC's plugin is in `release/26.12` with `WITH_SPICE` on by default. Gear 26.12 tarballs are due on 2026-12-03. Fedora's `krdc.spec` has no `spice-glib` dependency yet.

1. See whether Fedora ships it: `dnf5 repoquery krdc`, then look for `krdc_spiceplugin.so` in the package. If so, add `krdc` to `packages.txt`. If only Flathub has it, add `org.kde.krdc` to `flatpaks.list`.
2. See whether upstream accepts sockets: `spice/spiceviewfactory.cpp` and `spice/spiceview.cpp` in `network/krdc`. They only used `host` and `port` on 2026-11-06, while spice-glib has a `unix-path` property.
3. Without socket support, use this bridge as `remote-viewer` in a directory on `PATH`, with `flatpak run` replaced by `krdc` for the RPM. Its port has no password, so any local program can open the console. In the image it would go in `/usr/libexec/katze/`, set through `console_spice_command`, which is per user.

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

## References

- Incus console command: <https://github.com/lxc/incus/blob/v6.23.0/cmd/incus/console.go>
- KRDC source: <https://invent.kde.org/network/krdc>
- KDE Gear 26.12 schedule: <https://community.kde.org/Schedules/KDE_Gear_26.12_Schedule>
