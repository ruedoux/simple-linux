#!/usr/bin/env bash
set -euo pipefail

SL_ROOT_DIR="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
TOOLSET_SCRIPT_DIR="$SL_ROOT_DIR/commands/toolset"
export SL_ROOT_DIR TOOLSET_SCRIPT_DIR

source "$SL_ROOT_DIR/.sl-lib.sh"
sl_dispatch "$TOOLSET_SCRIPT_DIR" "sl-user toolset" "$@"
