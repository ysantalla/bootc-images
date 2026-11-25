# Incus, VM viewers and the firewall

Containers and virtual machines with Incus, the viewers tried for their screens, and the firewalld zones and policies.

## Verified

**Verified in a VM (local `base` build, 2026-11-06):** `incus start --console=vga` opened an empty Incus VM's UEFI screen in `spicy`, in a test build with `spice-gtk-tools`. The owner found it ugly, so it is not in the image.

**Verified in a VM, nested (local `base` build, 2026-11-06):** an openSUSE Tumbleweed KDE Incus VM (`images:opensuse/tumbleweed/desktop-kde`) reached Plasma on Wayland, and `incus exec` reached it, with `spice-vdagentd` active. KRDC's nightly Flatpak (`26.11.70`) showed its screen with working input, through a temporary `socat` bridge to port 5930, since KRDC only speaks TCP or `.vv` files. The owner reports other features worked, within the limits of nesting; audio could not be tested. Nothing from KRDC is in the image.

**Verified in a VM, nested (`xps16-da16260` guest of QEMU, 2026-11-06):** `mise run vm-incus base` imported a `base` disk and booted it as `base-test`, with IPv4, and KRDC's nightly Flatpak showed its Plasma welcome screen through the `socat` bridge. A second run left the VM as it was. `incus exec` does not work on these disks (`VM agent isn't currently running`), so use SSH or `incus console`. They have no `spice-vdagent` either, so KRDC warns about it, and clipboard and resizing should not work. Audio, and running the whole flow on the XPS, are untested.

**Verified in the same VM (2026-11-24), with an Alpine container on `incusbr0`:**
- Before `katze-incus-private`: the container reached the internet and, through the host, the VM's upstream network (10.0.2.3:53 and 10.0.2.2:631, the host machine's CUPS), but not the host's own ports.
- With the policy installed in `/etc/firewalld/policies` and a reload: the internet by address and by name still works, both upstream addresses are rejected, the host's ports stay closed, and a restarted container gets its address again.

## Not tested yet

- `katze-incus-private` with a real tailnet, with IPv6, with an Incus VM, and shipped in the image under `/usr/lib/firewalld`. A project that needs something on the local network from its container has no switch for it yet.
- `incus admin init` with a btrfs pool, as `README.md` now says, instead of `--minimal`'s `dir` pool. The prompts it describes come from Incus's interactive init, not from a run.
- Installing a system from an ISO through a VM viewer.
