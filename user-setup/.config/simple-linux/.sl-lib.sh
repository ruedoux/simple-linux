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

sl_subcommand_names() {
  local scripts_dir="$1" script name
  for script in "$scripts_dir"/*.sh; do
    [[ -f "$script" ]] || continue
    name="$(basename "$script")"
    echo "${name%.sh}"
  done
}

sl_print_usage() {
  local scripts_dir="$1" display_cmd="${2:-${0##*/}}" name
  echo "Usage: $display_cmd <subcommand> [args...]"
  echo ""
  echo "Available subcommands:"
  while IFS= read -r name; do
    [[ -n "$name" ]] && echo "  $name"
  done < <(sl_subcommand_names "$scripts_dir")
}

# sl_dispatch <scripts_dir> <display_cmd> [args...]
sl_dispatch() {
  local scripts_dir="$1" display_cmd="$2"
  shift 2
  local cmd="${1:-}" script

  if [[ -z "$cmd" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
    sl_print_usage "$scripts_dir" "$display_cmd"
    exit 0
  fi

  if [[ ! "$cmd" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: invalid subcommand '$cmd'" >&2
    sl_print_usage "$scripts_dir" "$display_cmd" >&2
    exit 1
  fi

  script="$scripts_dir/$cmd.sh"
  if [[ ! -f "$script" ]]; then
    echo "Error: unknown subcommand '$cmd'" >&2
    sl_print_usage "$scripts_dir" "$display_cmd" >&2
    exit 1
  fi

  if [[ ! -x "$script" ]]; then
    echo "Error: command script '$script' exists but is not executable" >&2
    exit 1
  fi

  shift
  exec "$script" "$@"
}
