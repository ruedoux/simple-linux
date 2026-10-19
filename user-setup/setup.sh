#!/usr/bin/env bash

set -euo pipefail

SETUP_SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SETUP_SCRIPT_DIR/.config/simple-linux/.sl-lib.sh"

copy_dots() {
  local src="$SETUP_SCRIPT_DIR/.config"

  # Paths preserved across re-runs, keyed by .config subdir and relative to it.
  # Directories are merged (rsync, no --delete); files are installed once if
  # missing. To protect something new, just add it to this map.
  declare -A preserve=(
    [simple-linux]="config.env bashrc-extension.sh packages/"
    [hypr]="hyprland/user-overrides.lua"
  )

  for subdir in "$src"/*/; do
    local name
    name="$(basename "$subdir")"
    local dest="$HOME/.config/$name"
    mkdir -p "$dest"

    local excludes=()
    local keep=()
    if [ -d "$subdir/files" ]; then
      excludes+=(--exclude=files/)
    fi

    local paths
    local path
    if [[ -n "${preserve[$name]:-}" ]]; then
      read -r -a paths <<< "${preserve[$name]}"
      for path in "${paths[@]}"; do
        excludes+=(--exclude="$path")
        keep+=("$path")
      done
    fi

    rsync -a --delete "${excludes[@]}" "$subdir" "$dest/"

    for path in "${keep[@]}"; do
      if [ -d "$subdir/$path" ]; then
        rsync -a "$subdir/$path/" "$dest/$path/"
      elif [ -f "$subdir/$path" ] && [ ! -f "$dest/$path" ]; then
        mkdir -p "$(dirname "$dest/$path")"
        cp "$subdir/$path" "$dest/$path"
      fi
    done

    # files/ (wallpapers) must merge without overwriting the user's files.
    if [ -d "$subdir/files" ]; then
      rsync -a --ignore-existing "$subdir/files/" "$dest/files/"
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

setup_ssh_config() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  local dest="$HOME/.ssh/config"
  if [ -f "$dest" ] && grep -q "SetEnv TERM" "$dest"; then
    log_ok "SSH config already has TERM override, skipping"
    return 0
  fi

  local block='# simple-linux managed — appended idempotently, never overwritten
Host *
    SetEnv TERM=xterm-256color'
  if [ -f "$dest" ]; then
    log_ok "Appending TERM override to existing SSH config"
    printf '\n%s\n' "$block" >> "$dest"
  else
    printf '%s\n' "$block" > "$dest"
  fi
  chmod 600 "$dest"
  log_ok "Synced SSH config"
}

main() {
  log_start "Starting setup"
  run_step setup_ssh_config "setting up ssh config"
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
