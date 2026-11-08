# Secrets, AI agents and dev containers

**Status: plan, researched on 2026-11-08. Nothing here is implemented or tested yet.** It collects what the owner and Claude worked out that day, so the work can resume once the XPS arrives (around 2026-11-24). Validate each part in a VM first (section 8), then on the XPS, and only then move it into the image, README and `CLAUDE.md`.

Drafts that go with this document live in [`devbox/`](../devbox/). They are not used by any image, task or workflow yet.

---

## 1. Threat model

A stolen laptop is no longer the main risk: full-disk encryption already covers it (`README.md`). The main risk is **anything that runs as the owner's user**:

- AI coding agents (Claude Code, Zed's agent) that read files and run commands, and can be steered by prompt injection in a README, issue, web page or dependency.
- Package install scripts (`npm`/`pip` post-install hooks). Supply-chain worms have stolen GitHub, npm and cloud credentials from developer machines this way.
- Editor extensions and other tools.

All of them can read `~/.aws`, `~/.ssh`, `.env` files, environment variables, and any keyring that is unlocked for the session.

The plan answers with four layers:

1. **No plaintext secrets on disk.** Tokens and keys live in the session keyring.
2. **Short-lived, least-privilege credentials**, so a leak is worth little.
3. **Isolation:** agents and dependency installs run in an Incus container per project, which only holds that project's scoped credentials.
4. **A human confirmation for the most powerful key:** the SSH agent asks before each use.

---

## 2. Decisions by the owner (2026-11-08)

- **Use what the image already ships.** No new password manager or keyring software (KeePassXC, 1Password, aws-vault, gitleaks): each one is more to maintain. Only configuration and small amounts of our own code are added.
- **KWallet stays as the Secret Service provider.** Replacing it was researched (section 3.2) and rejected for now.
- **Agents run in Incus, one container per project.** Each container holds one Claude Code account and only that project's tokens.
- **One minimal, shared dev image (`devbox`)** for every project. Per-project languages come from the project's own `mise.toml`. No zsh or Starship inside: the host's terminal setup is not replicated.

---

## 3. Secrets on the host

### 3.1 What the image already provides

| Piece | Comes from | Use |
|---|---|---|
| KWallet (`ksecretd`, Secret Service) | Kinoite | Token storage for `gh`, `glab`, browsers, and `secret-tool` |
| `secret-tool` | `libsecret` (Fedora) | Read and write the keyring from scripts, used for AWS below |
| `kwallet-query` | `kf6-kwallet` | Inspect wallets from a terminal |
| OpenSSH with FIDO2 (`ed25519-sk`) | Fedora | Hardware-backed SSH keys, if a security key is bought |
| `ksshaskpass` | `kinoite-main` | The KDE dialog for SSH passphrases and `ssh-add -c` confirmations |
| `yubikey-manager`, `pam-u2f`, `pam_yubico` | `kinoite-main` | Security key setup, and `sudo`/login with it |
| `gnupg2`, `systemd-cryptenroll` | Fedora | GPG if ever needed; LUKS unlock with TPM2 or FIDO2 |
| Incus, unprivileged by default | `base` | Per-project isolation (section 4) |
| Rootless Podman, no Docker daemon | `base` | A compromised container does not get root on the host |
| No Toolbx/Distrobox | `base` | Both mount the whole home directory into the container |
| `bootc-laptop` firewall zone, Tailscale | `base` | Nothing on untrusted networks reaches development ports |
| cosign signing, disabled third-party repos | `base` and CI | Supply chain of the OS itself |

**Zed's Flatpak is not a sandbox here:** it can read the home directory and its agent runs commands on the host. Use Zed as the editor, and run agents in the project's container (section 6).

### 3.2 KWallet in Fedora 45

Since KDE Frameworks 6.14, KWallet is two processes:

| Process | Role |
|---|---|
| `ksecretd` | The former KWallet backend. It provides `org.freedesktop.secrets` (Secret Service), which `gh`, `glab`, `secret-tool`, Chrome and Brave use |
| `kwalletd6` | A bridge: it keeps the old KWallet D-Bus API for apps such as the network applet and forwards those calls to whichever Secret Service provider is active |

**The limit of any session keyring:** while it is unlocked, any process of the user can ask it for a secret, and Secret Service has no per-application check. That is why isolation (section 4) is the real control, not the keyring.

**Replacing it was researched and set aside.** Notes for the future:
- `kwalletrc` keys: `[KSecretD] Enabled=false` stops `ksecretd`, and `[Migration] MigrateTo3rdParty=true` copies KWallet's data into the new provider on first use. KDE calls the latter experimental, and the copy may go to whichever provider answers first (KDE bug 504709). The old `[org.freedesktop.secrets] apiEnabled=false` key is from Plasma 5.
- D-Bus activation: the package ships `org.kde.secretservicecompat.service`. Whether it activates `org.freedesktop.secrets` is unconfirmed. A replacement provider may need its own `.service` file earlier in the search path so it wins activation.
- Known problems: plasma-nm could not read Wi-Fi passwords from a KeePassXC provider (KDE bug 504312), and Chromium and Electron apps have lost sessions at login even with KWallet itself (KDE bug 523878, Frameworks 6.26, open).
- **Turning `ksecretd` off with no other provider leaves no keyring at all:** `gh` and `glab` would fall back to plaintext files.

**Possible hardening with no new software (to check in a VM):**
- Close the wallet when idle and when the screen locks (System Settings → KDE Wallet). The `kwalletrc` key names have not been confirmed yet.
- A separate wallet for CLI tokens with its own password, which PAM does not open at login. Unclear: `gh`, `glab` and `secret-tool` write to the default collection, so this only works if that collection can be pointed at another wallet.

### 3.3 GitHub and GitLab CLIs

Both store their token in the Secret Service keyring when one is available. `glab` does so by default and only writes plaintext with `--insecure-storage`.

```bash
gh auth login --git-protocol ssh --web
glab auth login
gh auth status && glab auth status       # both should report the keyring
grep -l token ~/.config/gh/hosts.yml ~/.config/glab-cli/config.yml   # should list nothing
```

Install both per user with mise. Inside project containers, use **fine-grained** tokens limited to that project's repositories and with an expiry date, instead of `gh auth login`'s broad OAuth token.

On GitHub, turn on **push protection** for the account's repositories, so a pushed secret is blocked server side with nothing to install locally.

### 3.4 AWS with several accounts

Today the owner uses the `default` profile for Secretsy and an `immo` profile. Plan:

- **Drop `default`,** so nothing runs against Secretsy by accident.
- **Prefer IAM Identity Center** where an account can use it (`aws configure sso`): no long-lived key is stored at all. It requires AWS Organizations for account access.
- **Otherwise, keep each access key in the keyring** and read it with `credential_process`, so `~/.aws/credentials` disappears:

  ```bash
  secret-tool store --label='AWS secretsy' service aws-cli profile secretsy
  # paste: {"Version":1,"AccessKeyId":"AKIA...","SecretAccessKey":"..."}
  secret-tool store --label='AWS immo' service aws-cli profile immo
  rm ~/.aws/credentials
  ```

  ```ini
  # ~/.aws/config
  [profile secretsy]
  credential_process = secret-tool lookup service aws-cli profile secretsy
  region = us-east-1

  [profile immo]
  credential_process = secret-tool lookup service aws-cli profile immo
  region = us-east-1

  # Production: a role that requires MFA. The CLI asks for the code and caches temporary credentials.
  [profile secretsy-prod]
  source_profile = secretsy
  role_arn = arn:aws:iam::111111111111:role/Admin
  mfa_serial = arn:aws:iam::111111111111:mfa/yas
  ```

- **Pick the account per project** in the project's `mise.toml`:

  ```toml
  [env]
  AWS_PROFILE = "immo"
  ```

- The root user of each account keeps MFA and no access keys.

### 3.5 SSH keys and commit signing

No unprotected `id_*` files. The agent asks for confirmation each time the key is used:

```bash
ssh-keygen -t ed25519 -C xps16             # with a passphrase
ssh-add -c -t 8h ~/.ssh/id_ed25519         # -c: confirm every use; -t: expire after 8 h
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```

- `-c` also asks before every signed commit. If that becomes tiresome, use a second key only for signing, loaded without `-c`.
- To check on the machine: that an `ssh-agent` is running in the Plasma session (`echo $SSH_AUTH_SOCK`), and that `SSH_ASKPASS` points at `ksshaskpass`. If not, the image can set it in `environment.d` (section 9).
- With a FIDO2 security key, `ssh-keygen -t ed25519-sk -O resident -O verify-required` gives a key that needs a touch, and the same key could cover `sudo` (`pam-u2f`) and LUKS (`systemd-cryptenroll`).
- Never forward the SSH agent into project containers. They use HTTPS with a fine-grained token.

### 3.6 Claude Code on the host

On Linux, Claude Code keeps its login in `~/.claude/.credentials.json` with mode `0600`: file permissions are its only protection. On the host, deny reads of the obvious secrets in `~/.claude/settings.json`:

```json
{"permissions":{"deny":["Read(~/.aws/**)","Read(~/.ssh/**)","Read(~/.config/gh/**)","Read(~/.config/glab-cli/**)","Read(**/.env)","Read(**/.env.*)"]}}
```

These rules do not stop a `cat` through Bash, so they are a seatbelt, not isolation. Day-to-day agent work goes in containers (section 6).

### 3.7 Passwords and two-factor

- One password manager with a long passphrase, and a different password for every site. Which one the owner uses is still open (section 10).
- Passkeys where offered: GitHub, Google, the AWS root user.
- Two-factor on the email account first, since it can reset every other account.
- Recovery codes kept away from the laptop.
- The LUKS passphrase is different from the login password.

---

## 4. Isolation with Incus

### 4.1 What a project container can and cannot reach

An unprivileged container (Incus's default) sees only its own filesystem plus any folder mounted into it. It cannot see the host's `~/.aws`, `~/.ssh`, keyring, processes or graphical session. It still has three ways to reach the host:

1. **The network, today fully open to the host.** `bootc-incus.xml` sets `target="ACCEPT"` on `incusbr0`, so a container reaches **every port on the host**: development servers, databases of other projects, anything bound to `0.0.0.0`. `bootc-laptop` does not apply, since it covers the Wi-Fi. The container probably also reaches the LAN and the tailnet through the host's NAT; untested.
2. **A shared folder is a path back.** With `shift=true`, files the agent writes are owned by the host user. Anything the host later runs from that folder runs the agent's code: `.git/hooks/*`, `mise.toml` tasks, `package.json` scripts, a `Makefile`, Zed tasks, `.envrc`. A symlink to `~/.aws/credentials` leads nowhere inside the container, but a host tool that follows it reads the real file.
3. **The shared kernel.** A kernel bug could allow an escape. `security.nesting=true`, needed for Podman inside, widens that surface a little. An Incus VM (`--vm`) has its own kernel, at the cost of more memory and slower shared folders (virtiofs).

### 4.2 Mitigations

| Risk | Measure |
|---|---|
| Network to the host | Make `bootc-incus` accept only DHCP and DNS from `incusbr0` instead of everything. firewalld and Incus have a history of breaking container internet when the bridge is not trusted, so test that instances still reach the internet |
| Shared folder | Mount only the project's own folder, never `~/src`. Better: clone inside the container and edit through Zed's SSH remote. If mounted, read `git diff`, especially `.git/hooks`, `mise.toml` and `package.json`, before running anything from it on the host, and never `mise trust` an unread change |
| Kernel | Keep containers unprivileged (never `security.privileged=true`). Use `--vm` for the most sensitive work |
| Other bridges | Do not mount the Wayland, PipeWire, `ssh-agent`, `podman.sock` or Incus sockets into a project container |

Check from a test container:

```bash
# On the host: what listens beyond localhost
ss -tlnp | grep -v 127.0.0.1
# In the container: the host is the default gateway
ip route | grep default
curl -s --max-time 2 http://<host-bridge-ip>:<port>
```

---

## 5. The `devbox` image

### 5.1 Design

One golden image, built once and cloned per project. On the btrfs pool, a clone is instant and only stores what differs from the image.

| Package | Why |
|---|---|
| `git`, `openssh-server`, `sudo` | Work on the repo, Zed's SSH remote, install what a project needs |
| `gcc`, `gcc-c++`, `make`, `python3`, `unzip` | Native Node modules (`node-gyp`), cgo, archives that mise downloads |
| `podman`, `podman-docker`, `docker-compose` | `docker compose` for databases and services |
| mise, Claude Code (per user) | Per-project languages and the agent |

- **Base: `images:fedora/45/cloud`**, the same release as the host, with cloud-init. Alpine is smaller, but musl breaks many prebuilt binaries that mise and npm download.
- **Nothing else:** no zsh, Starship or editor. Zed installs its own server over SSH.
- Compilers are a non-goal in `base` (`CLAUDE.md`, section 1), and this is the container that non-goal points to.
- `sudo` without a password gives the agent root **inside** the container, which is unprivileged on the host.
- `security.syscalls.intercept.mknod` and `setxattr` are the usual settings for container engines inside Incus. Check whether Podman needs them.
- Nested rootless Podman needs the container's ID map to cover the inner user's subuid range. `setup.sh` gives Incus `root:1000000:1000000000`, which should be enough. Unverified.

### 5.2 Files

- [`devbox/cloud-init.yaml`](../devbox/cloud-init.yaml): used once, to build the image. Replace the placeholder SSH key.
- [`devbox/profile.yaml`](../devbox/profile.yaml): the `devbox` profile every project container uses, with nesting and resource limits.

### 5.3 Build the image (monthly, or to update it)

```bash
incus profile create devbox < devbox/profile.yaml

incus launch images:fedora/45/cloud devbox-build -p default -p devbox \
  -c cloud-init.user-data="$(cat devbox/cloud-init.yaml)"
incus exec devbox-build -- cloud-init status --wait
# Every clone needs its own identity and SSH host keys
incus exec devbox-build -- sh -c 'cloud-init clean --machine-id && rm -f /etc/ssh/ssh_host_*'
incus stop devbox-build
incus publish devbox-build --alias devbox --reuse
incus delete devbox-build
```

Existing project containers do not follow a new image. Update them in place with `incus exec <name> -- dnf -y upgrade`, or recreate them.

### 5.4 Use it

```bash
incus launch devbox immo -p default -p devbox
incus exec immo -- su - dev
incus snapshot create immo clean          # before letting an agent work
```

So that `ssh dev@immo.incus` works from the host and from Zed, point the host's resolver at the bridge once:

```bash
sudo resolvectl dns incusbr0 "$(incus network get incusbr0 ipv4.address | cut -d/ -f1)"
sudo resolvectl domain incusbr0 '~incus'
```

`resolvectl` settings do not survive a reboot. If this works, make it permanent in the image (section 9).

---

## 6. Claude Code accounts per project

The owner has two Claude Code accounts, each tied to different projects.

**Recommended: one account per container.** Log in inside each project's container, which then holds only that account, that project's fine-grained Git token and that project's AWS profile:

```bash
incus exec immo -- su - dev
claude              # the host's browser shows a code: paste it at "Paste code here if prompted"
claude auth login   # if pasting into the prompt does nothing
```

| Where | Claude Code | GitHub/GitLab | AWS |
|---|---|---|---|
| Container `immo` | Account A | Fine-grained token for IMMO's repos | `immo` only |
| Container for another project | Account B | Token for that project | That account only |
| Host | Owner's account, for `bootc-images` and general work | The owner's full session | None, or read-only |

**On the host, if ever needed:** `CLAUDE_CONFIG_DIR` gives each account its own directory, with its own settings, history and login. Set it in the project's `mise.toml` so it switches with the folder:

```toml
[env]
CLAUDE_CONFIG_DIR = "{{env.HOME}}/.claude-immo"
```

Both credentials then live in the host's home, where any agent on the host can read them. Use it for one-off tasks, not for agents' daily work.

---

## 7. Order of work when the XPS arrives

1. Hardware first (`CLAUDE.md`, roadmap item 1).
2. In the VM: section 8, steps 1 to 3.
3. Repo changes from section 9, one commit each.
4. On the XPS: migrate the real secrets (sections 3.3 to 3.5), create the first project container, and log in to its Claude Code account.

## 8. Test plan

Run in a `mise run vm-up base` VM first, then on the XPS.

1. **KWallet and the CLIs**
   - [ ] `busctl --user status org.freedesktop.secrets | grep -E '^(PID|Comm|Exe)'` names `ksecretd`
   - [ ] `rpm -q kf6-kwallet` is 6.14 or later
   - [ ] `grep -l org.freedesktop.secrets /usr/share/dbus-1/services/*` shows which file activates it
   - [ ] `gh auth status` and `glab auth status` report the keyring, and no token is in their config files
   - [ ] `secret-tool store` / `lookup` round-trips, and `aws sts get-caller-identity --profile <p>` works through `credential_process`
   - [ ] Closing the wallet on idle and on screen lock: find the `kwalletrc` keys, and check what Chrome and `gh` do while it is closed
2. **SSH**
   - [ ] `echo $SSH_AUTH_SOCK $SSH_ASKPASS` in a Plasma session
   - [ ] `ssh-add -c` shows a `ksshaskpass` confirmation on `ssh -T git@github.com` and on a signed commit
3. **Incus and devbox**
   - [ ] Build `devbox` as in section 5.3, and launch a project container from it
   - [ ] Inside: rootless `docker compose up` with a database, as the `dev` user
   - [ ] `ssh dev@<name>.incus` from the host, and Zed's SSH remote
   - [ ] Claude Code login inside the container with the paste-code flow
   - [ ] Network: confirm the container reaches host ports today, then tighten `bootc-incus` and confirm it still reaches the internet but not the host
   - [ ] Whether the container reaches the LAN and the tailnet
   - [ ] The same with `--vm`

## 9. Repo changes to make after validation

Each in its own commit, with a `tests/smoke.sh` check where it makes sense:

- `bootc-incus.xml`: only DHCP and DNS from `incusbr0`, if the tests in section 8 pass.
- `environment.d`: `SSH_ASKPASS=/usr/bin/ksshaskpass`, if the session does not set it already.
- `tests/smoke.sh`: `secret-tool`, `kwallet-query` and `ksshaskpass` exist, so the build fails if upstream drops one.
- A `mise run secrets-audit` task: flags AWS keys in `~/.aws/credentials`, plaintext `gh` or `glab` tokens, private SSH keys without a passphrase, and `.env` files under `~/src`.
- A `mise run devbox <name>` task (and one to rebuild the image) from the files in `devbox/`.
- Permanent `.incus` name resolution on the host, for example a `systemd-networkd` drop-in or a NetworkManager dispatcher script for `incusbr0`.
- `README.md`: the user-facing steps from sections 3 and 5, once tested.

## 10. Open questions for the owner

- Which password manager is used today, and whether its SSH agent should replace `ssh-add -c`.
- Whether a YubiKey or another FIDO2 key is available or worth buying (SSH, `sudo` and LUKS from one key).
- Whether the AWS accounts (Secretsy, IMMO) can use IAM Identity Center.
- Code in project containers: cloned inside, or mounted from the host.

## 11. References

- KWallet and Secret Service: <https://planet.kde.org/marco-martin-2025-04-14-towards-a-transition-from-kwallet-to-secret-service/>, KDE bugs [491280](https://bugs.kde.org/show_bug.cgi?id=491280), [504709](https://bugs.kde.org/show_bug.cgi?id=504709), [504312](https://bugs.kde.org/show_bug.cgi?id=504312), [523878](https://bugs.kde.org/show_bug.cgi?id=523878), [458069](https://bugs.kde.org/show_bug.cgi?id=458069)
- `kf6-kwallet` files: <https://packages.fedoraproject.org/pkgs/kf6-kwallet/kf6-kwallet/>
- `secret-tool` in `libsecret`: <https://packages.fedoraproject.org/pkgs/libsecret/libsecret/>
- KeePassXC Secret Service (the rejected option): <https://github.com/keepassxreboot/keepassxc/blob/develop/docs/topics/SecretService.adoc>
- `glab auth login`: <https://docs.gitlab.com/cli/auth/login>
- Claude Code authentication and multiple accounts: <https://code.claude.com/docs/en/authentication>
- Claude Code login in containers: <https://code.claude.com/docs/en/troubleshoot-install>
- Incus disk devices: <https://linuxcontainers.org/incus/docs/main/reference/devices_disk/>
- Incus images: <https://images.linuxcontainers.org/>
