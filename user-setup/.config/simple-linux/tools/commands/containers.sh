#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
. "${TOOLSET_SCRIPT_DIR}/global.sh"

DEFAULT_CONFIG="${SL_CONTAINERS_CONFIG_FILE:-}"
DEFAULT_COMPOSE="${SL_CONTAINERS_COMPOSE_FILE:-}"

usage() {
  echo "Usage:"
  echo "  $SCRIPT_NAME up-all   [-c|--config-file FILE] [-f|--compose-file FILE]"
  echo "  $SCRIPT_NAME down-all [-c|--config-file FILE] [-f|--compose-file FILE]"
  echo "  $SCRIPT_NAME up       [-c|--config-file FILE] [-f|--compose-file FILE] -n|--container-name NAME"
  echo "  $SCRIPT_NAME down     [-c|--config-file FILE] [-f|--compose-file FILE] -n|--container-name NAME"
  echo "  $SCRIPT_NAME restart  [-c|--config-file FILE] [-f|--compose-file FILE] -n|--container-name NAME"
}

run_health_check() {
  local container="$1"
  local health_check="$2"
  local retries="${3:-10}"
  local delay="${4:-5}"
  local i

  [[ -z "$health_check" ]] && return 0

  for ((i=1; i<=retries; i++)); do
    info Running health check: "$health_check"
    if sh -c "$health_check"; then
      return 0
    fi
    sleep "$delay"
  done

  error "Health check failed for $container"
  return 1
}

start_container() {
  local container="$1"
  local health_check="$2"
  local compose_file="$3"
  local running

  if nerdctl inspect "$container" >/dev/null 2>&1; then
    running="$(nerdctl inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)"
    if [[ "$running" == "true" ]]; then
      info "Container already running, skipping: $container"
      return 0
    fi
  fi

  info "Starting container: $container"
  nerdctl compose -f "$compose_file" up -p "$container" -d "$container"
  run_health_check "$container" "$health_check"
  info "Started container: $container"
}

remove_container() {
  local container="$1"
  local compose_file="$2"

  if ! nerdctl inspect "$container" >/dev/null 2>&1; then
    info "Container does not exist, skipping: $container"
    return 0
  fi

  info "Removing container: $container"
  nerdctl compose -f "$compose_file" rm -s -f -p "$container" "$container"
  info "Removed container: $container"
}

get_container_healthcheck() {
  local config_file="$1"
  local container_name="$2"

  jq -r --arg name "$container_name" '
    .[] | select(.container == $name) | .healthCheck // empty
  ' "$config_file"
}

container_exists_in_config() {
  local config_file="$1"
  local container_name="$2"

  jq -e --arg name "$container_name" '
    .[] | select(.container == $name)
  ' "$config_file" >/dev/null
}

parse_common_args() {
  CONFIG_FILE="$DEFAULT_CONFIG"
  COMPOSE_FILE="$DEFAULT_COMPOSE"
  CONTAINER_NAME=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config-file)
        CONFIG_FILE="$2"
        shift 2
        ;;
      -f|--compose-file)
        COMPOSE_FILE="$2"
        shift 2
        ;;
      -n|--container-name)
        CONTAINER_NAME="$2"
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
}

validate_files() {
  [[ -n "${CONFIG_FILE:-}" ]] || { error "Config file not provided. Use -c/--config-file or set SL_CONTAINERS_CONFIG_FILE in config.env"; return 1; }
  [[ -f "$CONFIG_FILE" ]] || { error "Config file not found: $CONFIG_FILE"; return 1; }
  [[ -n "${COMPOSE_FILE:-}" ]] || { error "Compose file not provided. Use -f/--compose-file or set SL_CONTAINERS_COMPOSE_FILE in config.env"; return 1; }
  [[ -f "$COMPOSE_FILE" ]] || { error "Compose file not found: $COMPOSE_FILE"; return 1; }
}

up_all_containers() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  while read -r obj; do
    local container health_check
    container="$(jq -r '.container' <<< "$obj")"
    health_check="$(jq -r '.healthCheck // empty' <<< "$obj")"
    start_container "$container" "$health_check" "$COMPOSE_FILE"
  done < <(jq -c '.[]' "$CONFIG_FILE")
}

down_all_containers() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  while read -r obj; do
    local container
    container="$(jq -r '.container' <<< "$obj")"
    remove_container "$container" "$COMPOSE_FILE"
  done < <(jq -c '.[]' "$CONFIG_FILE")
}

up_container() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  if [[ -z "$CONTAINER_NAME" ]]; then
    echo "Missing container name"
    usage
    return 1
  fi

  if ! container_exists_in_config "$CONFIG_FILE" "$CONTAINER_NAME"; then
    echo "Container not found in config: $CONTAINER_NAME"
    return 1
  fi

  local health_check
  health_check="$(get_container_healthcheck "$CONFIG_FILE" "$CONTAINER_NAME")"
  start_container "$CONTAINER_NAME" "$health_check" "$COMPOSE_FILE"
}

down_container() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  if [[ -z "$CONTAINER_NAME" ]]; then
    echo "Missing container name"
    usage
    return 1
  fi

  if ! container_exists_in_config "$CONFIG_FILE" "$CONTAINER_NAME"; then
    echo "Container not found in config: $CONTAINER_NAME"
    return 1
  fi

  remove_container "$CONTAINER_NAME" "$COMPOSE_FILE"
}

setup_networks() {
  nerdctl network create internet
}

case "${1:-}" in
  up-all)
    shift
    up_all_containers "$@"
    ;;
  down-all)
    shift
    down_all_containers "$@"
    ;;
  up)
    shift
    up_container "$@"
    ;;
  down)
    shift
    down_container "$@"
    ;;
  restart)
    shift
    down_container "$@"
    up_container "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
