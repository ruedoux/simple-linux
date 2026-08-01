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
> To update system files after a git pull in /opt/simple-linux, run `sudo /opt/simple-linux/system-setup/install-scripts.sh`
> first, then `sudo sl-system-sync` to apply changes.
