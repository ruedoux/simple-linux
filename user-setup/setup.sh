#!/usr/bin/env bash

set -euo pipefail

SETUP_SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SETUP_SCRIPT_DIR/.config/simple-linux/.sl-lib.sh"

copy_dots() {
  local src="$SETUP_SCRIPT_DIR/.config"
  for subdir in "$src"/*/; do
    local name
    name="$(basename "$subdir")"
    local dest="$HOME/.config/$name"
    mkdir -p "$dest"

    local preserve_args=()
    if [ -d "$subdir/files" ]; then
      preserve_args+=(--exclude=files/)
    fi
    if [ -f "$subdir/config.env" ]; then
      preserve_args+=(--exclude=config.env)
    fi
    if [[ "$name" == "simple-linux" ]]; then
      preserve_args+=(--exclude=bashrc-extension.sh)
    fi

    rsync -a --delete "${preserve_args[@]}" "$subdir" "$dest/"

    if [ -d "$subdir/files" ]; then
      rsync -a --ignore-existing "$subdir/files/" "$dest/files/"
    fi
    if [ -f "$subdir/config.env" ] && [ ! -f "$dest/config.env" ]; then
      cp "$subdir/config.env" "$dest/config.env"
    fi
    log_ok "Synced .config/$name"
  done

  # Copy top-level files (e.g. user-dirs.dirs) that aren't inside subdirectories
  for file in "$src"/*; do
    [ -f "$file" ] || continue
    local fname
    fname="$(basename "$file")"
    cp "$file" "$HOME/.config/$fname"
    log_ok "Synced .config/$fname"
  done
}

start_user_services() {
  local services=(pipewire pipewire-pulse wireplumber hyprsunset)
  for service in "${services[@]}"; do
    if systemctl --user cat "$service" &>/dev/null; then
      systemctl --user enable --now "$service"
    else
      log_warn "User service '$service' not found, skipping."
    fi
  done
}

setup_hyprland_autostart() {
  if ! grep -q "start-hyprland" "${HOME}/.bash_profile" 2>/dev/null; then
    cat >> "${HOME}/.bash_profile" << 'EOF'

if [ -z "$WAYLAND_DISPLAY" ] && [[ -n "$XDG_VTNR" && "$XDG_VTNR" -eq 1 ]]; then
  start-hyprland
fi
EOF
  fi

  mkdir -p "${HOME}/.config/systemd/user"
  cat > "${HOME}/.config/systemd/user/hyprland-session.target" << 'EOF'
[Unit]
Description=Hyprland session
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
PropagatesStopTo=graphical-session.target
EOF
}

main() {
  log_start "Starting setup"
  run_step copy_dots "copying dots"
  run_step start_user_services "starting user services"
  run_step setup_hyprland_autostart "setting up hyprland autostart"
  . "$HOME/.config/simple-linux/sl-controller.sh" reload-all
  log_success "Setup finished"
}

case $(whoami) in
  root)log_err -e "[$0]: This script is NOT to be executed with sudo or as root. Aborting..."; exit 1;;
esac

main "$@"
