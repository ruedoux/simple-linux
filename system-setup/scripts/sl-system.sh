#!/usr/bin/env bash
set -euo pipefail

SL_SYSTEM_LIB_DIR="${SL_SYSTEM_LIB_DIR:-/usr/local/lib/simple-linux}"

usage() {
  echo "Usage: ${0##*/} <subcommand> [args...]"
  echo ""
  echo "Available subcommands:"
  local scripts=("$SL_SYSTEM_LIB_DIR"/*.sh)
  for script in "${scripts[@]}"; do
    [[ -f "$script" ]] || continue
    local name
    name="$(basename "$script")"
    name="${name%.sh}"
    [[ "$name" == "lib" ]] && continue
    echo "  ${name}"
  done
}

cmd="${1:-}"

if [[ -z "$cmd" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! "$cmd" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: invalid subcommand '$cmd'" >&2
  usage >&2
  exit 1
fi

script="${SL_SYSTEM_LIB_DIR}/${cmd}.sh"
if [[ ! -f "$script" ]]; then
  echo "Error: unknown subcommand '$cmd'" >&2
  usage >&2
  exit 1
fi

if [[ ! -x "$script" ]]; then
  echo "Error: command script '$script' exists but is not executable" >&2
  exit 1
fi

shift
exec "$script" "$@"
