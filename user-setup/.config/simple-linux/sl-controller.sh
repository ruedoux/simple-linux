#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
export SL_ROOT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
export SL_TEMPLATE_DIR="$SL_ROOT_DIR/templates"
export SL_TEMPLATES_JSON="$SL_TEMPLATE_DIR/templates.json"
export SL_WALLPAPERS_DIR="$SL_ROOT_DIR/files/wallpapers"
export SL_WALLPAPER_SELECTED_FILE="$SL_WALLPAPERS_DIR/.selected"
export SL_CONFIG_PATH="$SL_ROOT_DIR/config.env"
export WALLPAPER_DEST_PATH="$SL_ROOT_DIR/files/wallpaper.png"
export SL_LOG_FILE="${SL_LOG_FILE:-$SL_ROOT_DIR/sl-controller.log}"
source "$SL_ROOT_DIR/.sl-lib.sh"
set -a; source "$SL_CONFIG_PATH"; set +a;

# If not running in a terminal (e.g. via nohup or triggered by another process),
# redirect all output to log file to prevent nohup.out pollution
if [[ ! -t 1 ]]; then
  exec >> "$SL_LOG_FILE" 2>&1
fi

_reload_program() {
  local process="$1"
  local command="${2:-$1}"

  log_start "Started reloading '$command'"
  if pgrep -x "$process" >/dev/null; then
    pkill "$process"

    for _ in {1..50}; do
      if ! pgrep -x "$process" >/dev/null; then
        break
      fi
      sleep 0.1
    done

    if pgrep -x "$process" >/dev/null; then
      pkill -9 "$process"
    fi
  fi

  nohup $command >/dev/null 2>&1 &
  log_success "Finished reloading '$command'"
}

_render_templates() {
  local filter="${1:-.}"

  local sl_vars
  sl_vars="$(compgen -A variable | grep '^SL_' | sed 's/^/${/;s/$/}/' | tr '\n' ' ')"

  local src dest
  while IFS=$'\t' read -r src dest; do
    [ -z "$src" ] && continue

    src="$(echo "$src" | envsubst)"
    dest="$(echo "$dest" | envsubst)"
    if [ ! -f "$src" ]; then
      log_warn "template not found: $src"
      continue
    fi

    mkdir -p "$(dirname "$dest")"
    envsubst "$sl_vars" < "$src" > "$dest"
    log_ok "Exported: $src -> $dest"
  done < <(jq -r --arg filter "$filter" 'to_entries[] | select(.key | test($filter)) | "\(.key)\t\(.value)"' "$SL_TEMPLATES_JSON")
}

_wallpapers_next_index() {
  mkdir -p "$SL_WALLPAPERS_DIR"

  local used=()
  local f base
  for f in "$SL_WALLPAPERS_DIR"/wallpaper-*.*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    if [[ "$base" =~ ^wallpaper-([0-9]+)\.[^.]+$ ]]; then
      used+=("${BASH_REMATCH[1]}")
    fi
  done

  local idx=0
  while [[ " ${used[*]:-} " == *" $idx "* ]]; do
    idx=$((idx + 1))
  done
  echo "$idx"
}

_wallpapers_resolve() {
  local src="$1"

  if [ ! -f "$src" ]; then
    log_err "Error: File '$src' not found." >&2
    return 1
  fi

  mkdir -p "$SL_WALLPAPERS_DIR"

  local resolved_src wallpapers_dir_real
  resolved_src="$(realpath "$src")"
  wallpapers_dir_real="$(realpath "$SL_WALLPAPERS_DIR")"

  if [[ "$resolved_src" == "$wallpapers_dir_real"/* ]]; then
    local existing="$(basename "$resolved_src")"
    if [[ "$existing" =~ ^wallpaper-[0-9]+\.[^.]+$ ]]; then
      echo "$existing"
      return 0
    fi
  fi

  local ext="${src##*.}"
  [[ "$ext" == "$src" ]] && ext="png"

  local idx dest_name
  idx="$(_wallpapers_next_index)"
  dest_name="wallpaper-${idx}.${ext}"

  cp -f "$src" "$SL_WALLPAPERS_DIR/$dest_name"
  echo "$dest_name"
}

_run_matugen() {
  matugen image "$WALLPAPER_DEST_PATH" --verbose --prefer saturation --mode "$SL_THEME_MODE";
}

_modify_config() {
  local variable="$1"
  local value="$2"

  if [[ -z "$variable" || -z "$value" ]]; then
    log_err "variable and value is required"
    return 1
  fi

  if grep -q "^${variable}=" "$SL_CONFIG_PATH"; then
    sed -i.bak "s|^${variable}=.*|${variable}=${value}|" "$SL_CONFIG_PATH"
    rm -f "${SL_CONFIG_PATH}.bak"
  else
    echo "Variable '$variable' does not exist in file '$SL_CONFIG_PATH'"
    return 1
  fi
}

switch_theme_mode() {
  case "$SL_THEME_MODE" in
    light)
      _modify_config "SL_THEME_MODE" "dark"
      export SL_THEME_MODE="dark"
      ;;
    dark)
      _modify_config "SL_THEME_MODE" "light"
      export SL_THEME_MODE="light"
      ;;
  esac

  update_themes
}

update_packages() {
  for pkg in "$SL_ROOT_DIR/packages/"*; do
    [ -e "$pkg" ] || continue
    local package_name="$(basename "$pkg")"
    "$SL_ROOT_DIR/sl-install-package.sh" install "$SL_ROOT_DIR/packages/$package_name"
  done
}

update_bashrc() {
  rsync -a --backup --suffix=".bck" "$SL_ROOT_DIR/.bashrc" "$HOME/.bashrc"
}

update_yazi_desktop() {
  mkdir -p "$HOME/.local/share/applications"
  cat > "$HOME/.local/share/applications/yazi.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Yazi File Manager
Exec=${SL_TERMINAL:-kitty} --class yazi -e yazi %U
Terminal=false
Categories=System;FileTools;FileManager;
MimeType=inode/directory;
NoDisplay=true
EOF
  update-desktop-database "$HOME/.local/share/applications/"
}

update_monitors() {
  source "$SL_ROOT_DIR/.sl-monitors-resolve.sh"
  monitors_resolve
  _render_templates "hyprland/(monitors|workspaces|hyprpaper)"
}

update_themes() {
  source "$SL_ROOT_DIR/.sl-monitors-resolve.sh"
  local color_scheme="prefer-$SL_THEME_MODE"
  local gtk_theme="adw-gtk3-$SL_THEME_MODE"

  export SL_MAIN_MONITOR="${SL_MAIN_MONITOR:-$(_get_biggest_monitor)}"
  export SL_QT_THEME="$(
    case "$SL_THEME_MODE" in
      dark)  printf '%s' "$SL_QT_DARK_THEME" ;;
      light) printf '%s' "$SL_QT_LIGHT_THEME" ;;
    esac
  )"

  export SL_FONT_SIZE_SCALED=$((SL_FONT_SIZE * SL_UI_SCALE))
  gtk-update-icon-cache -f "$HOME/.local/share/icons/$SL_ICON_THEME"
  gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
  gsettings set org.gnome.desktop.wm.preferences theme "$gtk_theme"
  gsettings set org.gnome.desktop.interface color-scheme "$color_scheme"
  gsettings set org.gnome.desktop.interface cursor-theme "$SL_HYPRCURSOR_THEME"
  gsettings set org.gnome.desktop.interface icon-theme "$SL_ICON_THEME"
  gsettings set org.gnome.desktop.interface text-scaling-factor "$SL_UI_SCALE"
  gsettings set org.gnome.desktop.interface font-name "$SL_FONT $SL_FONT_SIZE"

  _render_templates "^(?!hyprland/(monitors|workspaces|hyprpaper))"
  _run_matugen
  _reload_program qs
}

remove_wallpaper() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--name)
        name="$2"
        shift 2
        ;;
      -*)
        echo "Unknown option: $1"
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [ -z "$name" ]; then
    log_err "--name is required." >&2
    return 1
  fi

  if [ "$(cat "$SL_WALLPAPER_SELECTED_FILE")" == "$name" ]; then
    log_err "cannot delete current wallpaper"
    return 1
  fi

  rm -f "$SL_WALLPAPERS_DIR/$name"
}

update_wallpaper() {
  local WALLPAPER_BLURRED_DEST_PATH="$SL_ROOT_DIR/files/wallpaper-blurred.png"

  local wallpaper_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--path)
        wallpaper_override="$2"
        shift 2
        ;;
      -*)
        echo "Unknown option: $1"
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  local wallpaper_name=""
  if [ -n "${wallpaper_override:-}" ]; then
    wallpaper_name="$(_wallpapers_resolve "$wallpaper_override")" || return 1
    echo -n "$wallpaper_name" > "$SL_WALLPAPER_SELECTED_FILE";
  elif [ ! -f "$WALLPAPER_DEST_PATH" ] && [ -f "$SL_WALLPAPER_SELECTED_FILE" ]; then
    wallpaper_name="$(cat "$SL_WALLPAPER_SELECTED_FILE")"
  fi

  if [ -n "$wallpaper_name" ] && [ -f "$SL_WALLPAPERS_DIR/$wallpaper_name" ]; then
    rsync -a --delete "$SL_WALLPAPERS_DIR/$wallpaper_name" "$WALLPAPER_DEST_PATH"
  fi

  magick "$WALLPAPER_DEST_PATH" -scale 10% -blur 0x2.5 -scale 1000% "$WALLPAPER_BLURRED_DEST_PATH"
  _reload_program hyprpaper
}

update_python() {
  pyenv install --skip-existing "$SL_PYENV_PYTHON_VER"
  pyenv global $SL_PYENV_PYTHON_VER
  pip install --upgrade pip
  which python
  which pip
  python --version
}

update_flatpacks() {
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak update

  # Install per-user flatpak extras from config.env
  if [[ -n "${SL_USER_FLATPAK_PACKAGES:-}" ]]; then
    local pkg
    for pkg in $SL_USER_FLATPAK_PACKAGES; do
      flatpak install flathub --user -y "$pkg"
    done
  fi

  # Apply per-app overrides from config.env
  if [[ -n "${SL_USER_FLATPAK_OVERRIDES:-}" ]]; then
    local entry app_id args
    for entry in $SL_USER_FLATPAK_OVERRIDES; do
      app_id="${entry%%:*}"
      args="${entry#*:}"
      flatpak override "$app_id" --user $args
    done
  fi
}

setup_containers() {
  containerd-rootless-setuptool.sh install
  containerd-rootless-setuptool.sh install-buildkit
  systemctl --user enable --now containerd
  systemctl --user enable --now buildkit
}

_install_roslyn() {
  eval "dotnet tool install --global roslyn-language-server --prerelease 2>/dev/null || dotnet tool update --global roslyn-language-server --prerelease"
}

setup_dev_env() {
  if command -v dotnet &>/dev/null; then
    run_step _install_roslyn "installing roslyn-language-server (dotnet global tool)"
  else
    log_warn "dotnet SDK not found — skipping Roslyn install. Set ENABLE_DEV_EXTRAS=true in settings.env and re-run the system setup."
  fi

  if command -v containerd &>/dev/null || command -v nerdctl &>/dev/null; then
    run_step setup_containers "setting up containers (containerd + buildkit rootless)"
  else
    log_warn "containerd/nerdctl not found — skipping container setup. Set ENABLE_DEV_EXTRAS=true in settings.env and re-run the system setup."
  fi
}

reload_all() {
  run_step update_bashrc "updating bashrc"
  run_step update_yazi_desktop "installing yazi desktop entry"
  run_step update_packages "updating packages"
  source ~/.bashrc # for pyenv
  run_step update_python "updating python (pyenv)"
  run_step update_flatpacks "updating flatpacks"
  run_step update_wallpaper "updating wallpaper"
  run_step update_monitors "updating monitors"
  run_step update_themes "updating themes"
}

usage() {
  echo "Usage:"
  echo "  $SCRIPT_NAME reload-all"
  echo "  $SCRIPT_NAME config"
  echo "  $SCRIPT_NAME reload-quickshell"
  echo "  $SCRIPT_NAME update-packages"
  echo "  $SCRIPT_NAME update-bashrc"
  echo "  $SCRIPT_NAME update-python"
  echo "  $SCRIPT_NAME update-themes"
  echo "  $SCRIPT_NAME update-monitors"
  echo "  $SCRIPT_NAME update-flatpacks"
  echo "  $SCRIPT_NAME update-wallpaper --path [path]"
  echo "  $SCRIPT_NAME remove-wallpaper --name [name]"
  echo "  $SCRIPT_NAME switch-theme-mode"
  echo "  $SCRIPT_NAME setup-dev-env"
}

case "$SL_THEME_MODE" in
  dark|light) ;;
  *)
    log_err "Unknown theme mode '$SL_THEME_MODE', pick one of [dark/light]"
    return 1
    ;;
esac

case "${1:-}" in
  reload-all)
    shift
    run_step reload_all "reloading user profile"
    ;;
  config)
    shift
    $EDITOR "$SL_ROOT_DIR/config.env"
    ;;
  reload-quickshell)
    shift
    _reload_program qs
    ;;
  update-packages)
    shift
    run_step update_packages "updating packages"
    ;;
  update-bashrc)
    shift
    run_step update_bashrc "updating .bashrc"
    ;;
  update-python)
    shift
    run_step update_python "updating python (pyenv)"
    ;;
  update-themes)
    shift
    run_step update_themes "updating themes"
    ;;
  update-monitors)
    shift
    run_step update_monitors "updating monitors"
    ;;
  update-wallpaper)
    shift
    run_step update_wallpaper "updating wallpaper" "$@"
    _run_matugen
    ;;
  update-flatpacks)
    shift
    run_step update_flatpacks "updating flatpacks"
    ;;
  remove-wallpaper)
    shift
    run_step remove_wallpaper "removing wallpaper" "$@"
    ;;
  switch-theme-mode)
    shift
    run_step switch_theme_mode "switching theme mode"
    ;;
  setup-dev-env)
    shift
    run_step setup_dev_env "setting up dev environment"
    ;;
  *)
    usage
    exit 1
    ;;
esac
