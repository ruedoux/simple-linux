# system-setup — Automated Arch Linux Installation

A fully automated Arch Linux install & configuration system. Takes a bare-metal machine (or VM) from Arch ISO boot to a ready-to-use Hyprland desktop with full-disk encryption, Btrfs snapshots, Unified Kernel Images, and Secure Boot signing.

## Setup

| Feature | Details |
|---|---|
| **Disk layout** | GPT: 2 GiB EFI + remaining as LUKS2 |
| **Encryption** | LUKS2 on root partition (`/dev/mapper/cryptroot`) |
| **Filesystem** | Btrfs with subvolumes: `@`, `@home`, `@swap`, `@var_log`, `@var_cache_pacman` |
| **Boot** | Unified Kernel Images (UKI) via mkinitcpio, booted directly via UEFI efibootmgr entries |
| **Secure Boot** | Custom keys via `sbctl`, UKI signing, automatic re-sign via sbctl's built-in pacman hook |
| **Snapshots** | `timeshift` installed for Btrfs snapshots (manual configuration required) |
| **Firewall** | `nftables` (default-deny inbound, allow established/loopback/DHCP) |
| **S.M.A.R.T.** | `smartd` enabled with disk-failure alerts written to `/var/lib/simple-linux/alerts` (world-readable) |
| **Notifications** | Persistent reminders via `sl-remind` — weekly "update" and monthly "btrfs" timers write `.alert` files, surfaced as desktop notifications on every login until an admin removes the file |
| **Desktop** | Hyprland, PipeWire audio, Bluetooth |

## Prerequisites

- **UEFI** boot (BIOS/CSM is not supported)
- **Arch Linux ISO** booted (for Phase 1)
- **Secure Boot in Setup Mode** — enable in UEFI firmware before running Phase 2
- **All data backed up** — the target drive will be **completely wiped**
- Network connectivity (Ethernet or pre-configured WiFi)

## Quick Start

### 1. Boot Arch ISO, clone the repo

```bash
git clone <repo-url> /tmp/simple-linux
cd /tmp/simple-linux/system-setup
```

### 2. Configure

Edit `settings.env`. The critical settings are:

- `CHECKED` — must be `"true"` for scripts to run (safety gate)
- `DRIVE` — target disk (e.g. `/dev/nvme0n1`, `/dev/sda`)
- `TIMEZONE`, `HOSTNAME`, `ADMIN_USER` — personalize these
- `ENABLE_GAMING` — set to `"true"` to install Steam, gamescope, lact, and enable gaming group restrictions
- `ENABLE_DEV_EXTRAS` — set to `"true"` to install container tooling (nerdctl, buildkit, rootlesskit), kubectl, QEMU/libvirt/virt-manager, dotnet 9.0 & 10.0 SDKs, yt-dlp, and additional development tools

> See `settings.env` for the full list of tunable settings. Other commonly-edited
> settings include GPU driver variables (`GPU_NVIDIA_DRIVERS`, `GPU_AMD_DRIVERS`,
> `GPU_INTEL_DRIVERS`), `SWAP_SIZE`, `LOCALES`, `KERNELS`, and `WIRELESS_REGDOM`.

### 3. Provide passwords

Passwords are set via environment variables, never stored on disk.

**Phase 1** (run from Arch ISO — `./setup.sh`):

```bash
export SETUP_LUKS_PASSWORD="your-luks-passphrase"
export SETUP_ROOT_PASSWORD=""                               # empty = lock root
export SETUP_PASSWORD_admin="your-admin-password"
```

> The script checks for these three passwords. If any are missing, it prompts
> interactively for all missing ones and proceeds without further interaction.

**Phase 2** (after reboot, before running `sudo sl-system-sync`):

```bash
# Re-export these — they were lost after reboot
export SETUP_PASSWORD_code="your-code-password"
export SETUP_PASSWORD_gaming="your-gaming-password"
```

> The `code` and `gaming` users are created during Phase 2. If passwords are
> not provided, the script prompts for them interactively.

### 4. Run (2 invocations)

```bash
# Phase 1: Partition, encrypt, install base system (from Arch ISO)
./setup.sh

# ── Machine reboots into new system, login as admin ──

# Phase 2: Install Hyprland DE, GPU drivers, packages (from installed system)
sudo sl-system-sync
```

> Phase 2 is safe to re-run — all pacman installs use `--needed` and user creation
> skips existing users. Note: it always runs a full system upgrade (`pacman -Syu`).

### Updating

`sl-system-sync` is the single command for both updating simple-linux itself and
applying your configuration. On each run it checks `/opt/simple-linux` for new
commits and, if any are available, asks before pulling:

```bash
sudo sl-system-sync             # checks for updates, prompts, then applies config
sudo sl-system-sync --check     # only compare local repo to remote (no changes)
sudo sl-system-sync --accept    # accept everything: auto pull + pacman --noconfirm
```

When a new version is available you're asked interactively; answering "no" skips
the pull and continues applying your current configuration. `--check` only
compares the local clone against the remote and exits non-zero when an update is
available, so it can be used from cron.

Pacman is interactive by default (no `--noconfirm`), so you can react to prompts
such as package removals or `.pacnew` config-file questions. Use `--accept` (or
`-y`) for unattended runs.

At login, Quickshell runs `sl-remind check-update`, a read-only check that
notifies you when a new version is available in `/opt/simple-linux`.

#### Local overrides (`settings.local.env`)

`/etc/simple-linux/settings.env` is **managed and overwritten on update** — don't
edit it. Put your changes in `/etc/simple-linux/settings.local.env`, which is
sourced right after `settings.env` and never overwritten:

```bash
# /etc/simple-linux/settings.local.env
ADDITIONAL_PACKAGES="foo bar"      # extra packages installed by sl-system-sync
PACKAGES="${PACKAGES} baz"         # or override any managed variable directly
```

`ADDITIONAL_PACKAGES` is installed by `sl-system-sync` and verified by
`sl-system-health`, so your extra packages survive updates cleanly.

### Skipping the system upgrade

By default `sl-system-sync` runs a full `pacman -Syu` upgrade. To apply your
configuration changes without a full system upgrade, pass `--no-update`:

```bash
sudo sl-system-sync --no-update
```

This skips the `pacman -Syu` upgrade but still installs the configured packages
with `--needed` (and refreshes the package DB when `[multilib]` is first enabled).

> **Caveat:** installing packages without first upgrading the system is a
> *partial upgrade*, which Arch Linux does not support. Use `--no-update` only
> when you want to defer the upgrade and intend to run a full `pacman -Syu` soon.

Run `sl-system-health` (read-only) to check disk space, Btrfs scrub status, per-disk S.M.A.R.T. health, package completeness, and dangling packages. It exits non-zero on failures.
