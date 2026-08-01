#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

log_start()   { echo -e "${BOLD}[$(date '+%H:%M:%S')] > $*${RESET}"; }
log_success() { echo -e "${BOLD}[$(date '+%H:%M:%S')] > ${GREEN}$*${RESET}"; }
log_ok()      { echo -e "${GREEN}  v $*${RESET}"; }
log_warn()    { echo -e "${YELLOW}  w $*${RESET}"; }
log_err()     { echo -e "${RED}  x $*${RESET}" >&2; }

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