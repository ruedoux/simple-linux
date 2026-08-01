#!/usr/bin/env bash
set -euo pipefail

source /root/settings.env
source /root/.lib.sh

setup_locale() {
  ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  hwclock --systohc
  for locale in $LOCALES; do
    if ! grep -q "^#\?${locale}" /etc/locale.gen; then
      log_err "Locale '${locale}' not found in /etc/locale.gen"
      exit 1
    fi
  done
  for locale in $LOCALES; do
      sed -i "s/^#${locale}/${locale}/" /etc/locale.gen
  done
  locale-gen
  echo "LANG=${LANG}" > /etc/locale.conf
  echo "$HOSTNAME" > /etc/hostname
}

enable_network_services() {
  # shellcheck disable=SC2086
  systemctl enable $SYSTEMD_CHROOT_SERVICES
}

create_admin_user() {
  useradd -mG wheel "$ADMIN_USER"
  chmod 0700 /home/"$ADMIN_USER"

  local key="SETUP_PASSWORD_${ADMIN_USER}"
  local admin_password="${!key:-}"
  if ! set_password_noninteractive "$ADMIN_USER" "$admin_password"; then
    log_err "Password for ${ADMIN_USER} not provided (SETUP_PASSWORD_${ADMIN_USER})"
    exit 1
  fi

  local root_pass="${SETUP_ROOT_PASSWORD:-}"
  if [[ -n "$root_pass" ]]; then
    set_password_noninteractive "root" "$root_pass"
  else
    log_step "Locking root account (SETUP_ROOT_PASSWORD not set)"
    passwd -l root
  fi

  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
  visudo -c || { log_err "sudoers syntax check failed"; exit 1; }
}


setup_uki() {
  mkdir -p /boot/EFI/Linux

  for kernel in "${KERNEL_LIST[@]}"; do
    mkinitcpio -p "$kernel"
  done
}

setup_efi_boot_entries() {
  PART_NUM=$(lsblk -no PARTN "$EFI_PART")
  for i in "${!KERNEL_LIST[@]}"; do
    KERNEL="${KERNEL_LIST[$i]}"
    LABEL="${LABEL_LIST[$i]}"
    LOADER="/EFI/Linux/arch-${KERNEL}.efi"

    # Remove any existing boot entry with the same label (stale or prior install).
    # This makes the function idempotent and eliminates duplicate label warnings.
    if efibootmgr 2>/dev/null | grep -qF "${LABEL}"; then
      log_step "Removing existing boot entry: ${LABEL}"
      efibootmgr --delete --label "${LABEL}" 2>/dev/null || :
    fi

    efibootmgr --create --disk "$DRIVE" --part "$PART_NUM" \
      --label "$LABEL" --loader "$LOADER"
  done
}

seed_esp_random() {
  bootctl random-seed
}

main() {
  setup_logging
  trap 'log_err "Chroot setup failed with exit code ${?}"' ERR
  run_step setup_locale "setting up locale"
  run_step enable_network_services "enabling network services"
  run_step create_admin_user "creating admin user"
  parse_kernels
  run_step setup_uki "setting up UKI"
  run_step seed_esp_random "seeding random seed on ESP"
  run_step setup_efi_boot_entries "setting up efi boot entries"
}

main
