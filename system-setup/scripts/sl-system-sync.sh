#!/usr/bin/env bash
set -euo pipefail

source /etc/simple-linux/settings.default.env
source /etc/simple-linux/lib.sh
[ -f /etc/simple-linux/settings.env ] && source /etc/simple-linux/settings.env

NO_UPDATE=0
ACCEPT=0
CHECK_ONLY=0
REPO="${SYSTEM_WIDE_DEST:-/opt/simple-linux}"
PACMAN_CONFIRM=""

usage() {
  echo "Usage: sl-system-sync [--accept] [--no-update] [--check]"
  echo ""
  echo "  --accept, -y     Accept all prompts: auto git pull + pacman --noconfirm."
  echo "  --no-update, -n  Skip the full system upgrade (pacman -Syu)."
  echo "                   Configured packages are still installed (--needed)."
  echo "  --check, -c      Fetch and compare only; make no changes."
  echo "                   Exits 0 when up to date, 1 when an update is available."
  echo "  -h, --help       Show this help."
}

local_commit()  { git -C "$REPO" rev-parse HEAD; }
remote_commit() { git -C "$REPO" rev-parse '@{u}'; }

update_available() {
  [ "$(local_commit)" != "$(remote_commit)" ]
}

do_check() {
  if [ ! -d "$REPO/.git" ]; then
    log_err "$REPO is not a git repository — cannot check for updates"
    exit 1
  fi

  log_step "Fetching remote state"
  git -C "$REPO" fetch --quiet origin

  if update_available; then
    log_warn "Update available: $(local_commit) -> $(remote_commit)"
    return 1
  fi

  log_ok "Up to date ($(local_commit))"
  return 0
}

sync_simple_linux_repo() {
  if [ ! -d "$REPO/.git" ]; then
    log_warn "$REPO is not a git repository — skipping simple-linux update check"
    return 0
  fi

  do_check || true

  if ! update_available; then
    log_ok "Already up to date — nothing to do."
    return 0
  fi

  if [ "$ACCEPT" -eq 1 ]; then
    log_step "Pulling latest changes (--accept)"
  elif [[ ! -t 0 ]]; then
    log_warn "Not a TTY and --accept not given — skipping simple-linux update"
    return 0
  else
    log_step "New version available: $(local_commit) -> $(remote_commit)"
    local answer
    read -rp "  Update simple-linux now? [y/N] " answer
    case "$answer" in
      y|Y|yes|Yes|YES) ;;
      *)
        log_warn "Skipping simple-linux update; continuing with current version"
        return 0
        ;;
    esac
  fi

  log_step "Pulling latest changes"
  if ! git -C "$REPO" pull --ff-only --quiet; then
    log_err "git pull --ff-only failed. The local repo may have modifications."
    log_err "Inspect $REPO and resolve, or run: sudo git -C $REPO reset --hard origin/main"
    exit 1
  fi
  log_ok "Repository updated to $(local_commit)"

  run_step "$REPO/system-setup/install-scripts.sh" "installing updated system files"
}

sync_pacman() {
  if [[ "$NO_UPDATE" -eq 1 ]]; then
    log_warn "Skipping full system upgrade (--no-update)"
    return 0
  fi
  sudo pacman -Syu $PACMAN_CONFIRM
}

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
  if [[ "$NO_UPDATE" -eq 1 ]]; then
    # Refresh-only: the new [multilib] DB is required for the --needed installs
    # that follow, but we skip the full upgrade per --no-update.
    log_warn "Refreshing package DB without upgrade (--no-update)"
    sudo pacman -Sy $PACMAN_CONFIRM
  else
    sudo pacman -Syu $PACMAN_CONFIRM
  fi
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
    sudo pacman -S $PACMAN_CONFIRM --needed $drivers
  else
    log_warn "No recognized GPU; installing mesa as fallback"
    sudo pacman -S $PACMAN_CONFIRM --needed mesa
  fi
}

install_pkg_list() {
  local var_name="$1"
  local pkgs="${!var_name:-}"
  [[ -z "$pkgs" ]] && return 0
  # shellcheck disable=SC2086
  sudo pacman -S $PACMAN_CONFIRM --needed $pkgs
}

install_hyprland() { install_pkg_list HYPRLAND_PACKAGES; }
install_packages() { install_pkg_list OTHER_PACKAGES; }
install_additional_packages() { install_pkg_list ADDITIONAL_PACKAGES; }

install_gaming_packages() {
  if [[ "$ENABLE_GAMING" != "true" ]]; then
    return 0
  fi
  install_pkg_list GAMING_PACKAGES
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
  [[ "$ENABLE_DEV_EXTRAS" != "true" ]] && return 0
  install_pkg_list DEV_EXTRA_PACKAGES
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

    # Ensure the user has all configured groups (handles re-runs where
    # DESKTOP_USERS entries gained new groups since initial install)
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

mask_tpm_nvpcr_services() {
  # Workaround for upstream systemd bug #43848: systemd 262 now requires NvPCR
  # definitions + a signed PCR policy to be embedded in the UKI (ukify
  # --sign-initrd-pcrs). UKIs are built with mkinitcpio, so these units fail
  # on every boot ("Failed to initialize NvPCR index: No such file or directory").
  # Project doesn't use NvPCR measurement — mask the units until fixed upstream.
  sudo systemctl mask systemd-tpm2-setup-early.service systemd-pcrproduct.service systemd-pcrlogin@.service
  sudo systemctl reset-failed systemd-tpm2-setup-early.service \
    systemd-pcrproduct.service \
    systemd-pcrlogin@.service 2>/dev/null || true
}

setup_smartd() {
  if ! command -v smartd &>/dev/null; then
    log_warn "smartd not installed, skipping S.M.A.R.T. monitoring configuration"
    return 0
  fi

  local smartd_conf="/etc/smartd.conf"
  local exec_line="DEVICESCAN -m <nomailer> -M exec /usr/local/bin/sl-remind-notifications smartd"

  if [ -f "$smartd_conf" ] && grep -qF "$exec_line" "$smartd_conf"; then
    log_ok "smartd.conf already configured, skipping"
  else
    sudo tee "$smartd_conf" > /dev/null <<SMARTD_CONF
# simple-linux managed — S.M.A.R.T. monitoring, alerts written to ${NOTIFY_ALERTS_DIR:-/var/lib/simple-linux/alerts}
${exec_line}
SMARTD_CONF
    log_ok "smartd.conf configured"
  fi

  sudo systemctl enable --now smartd
  log_ok "smartd service enabled"
}

reset_reminder_stamps() {
  local alerts_dir="${NOTIFY_ALERTS_DIR:-/var/lib/simple-linux/alerts}"

  # The update was just applied — silence the "system update" reminder.
  /usr/local/bin/sl-remind-notifications reset update

  # Seed the btrfs stamp on first run so the monthly scrub countdown starts.
  if [ ! -f "$alerts_dir/btrfs.stamp" ]; then
    /usr/local/bin/sl-remind-notifications reset btrfs
  fi

  log_ok "reminder stamps updated"
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

unsigned_images() {
  local verify_output
  verify_output=$(sudo sbctl verify 2>&1 || true)
  # vmlinuz files are bundled inside UKIs and don't need separate signing
  echo "$verify_output" | grep "not signed" | grep -v "vmlinuz" || true
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
  local unsigned
  unsigned=$(unsigned_images)
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
  [[ -z "$(unsigned_images)" ]]
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
  log_warn "Secure Boot: cannot configure (Setup Mode disabled, configuration incomplete)."
  log_warn "Enter Setup Mode in UEFI firmware and re-run, or configure manually."
  if [[ -n "$(unsigned_images)" ]]; then
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
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --accept|-y)
        ACCEPT=1
        PACMAN_CONFIRM="--noconfirm"
        shift
        ;;
      --no-update|-n)
        NO_UPDATE=1
        shift
        ;;
      --check|-c)
        CHECK_ONLY=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_err "Unknown option: $1"
        usage >&2
        exit 1
        ;;
    esac
  done

  trap 'sudo -k 2>/dev/null || true' EXIT INT TERM
  setup_logging

  if [ "$CHECK_ONLY" -eq 1 ]; then
    if do_check; then
      exit 0
    else
      exit 1
    fi
  fi

  prime_sudo_cache

  # Pre-flight validation
  run_step preflight_checks "running preflight checks"

  # Update simple-linux itself (git pull) before applying config
  run_step sync_simple_linux_repo "checking for simple-linux updates"

  # Desktop environment
  run_step sync_pacman "synchronizing pacman"
  run_step enable_multilib "enabling multilib repository"
  run_step detect_and_install_gpu_drivers "detecting and installing GPU drivers"
  run_step install_gaming_packages "installing gaming packages"
  run_step create_desktop_users "creating desktop users"
  run_step install_hyprland "installing hyprland"
  run_step install_packages "installing packages"
  run_step install_dev_extras "installing development extras"
  run_step install_additional_packages "installing additional packages"
  run_step enable_system_services "enabling system services"
  run_step mask_tpm_nvpcr_services "masking TPM NvPCR services (upstream systemd#43848 workaround)"
  run_step setup_smartd "configuring S.M.A.R.T. monitoring (smartd)"
  run_step configure_wireless_regdom "configuring wireless regulatory domain"
  run_step reset_reminder_stamps "resetting reminder stamps"

  # Secure Boot — 3-way check: skip/configure/warn
  secure_boot_check

  cleanup_passwords

  log_step "System setup updated — reboot for all changes to take effect"
}

main "$@"
