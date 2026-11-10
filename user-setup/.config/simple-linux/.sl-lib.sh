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

load_config() {
  set -a
  [ -f "$SL_CONFIG_DEFAULT_PATH" ] && source "$SL_CONFIG_DEFAULT_PATH"
  [ -f "$SL_CONFIG_PATH" ] && source "$SL_CONFIG_PATH"
  set +a
}

toolset.update_config_variable() {
  local config_file_path="$1"
  local var_name="$2"
  local var_value="$3"

  if [[ ! -f "$config_file_path" ]]; then
    error "Config file '$config_file_path' does not exist." >&2
    return 1
  fi

  if [[ -z "$var_name" || -z "$var_value" ]]; then
    error "Variable name and value are required" >&2
    return 1
  fi

  if grep -q "^${var_name}=" "$config_file_path"; then
    sed -i "s|^${var_name}=.*|${var_name}=\"${var_value}\"|" "$config_file_path"
  else
    printf '%s="%s"\n' "$var_name" "$var_value" >> "$config_file_path"
  fi
}
