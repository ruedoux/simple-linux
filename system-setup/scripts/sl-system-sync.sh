#!/usr/bin/env bash
set -euo pipefail

# Standalone sudo command — sources system-wide truth from /etc
# Installed to /usr/local/bin/sl-system-sync during USB setup.
# Re-run to apply changes after editing /etc/simple-linux/settings.env.

source /etc/simple-linux/settings.env
source /etc/simple-linux/lib.sh

sync_pacman() { sudo pacman -Syu --noconfirm; }

enable_multilib() {
  if [[ "$ENABLE_GAMING" != "true" ]]; then
    return 0
  fi

  if grep -q '^\[multilib\]' /etc/pacman.conf; then
    log_ok "[multilib] repository already enabled"
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
    sudo pacman -S --noconfirm --needed mesa
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

  # Create system group for Steam binary access control
  local gaming_group="${GAMING_GROUP:-gaming}"
  sudo groupadd -f "$gaming_group"

  # Restrict Steam binaries to root:$gaming_group (750 — group members only)
  sudo find /usr/bin /usr/lib/steam -maxdepth 3 -type f -executable \
    \( -name 'steam' -o -name 'steam*' -o -path '*/steam/*' \) \
    -exec chown "root:$gaming_group" {} \; -exec chmod 750 {} \; 2>/dev/null || true

  # Pacman hook: re-apply restrictions after every Steam package update
  sudo mkdir -p /etc/pacman.d/hooks
  sudo tee /etc/pacman.d/hooks/steam-permissions.hook > /dev/null <<STEAM_HOOK
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = steam

[Action]
Description = Restricting Steam binaries to ${gaming_group} group...
When = PostTransaction
Exec = /bin/sh -c 'find /usr/bin /usr/lib/steam -maxdepth 3 -type f -executable \( -name steam -o -name steam\\* -o -path \\*/steam/\\* \) -exec chown root:${gaming_group} {} \\; -exec chmod 750 {} \\; 2>/dev/null || true'
STEAM_HOOK
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
    else
      sudo useradd -mG "$groups" "$username"
      sudo chmod 0700 /home/"$username"

      local key="SETUP_PASSWORD_${username}"
      local user_password="${!key:-}"
      if ! set_password_noninteractive "$username" "$user_password"; then
        log_warn "Password for ${username} not provided (SETUP_PASSWORD_${username})"
        log_warn "User created but password must be set manually with: sudo passwd ${username}"
      fi
    fi
  done

  # Ensure all users have their configured groups (handles re-runs where
  # DESKTOP_USERS entries gained new groups since initial install)
  for entry in "${DESKTOP_USERS[@]}"; do
    username="${entry%%:*}"
    groups="${entry#*:}"
    # Validate groups exist before adding — warn on invalid, don't silently skip
    local valid_groups=()
    for grp in ${groups//,/ }; do
      if getent group "$grp" &>/dev/null; then
        valid_groups+=("$grp")
      else
        log_warn "Group '${grp}' does not exist, skipping for ${username}"
      fi
    done
    if [[ ${#valid_groups[@]} -gt 0 ]]; then
      sudo usermod -aG "$(IFS=,; echo "${valid_groups[*]}")" "$username"
    fi
  done

  # Add gaming-capable users to the Steam access group
  local gaming_group="${GAMING_GROUP:-gaming}"
  for username in $GAMING_USERS; do
    if getent group "$gaming_group" &>/dev/null; then
      sudo usermod -aG "$gaming_group" "$username"
    else
      log_warn "Group '${gaming_group}' does not exist, cannot add ${username}"
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
  if [[ -f /etc/conf.d/wireless-regdom ]]; then
    log_ok "Wireless regulatory domain already configured, skipping"
    return 0
  fi
  echo "WIRELESS_REGDOM=\"${WIRELESS_REGDOM}\"" | sudo tee /etc/conf.d/wireless-regdom > /dev/null
  log_ok "Wireless regulatory domain set to '${WIRELESS_REGDOM}'"
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

secure_boot_images_signed() {
  local verify_output
  verify_output=$(sudo sbctl verify 2>&1 || true)
  local unsigned
  unsigned=$(echo "$verify_output" | grep "not signed" | grep -v "vmlinuz" || true)
  [[ -z "$unsigned" ]]
}

secure_boot_check() {
  if ! command -v sbctl &>/dev/null; then
    log_warn "sbctl not installed. Skipping Secure Boot configuration."
    return 0
  fi

  local sb_status
  sb_status=$(sudo sbctl status 2>/dev/null || true)

  # Already fully configured — skip
  if echo "$sb_status" | grep -qi "Setup Mode:.*Disabled" && \
     echo "$sb_status" | grep -qi "Secure Boot:.*Enabled" && \
     secure_boot_images_signed; then
    log_ok "Secure Boot already fully configured, skipping"
    return 0
  fi

  # Setup Mode available — configure now
  if echo "$sb_status" | grep -qi "Setup Mode:.*Enabled"; then
    log_ok "Secure Boot Setup Mode detected, proceeding with configuration"
    run_step setup_keys "generating and enrolling Secure Boot keys"
    run_step sign_all_images "signing all EFI images"
    return 0
  fi

  # Not configurable — warn but don't block the rest of setup
  local verify_output
  verify_output=$(sudo sbctl verify 2>&1 || true)
  log_warn "Secure Boot: cannot configure (Setup Mode disabled, configuration incomplete)."
  log_warn "Enter Setup Mode in UEFI firmware and re-run, or configure manually."
  if echo "$verify_output" | grep -q "not signed"; then
    log_warn "Unsigned images detected — the system may not boot with Secure Boot enabled."
  fi
}

preflight_checks() {
  log_step "Running preflight checks"

  # Refuse to run on live ISO (must be installed system)
  if [[ ! -f /etc/machine-id ]]; then
    log_err "Missing /etc/machine-id — this does not appear to be an installed system."
    log_err "Refusing to run on a live ISO. Boot into the installed system first."
    exit 1
  fi
  log_ok "Installed system confirmed"

  # systemd must be running
  if ! pidof systemd &>/dev/null; then
    log_err "systemd is not running. This script requires systemd."
    exit 1
  fi
  log_ok "systemd running"

  # Network connectivity
  if ! ping -c 2 "${NETWORK_CHECK_HOST}" >/dev/null 2>&1; then
    log_err "No network connectivity. Connect to the internet first."
    exit 1
  fi
  log_ok "Network connectivity confirmed"

  # Pacman lock check
  if [[ -f /var/lib/pacman/db.lck ]]; then
    if ! pgrep -x pacman >/dev/null 2>&1; then
      log_warn "Stale pacman lock found (no pacman process running). Removing."
      sudo rm -f /var/lib/pacman/db.lck
    else
      log_err "Pacman is currently running. Wait for it to finish or terminate it, then re-run."
      exit 1
    fi
  fi
  log_ok "Pacman lock OK"

  # Validate DESKTOP_USERS format — fail early on malformed entries
  for entry in "${DESKTOP_USERS[@]}"; do
    local username="${entry%%:*}"
    if [[ -z "$username" ]] || [[ "$entry" != *:* ]]; then
      log_err "Invalid DESKTOP_USERS entry: '${entry}'. Expected format: 'username:groups'"
      exit 1
    fi
  done
  log_ok "DESKTOP_USERS format validated"

  log_ok "Preflight checks passed"
}

main() {
  trap 'sudo -k 2>/dev/null || true' EXIT INT TERM
  setup_logging
  prime_sudo_cache

  # Pre-flight validation
  run_step preflight_checks "running preflight checks"

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

  # Secure Boot — 3-way check: skip/configure/warn
  secure_boot_check

  cleanup_passwords

  log_step "System setup updated — reboot for all changes to take effect"
}

main
