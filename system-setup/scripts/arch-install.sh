#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
SETUP_SCRIPT_DIR="${SETUP_SCRIPT_DIR:-$(dirname "$SCRIPT_DIR")}"
REPO_ROOT="$(dirname "$SETUP_SCRIPT_DIR")"

source "$SETUP_SCRIPT_DIR/settings.env"
source "$SETUP_SCRIPT_DIR/.lib.sh"

verify_checked

if [[ "$DRIVE" == *"<fillin>"* ]]; then
  log_err "DRIVE is not configured in settings.env. Edit it before running."
  exit 1
fi

preflight_checks() {
  log_step "Running preflight checks"

  if [[ ! -d /sys/firmware/efi ]]; then
    log_err "Not booted in UEFI mode. This script requires UEFI."
    exit 1
  fi
  log_ok "UEFI mode confirmed"

  if ! ping -c 2 "${NETWORK_CHECK_HOST}" >/dev/null 2>&1 && ! ping -c 2 archlinux.org >/dev/null 2>&1; then
    log_err "No network connectivity. Connect to the internet first."
    exit 1
  fi
  log_ok "Network connectivity confirmed"

  timedatectl set-ntp true
  log_ok "NTP time sync enabled"

  if ! pacman -Sy --noconfirm archlinux-keyring >/dev/null 2>&1; then
    pacman-key --init
    pacman-key --populate archlinux
  fi
  log_ok "Pacman keyring initialized"

  if [[ ! -b "$DRIVE" ]]; then
    log_err "Drive $DRIVE does not exist or is not a block device."
    exit 1
  fi

  local disk_size_bytes
  disk_size_bytes=$(lsblk -bno SIZE "$DRIVE" | head -1)
  if (( disk_size_bytes < 21474836480 )); then  # 20 GiB
    log_err "Drive $DRIVE is too small (<20 GiB). Found: $(( disk_size_bytes / 1073741824 )) GiB"
    exit 1
  fi
  if (( disk_size_bytes < 53687091200 )); then  # 50 GiB
    log_warn "Drive $DRIVE is under 50 GiB. Btrfs + timeshift + Hyprland may fill the disk quickly."
  fi
  log_ok "Drive $DRIVE is valid ($(( disk_size_bytes / 1073741824 )) GiB)"
}

warn_and_wait() {
  log_step "Target drive: $DRIVE"
  lsblk -o NAME,SIZE,MODEL,TYPE "$DRIVE" 2>/dev/null || log_warn "Could not display drive info"
  echo ""

  log_warn "ALL DATA on $DRIVE will be DESTROYED!"
  echo "Proceeding in 10 seconds... (Ctrl+C to cancel)"
  for i in {10..1}; do
    printf "  %2d\r" "$i"
    sleep 1
  done
  echo ""
  log_ok "Proceeding with drive wipe"
}

partition_disk() {
  wipefs -a "$DRIVE"
  sgdisk --zap-all "$DRIVE"
  sgdisk -n "1:0:+${EFI_SIZE}" -t 1:ef00 "$DRIVE"
  sgdisk -n 2:0:0 -t 2:8309 "$DRIVE"
  partprobe "$DRIVE"
  mkfs.fat -F32 "$EFI_PART"
}

setup_luks_partition() {
  local luks_pass="${SETUP_LUKS_PASSWORD:-}"
  if [[ -z "$luks_pass" ]]; then
    log_err "SETUP_LUKS_PASSWORD is not set"
    exit 1
  fi
  printf '%s' "$luks_pass" | cryptsetup luksFormat --type luks2 --key-file=- "$LUKS_PART"
  printf '%s' "$luks_pass" | cryptsetup open --key-file=- "$LUKS_PART" cryptroot
  log_ok "LUKS partition set up"
}

setup_btrfs_subvolumes() {
  mkfs.btrfs /dev/mapper/cryptroot
  mount /dev/mapper/cryptroot /mnt
  for subvol in @ @home @swap @var_log @var_cache_pacman; do
      btrfs subvolume create "/mnt/${subvol}"
  done
  umount /mnt

  BTRFS_OPTS="rw,relatime,compress=${BTRFS_COMPRESSION},space_cache=v2"
  mount -o "${BTRFS_OPTS},subvol=@" /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/{home,swap,var/log,var/cache/pacman/pkg,boot}
  mount -o "${BTRFS_OPTS},subvol=@home" /dev/mapper/cryptroot /mnt/home
  mount -o "rw,relatime,space_cache=v2,nodatacow,subvol=@swap" /dev/mapper/cryptroot /mnt/swap
  mount -o "${BTRFS_OPTS},subvol=@var_log" /dev/mapper/cryptroot /mnt/var/log
  mount -o "${BTRFS_OPTS},subvol=@var_cache_pacman" /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
  mount -o "umask=0077" "$EFI_PART" /mnt/boot
}

detect_microcode_package() {
  local vendor
  vendor="$(grep -m1 -o 'GenuineIntel\|AuthenticAMD' /proc/cpuinfo || true)"
  case "$vendor" in
    GenuineIntel) echo "intel-ucode" ;;
    AuthenticAMD) echo "amd-ucode" ;;
    *)
      log_warn "Could not detect CPU vendor, skipping microcode package"
      echo ""
      ;;
  esac
}

setup_chroot_env() {
  local ucode_pkg
  ucode_pkg="$(detect_microcode_package)"

  btrfs filesystem mkswapfile --size "$SWAP_SIZE" /mnt/swap/swapfile
  if [[ ! -f /mnt/swap/swapfile ]]; then
    log_err "Swapfile creation failed — /mnt/swap/swapfile does not exist"
    exit 1
  fi
  swapon /mnt/swap/swapfile
  # shellcheck disable=SC2086
  pacstrap -K /mnt $PACKAGES $ucode_pkg
  genfstab -U /mnt >> /mnt/etc/fstab

  # Make /boot unmounted after boot — mounted on-demand via systemd automount
  # Also disable fsck on ESP (vfat can trip unnecessarily, btrfs handles integrity)
  sed -i -e '/\/boot/s/rw,/noauto,x-systemd.automount,nofail,rw,/' \
         -e '/\/boot/s/[[:space:]][0-9]$/ 0/' /mnt/etc/fstab
}

setup_kernel_settings() {
  sed -i 's/^HOOKS=.*/HOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems)/' /mnt/etc/mkinitcpio.conf
  # Btrfs does self-healing at mount time — no fsck needed in initramfs
  sed -i 's/^BINARIES=.*/BINARIES=()/' /mnt/etc/mkinitcpio.conf

  local luks_uuid
  luks_uuid=$(blkid -s UUID -o value "$LUKS_PART")
  mkdir -p /mnt/etc/cmdline.d
  cat > /mnt/etc/cmdline.d/root.conf <<EOF
rd.luks.name=${luks_uuid}=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=/@ rw quiet
EOF

  parse_kernels
  for i in "${!KERNEL_LIST[@]}"; do
    KERNEL="${KERNEL_LIST[$i]}"
    cat > "/mnt/etc/mkinitcpio.d/${KERNEL}.preset" <<EOF
ALL_kver="/boot/vmlinuz-${KERNEL}"
PRESETS=('default')
default_uki="/boot/EFI/Linux/arch-${KERNEL}.efi"
default_options="--cmdline=/etc/cmdline.d/root.conf --splash=/usr/share/systemd/bootctl/splash-arch.bmp"
EOF
  done
}

setup_nftables_config() {
  cat > "/mnt/etc/nftables.conf" << 'EOF'
#!/usr/bin/nft -f

flush ruleset

table inet filter {
  chain input {
    type filter hook input priority filter
    policy drop

    ct state invalid drop comment  "early drop of invalid connections"
    ct state {established, related} accept comment "allow tracked connections"

    iifname lo accept comment "allow from loopback"

    udp dport 68 accept comment "allow DHCP client lease renewal"

    drop
  }

  chain forward {
    type filter hook forward priority filter 
    policy drop

    ct state invalid drop comment  "early drop of invalid connections"
    ct state {established, related} accept comment "allow tracked connections"

    drop
  }
}

EOF
}

run_chroot_script() {
  cp "$SETUP_SCRIPT_DIR/settings.env" /mnt/root/settings.env
  cp "$SETUP_SCRIPT_DIR/.lib.sh" /mnt/root/.lib.sh
  cp "$SCRIPT_DIR/chroot.sh" /mnt/root/chroot.sh
  chmod +x /mnt/root/chroot.sh

  arch-chroot /mnt /root/chroot.sh
  rm /mnt/root/chroot.sh /mnt/root/settings.env /mnt/root/.lib.sh
}

copy_repository() {
  mkdir -p "/mnt${SYSTEM_WIDE_DEST}"
  cp -r "$REPO_ROOT/." "/mnt${SYSTEM_WIDE_DEST}"
  chown -R root:root "/mnt${SYSTEM_WIDE_DEST}"
}

install_system_files() {
  "$SETUP_SCRIPT_DIR/install-scripts.sh" /mnt
  log_ok "System files installed: /etc/simple-linux/ + /usr/local/bin/sl-system-*"
}

finish_setup() {
  log_step "Unmounting filesystems"
  swapoff /mnt/swap/swapfile
  umount -R /mnt
  log_ok "Filesystems unmounted"
}

cleanup_on_error() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    log_err "Installation failed with exit code ${exit_code}"
    log_step "Attempting cleanup..."
    swapoff /mnt/swap/swapfile 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    if cryptsetup status cryptroot &>/dev/null; then
      cryptsetup close cryptroot 2>/dev/null || true
    fi
    log_ok "Cleanup complete (system may be in an inconsistent state)"
  fi
}

main() {
  trap cleanup_on_error ERR
  setup_logging
  run_step preflight_checks "running preflight checks"
  run_step warn_and_wait "drive destruction warning"
  run_step partition_disk "partitioning disk"
  run_step setup_luks_partition "setting up LUKS partition"
  run_step setup_btrfs_subvolumes "setting up btrfs subvolumes"
  run_step setup_chroot_env "setting up chroot environment"
  run_step setup_kernel_settings "setting up kernel settings"
  run_step setup_nftables_config "setting up nftables"
  run_step run_chroot_script "running chroot script"
  run_step copy_repository "copying repository to /opt"
  run_step install_system_files "installing system files to /etc and /usr/local/bin"
  run_step finish_setup "finishing setup"
  cleanup_passwords
  pause_before_reboot "Initial installation"
}

main
