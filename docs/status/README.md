# Status: what was tested and what was not

One file per subject, so that two changes rarely write to the same place:

| File | Subject |
|---|---|
| [image-and-updates.md](image-and-updates.md) | Building and publishing, `bootc switch`, upgrades, rollback, signatures, the update notification |
| [incus-and-network.md](incus-and-network.md) | Incus containers and VMs, VM viewers, the firewall |
| [theme-and-icons.md](theme-and-icons.md) | The Katze themes, color schemes, Plasma style, icons, fonts, the terminal's look |
| [applications.md](applications.md) | Browsers, Flatpaks and launchers, Docker commands, added applications |
| [xps16-da16260.md](xps16-da16260.md) | What needs the real XPS 16 |

Each has **Verified**, with the date and where it was run in every entry, and **Not tested yet**. The log started on 2026-11-05 in `CLAUDE.md`, which keeps the roadmap and the owner's decisions (section 10).

- Add a result under **Verified** when something is tested, and take it out of **Not tested yet**.
- Never record something as verified if it was not run.
- Two open pull requests that add to the same list conflict. Put the entry in the file of its subject, and when another pull request is open on that file, add it after that one merges.
