#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
SETUP_SCRIPT_DIR="${SETUP_SCRIPT_DIR:-$(dirname "$SCRIPT_DIR")}"

source "$SETUP_SCRIPT_DIR/settings.env"
source "$SETUP_SCRIPT_DIR/.lib.sh"

verify_checked

sync_pacman() { sudo pacman -Syu --noconfirm; }

enable_multilib() {
  if [[ "$ENABLE_GAMING" != "true" ]]; then
    return 0
  fi

  log_step "Enabling [multilib] repository"
  sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
  log_ok "[multilib] repository enabled"
  sudo pacman -Syu --noconfirm
}

detect_and_install_gpu_drivers() {
  local gpu_vendors drivers=""
  gpu_vendors=$(lspci -mm 2>/dev/null | grep -iE '"(VGA compatible controller|3D controller|Display controller)"' | cut -d '"' -f4 || true)

  if echo "$gpu_vendors" | grep -qi "intel"; then
    drivers="$drivers ${GPU_INTEL_DRIVERS}"
  fi
  if echo "$gpu_vendors" | grep -qiE "amd|advanced micro|ati"; then
    drivers="$drivers ${GPU_AMD_DRIVERS}"
  fi
  if echo "$gpu_vendors" | grep -qi "nvidia"; then
    drivers="$drivers ${GPU_NVIDIA_DRIVERS}"
  fi

  # Install matching lib32 Vulkan driver (resolves Steam's lib32-vulkan-driver dependency)
  if [[ "$ENABLE_GAMING" == "true" ]]; then
    if echo "$gpu_vendors" | grep -qi "nvidia"; then
      drivers="$drivers ${GPU_NVIDIA_LIB32_VULKAN}"
    elif echo "$gpu_vendors" | grep -qiE "amd|advanced micro|ati"; then
      drivers="$drivers ${GPU_AMD_LIB32_VULKAN}"
    elif echo "$gpu_vendors" | grep -qi "intel"; then
      drivers="$drivers ${GPU_INTEL_LIB32_VULKAN}"
    fi
  fi

  if [[ -n "$drivers" ]]; then
    log_ok "Detected GPU(s), installing:${drivers}"
    # shellcheck disable=SC2086
    sudo pacman -S --noconfirm --needed $drivers
  else
    log_warn "No recognized GPU; installing mesa as fallback"
    sudo pacman -S --noconfirm mesa
  fi
}

# shellcheck disable=SC2086
install_hyprland() { sudo pacman -S --noconfirm --needed $HYPRLAND_PACKAGES; }
# shellcheck disable=SC2086
install_packages() { sudo pacman -S --noconfirm --needed $OTHER_PACKAGES; }

install_gaming_packages() {
  if [[ "$ENABLE_GAMING" != "true" ]]; then
    return 0
  fi
  # shellcheck disable=SC2086
  sudo pacman -S --noconfirm --needed $GAMING_PACKAGES
  # shellcheck disable=SC2086
  sudo systemctl enable --now $GAMING_SERVICES

  # Hide gaming .desktop files from non-gaming users
  local entry username user_apps
  for entry in "${DESKTOP_USERS[@]}"; do
    username="${entry%%:*}"
    if [[ " ${GAMING_USERS} " == *" ${username} "* ]]; then
      continue
    fi
    user_apps="/home/${username}/.local/share/applications"
    sudo -u "$username" mkdir -p "$user_apps"
    printf '[Desktop Entry]\nType=Application\nName=Steam\nNoDisplay=true\n' | \
      sudo -u "$username" tee "$user_apps/steam.desktop" > /dev/null
  done
}

install_dev_extras() {
  if [[ "$ENABLE_DEV_EXTRAS" != "true" ]]; then
    return 0
  fi
  # shellcheck disable=SC2086
  sudo pacman -S --noconfirm --needed $DEV_EXTRA_PACKAGES
}

create_desktop_users() {
  local entry username groups
  for entry in "${DESKTOP_USERS[@]}"; do
    username="${entry%%:*}"
    groups="${entry#*:}"

    if id -u "$username" &>/dev/null; then
      log_warn "User '${username}' already exists, skipping creation"
      continue
    fi

    sudo useradd -mG "$groups" "$username"
    sudo chmod 0700 /home/"$username"

    local key="SETUP_PASSWORD_${username}"
    local user_password="${!key:-}"
    if ! set_password_noninteractive "$username" "$user_password"; then
      log_err "Password for ${username} not provided (SETUP_PASSWORD_${username})"
      exit 1
    fi
  done
}

enable_system_services() {
  # shellcheck disable=SC2086
  sudo systemctl enable --now $SYSTEMD_SYSTEM_SERVICES
}

configure_wireless_regdom() {
  if [[ -z "${WIRELESS_REGDOM:-}" ]]; then
    log_warn "WIRELESS_REGDOM not set, skipping wireless regulatory domain configuration"
    return 0
  fi
  echo "WIRELESS_REGDOM=\"${WIRELESS_REGDOM}\"" | sudo tee /etc/conf.d/wireless-regdom > /dev/null
  log_ok "Wireless regulatory domain set to '${WIRELESS_REGDOM}'"
}

verify_secure_boot_mode() {
  if ! sudo sbctl status 2>/dev/null | grep -qi "setup mode.*enabled"; then
    log_err "Secure Boot is NOT in Setup Mode."
    log_err "Enter your BIOS/UEFI firmware, enable Setup Mode, then re-run this script."
    exit 1
  fi
  log_ok "Secure Boot Setup Mode confirmed"
}

setup_keys() {
  sudo sbctl create-keys
  sudo sbctl enroll-keys -m
}

sign_all_images() {
  # Register each UKI with sbctl explicitly — sbctl sign-all does not detect UKIs
  shopt -s nullglob
  local uki_files=(/boot/EFI/Linux/*.efi)
  shopt -u nullglob

  if [[ ${#uki_files[@]} -eq 0 ]]; then
    log_err "No UKI files found in /boot/EFI/Linux/"
    exit 1
  fi

  for uki in "${uki_files[@]}"; do
    log_step "Registering ${uki} with sbctl"
    sudo sbctl sign -s "$uki"
  done

  sudo sbctl sign-all

  # Verify — fatal if anything is still unsigned
  # vmlinuz files are bundled inside UKIs and don't need separate signing
  local verify_output
  verify_output=$(sudo sbctl verify 2>&1 || true)
  local unsigned
  unsigned=$(echo "$verify_output" | grep "not signed" | grep -v "vmlinuz" || true)
  if [[ -n "$unsigned" ]]; then
    log_err "Some EFI images are still unsigned:"
    echo "$unsigned" | while read -r line; do
      log_err "  ${line}"
    done
    exit 1
  fi
  log_ok "All EFI images verified signed"
}

main() {
  trap 'sudo -k 2>/dev/null || true' EXIT INT TERM
  setup_logging
  prime_sudo_cache

  # Desktop environment
  run_step sync_pacman "synchronizing pacman"
  run_step enable_multilib "enabling multilib repository"
  run_step detect_and_install_gpu_drivers "detecting and installing GPU drivers"
  run_step install_gaming_packages "installing gaming packages"
  run_step create_desktop_users "creating desktop users"
  run_step install_hyprland "installing hyprland"
  run_step install_packages "installing packages"
  run_step install_dev_extras "installing development extras"
  run_step enable_system_services "enabling system services"
  run_step configure_wireless_regdom "configuring wireless regulatory domain"

  # Secure Boot
  run_step verify_secure_boot_mode "checking Secure Boot Setup Mode"
  run_step setup_keys "generating and enrolling Secure Boot keys"
  run_step sign_all_images "signing all EFI images"

  cleanup_passwords

  pause_before_reboot "System setup"
}

main
