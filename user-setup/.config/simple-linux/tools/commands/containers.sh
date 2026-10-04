#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
. "$(dirname "${TOOLSET_SCRIPT_DIR}")/.sl-lib.sh"
load_config

DEFAULT_COMPOSE="${SL_CONTAINERS_COMPOSE_FILE:-}"

usage() {
  echo "Usage:"
  echo "  $SCRIPT_NAME up-all   [-f|--compose-file FILE]"
  echo "  $SCRIPT_NAME down-all [-f|--compose-file FILE]"
  echo "  $SCRIPT_NAME up       [-f|--compose-file FILE] -n|--container-name NAME"
  echo "  $SCRIPT_NAME down     [-f|--compose-file FILE] -n|--container-name NAME"
  echo "  $SCRIPT_NAME restart  [-f|--compose-file FILE] -n|--container-name NAME"
}

read_healthcheck() {
  local container="$1"
  nerdctl inspect -f '{{index .Config.Labels "sl.healthcheck"}}' "$container" 2>/dev/null || true
}

wait_until_healthy() {
  local container="$1"
  local health_check retries=10 delay=5 i

  health_check="$(read_healthcheck "$container")"

  case "$health_check" in
    ""|"<nil>"|"<no value>") return 0 ;;
  esac

  for ((i=1; i<=retries; i++)); do
    info "Running health check: $health_check"
    if sh -c "$health_check"; then
      return 0
    fi
    sleep "$delay"
  done

  error "Health check failed for $container"
  return 1
}

wait_service_healthy() {
  local service="$1"
  local container

  container="$(nerdctl compose -p "$service" -f "$COMPOSE_FILE" ps -q "$service")"
  if [[ -z "$container" ]]; then
    debug "No container resolved for service: $service; skipping health check"
    return 0
  fi

  wait_until_healthy "$container"
}

start_service() {
  local service="$1"

  info "Starting service: $service"
  nerdctl compose -p "$service" -f "$COMPOSE_FILE" up -d "$service"
  wait_service_healthy "$service"
  info "Started service: $service"
}

remove_service() {
  local service="$1"

  info "Removing service: $service"
  nerdctl compose -p "$service" -f "$COMPOSE_FILE" rm -s -f "$service"
  info "Removed service: $service"
}

parse_common_args() {
  COMPOSE_FILE="$DEFAULT_COMPOSE"
  CONTAINER_NAME=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
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
  [[ -n "${COMPOSE_FILE:-}" ]] || { error "Compose file not provided. Use -f/--compose-file or set SL_CONTAINERS_COMPOSE_FILE in config.env"; return 1; }
  [[ -f "$COMPOSE_FILE" ]] || { error "Compose file not found: $COMPOSE_FILE"; return 1; }
}

up_all_containers() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  while read -r service; do
    [[ -n "$service" ]] || continue
    start_service "$service"
  done < <(nerdctl compose -f "$COMPOSE_FILE" config --services)
}

down_all_containers() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  while read -r service; do
    [[ -n "$service" ]] || continue
    remove_service "$service"
  done < <(nerdctl compose -f "$COMPOSE_FILE" config --services)
}

up_container() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  if [[ -z "$CONTAINER_NAME" ]]; then
    echo "Missing container name"
    usage
    return 1
  fi

  start_service "$CONTAINER_NAME"
}

down_container() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  if [[ -z "$CONTAINER_NAME" ]]; then
    echo "Missing container name"
    usage
    return 1
  fi

  remove_service "$CONTAINER_NAME"
}

restart_container() {
  parse_common_args "$@" || return 1
  validate_files || return 1

  if [[ -z "$CONTAINER_NAME" ]]; then
    echo "Missing container name"
    usage
    return 1
  fi

  info "Restarting service: $CONTAINER_NAME"
  remove_service "$CONTAINER_NAME"
  start_service "$CONTAINER_NAME"
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
    restart_container "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
