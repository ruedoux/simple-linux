#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
BLUE='\033[0;34m'
# shellcheck disable=SC2034
PURPLE='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

# Logging — controller style
log_start()   { echo -e "${BOLD}[$(date '+%H:%M:%S')] > $*${RESET}"; }
log_success() { echo -e "${BOLD}[$(date '+%H:%M:%S')] > ${GREEN}$*${RESET}"; }
log_ok()      { echo -e "${GREEN}  v $*${RESET}"; }
log_warn()    { echo -e "${YELLOW}  w $*${RESET}"; }
log_err()     { echo -e "${RED}  x $*${RESET}" >&2; }

# Logging — toolset style
info()  { echo -e "${BLUE}[INFO]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*"; }
debug() {
  if [[ "${TOOLSET_DEBUG:-}" == "true" ]]; then
    echo -e "${PURPLE}[DEBUG]${RESET} $*"
  fi
}

run_step() {
  local fn="$1"
  local message="$2"
  shift 2

  log_start "Started ${message}"
  if ! "$fn" "$@"; then
    log_err "FAILED: ${message}"
    return 1
  fi
  log_success "Finished ${message}"
}

# Config loading — managed defaults first, then user overrides
SL_ROOT_DIR="${SL_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SL_CONFIG_DEFAULT_PATH="${SL_CONFIG_DEFAULT_PATH:-$SL_ROOT_DIR/config.default.env}"
SL_CONFIG_PATH="${SL_CONFIG_PATH:-$SL_ROOT_DIR/config.env}"
SL_SETTINGS_DEFAULT_PATH="${SL_SETTINGS_DEFAULT_PATH:-/etc/simple-linux/settings.default.env}"
SL_SETTINGS_PATH="${SL_SETTINGS_PATH:-/etc/simple-linux/settings.env}"

load_config() {
  set -a
  [ -f "$SL_CONFIG_DEFAULT_PATH" ] && source "$SL_CONFIG_DEFAULT_PATH"
  [ -f "$SL_CONFIG_PATH" ] && source "$SL_CONFIG_PATH"
  set +a
}

load_system_settings() {
  set -a
  [ -f "$SL_SETTINGS_DEFAULT_PATH" ] && source "$SL_SETTINGS_DEFAULT_PATH"
  [ -f "$SL_SETTINGS_PATH" ] && source "$SL_SETTINGS_PATH"
  set +a
}

toolset.require_var() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    error "Variable $var_name is not set. Please add it to ${SL_CONFIG_PATH:-config.env}"
    return 1
  fi
}

toolset.set_if_exists() {
  [ -f "$1" ] && printf '%s\n' "$1"
}

toolset.get_config_file_from_args() {
  local config_file_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config)
        shift
        config_file_path="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$config_file_path" ]]; then
    error "Error: --config option is required." >&2
    return 1
  fi

  if [[ ! -f "$config_file_path" ]]; then
    error "Error: Config file '$config_file_path' does not exist." >&2
    return 1
  fi

  readlink -f "$config_file_path"
}

toolset.verify_config() {
  local config_path="$1"
  shift
  for var in "$@"; do
    awk -F= -v name="$var" '$1 == name { found=1; exit } END { exit !found }' "$config_path" \
      || { error "Variable $var not found in $config_path" >&2; return 1; }
  done
}

toolset.verify_json_config() {
  local config_path="$1"
  shift

  for path in "$@"; do
    jq -e ".$path" "$config_path" > /dev/null 2>&1 || {
      error "Path $path not found in $config_path" >&2
      return 1
    }
  done
}

toolset.update_config_variable() {
  local config_file_path="$1"
  local var_name="$2"
  local var_value="$3"

  if [[ ! -f "$config_file_path" ]]; then
    error "Config file '$config_file_path' does not exist." >&2
    return 1
  fi

  if [ -z "${var_name+x}" ]; then
    error "Variable name not provided" >&2
    return 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v name="$var_name" -v value="$var_value" '
    BEGIN { FS = OFS = "=" }
    $1 == name { $0 = name "=\"" value "\"" }
    { print }
  ' "$config_file_path" > "$tmp_file" && mv "$tmp_file" "$config_file_path"
}

toolset.verify_variable_exists() {
  local var_name="$1"
  if [ -z "${!var_name+x}" ]; then
    error "Variable $var_name not set" >&2
    return 1
  fi
}
