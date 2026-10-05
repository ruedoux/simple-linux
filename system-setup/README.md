# system-setup — Automated Arch Linux Installation

A fully automated Arch Linux install and configuration system. Takes a bare metal machine (or VM) from Arch ISO boot to a usable Hyprland desktop with full disk encryption, btrfs snapshots, Unified Kernel Images, and Secure Boot signing.

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
| **Notifications** | Persistent reminders via `sl-remind-notifications` — weekly "update" and monthly "btrfs" reminders are derived from timestamp stamps and surfaced as desktop notifications on every login until reset (`sl-system-sync` resets "update", `sl-remind-notifications reset btrfs` resets "btrfs") |
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

Copy the settings you want to change from `settings.default.env` into
`settings.env` and edit them there (otherwise settings will get overwritten on repo updates). The critical settings are:

- `CHECKED` — must be `"true"` for scripts to run (safety gate)
- `DRIVE` — target disk (e.g. `/dev/nvme0n1`, `/dev/sda`)
- `TIMEZONE`, `HOSTNAME`, `ADMIN_USER` — personalize these
- `ENABLE_GAMING` — set to `"true"` to install steam, gamescope, lact, and enable gaming group restrictions (only gaming user has access to steam)
- `ENABLE_DEV_EXTRAS` — set to `"true"` to install container tooling and additional development tools

> See `settings.default.env` for the full list of tunable settings.

### 3. Provide passwords

Passwords are set via environment variables, or prompted during installation if not provided beforehand.

**Phase 1** (run from Arch ISO — `./setup.sh`):
**Phase 2** (after reboot, before running `sudo sl-system-sync`):

### 4. Run (2 invocations)

```bash
# Phase 1: Partition, encrypt, install base system (from Arch ISO)
./setup.sh

# ── Machine reboots into new system, login as admin ──

# Phase 2: Install Hyprland DE, GPU drivers, packages (from installed system)
sudo sl-system-sync
```

> Phase 2 is safe to re-run — all pacman installs use `--needed` and user creation
> skips existing users.

### Updating

`sl-system-sync` is the single command for both updating simple-linux itself and
applying your configuration. On each run it checks `/opt/simple-linux` for new
commits and, if any are available, asks before pulling:

```bash
sudo sl-system-sync             # checks for updates, prompts, then applies config
sudo sl-system-sync --check     # only compare local repo to remote (no changes)
sudo sl-system-sync --accept    # accept everything: auto pull + pacman --noconfirm
sudo sl-system-sync --no-update # skips pacman -Syu
```

When a new version is available you're asked interactively; answering "no" skips
the pull and continues applying your current configuration. `--check` only
compares the local clone against the remote and exits non-zero when an update is
available, so it can be used from cron.

At login, Quickshell runs `sl-remind-notifications check-update`, a read-only check that
notifies you when a new version is available in `/opt/simple-linux`.

#### Overrides (`settings.env`)

`/etc/simple-linux/settings.default.env` is **managed and overwritten on update** — don't
edit it. Put your changes in `/etc/simple-linux/settings.env`, which is
sourced right after `settings.default.env` and never overwritten:

```bash
# /etc/simple-linux/settings.env
ADDITIONAL_PACKAGES="foo bar"      # extra packages installed by sl-system-sync
PACKAGES="${PACKAGES} baz"         # or override any managed variable directly
```

`ADDITIONAL_PACKAGES` is installed by `sl-system-sync` and verified by
`sl-system-health`, so your extra packages survive updates cleanly.

Run `sl-system-health` (read-only) to check disk space, Btrfs scrub status, per-disk S.M.A.R.T. health, package completeness, and dangling packages. It exits non-zero on failures.
