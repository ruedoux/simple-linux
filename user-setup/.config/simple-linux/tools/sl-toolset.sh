#!/usr/bin/env bash
set -euo pipefail

export TOOLSET_SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

usage() {
  echo "Usage: ${SCRIPT_NAME} <subcommand> [args...]"
  echo ""
  echo "Available subcommands:"
  local scripts=("${TOOLSET_SCRIPT_DIR}/commands/"*.sh)
  for script in "${scripts[@]}"; do
    [[ -f "$script" ]] || continue
    local name="$(basename "$script")"
    name="${name%.sh}"
    [[ "$name" == "global" ]] && continue
    echo "  ${name}"
  done
}

cmd="${1:-}"

if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi

# Validate cmd against path traversal and special characters
if [[ ! "$cmd" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: invalid subcommand '$cmd'" >&2
  usage
  exit 1
fi

script="${TOOLSET_SCRIPT_DIR}/commands/${cmd}.sh"
if [[ ! -f "$script" ]]; then
  echo "Error: unknown subcommand '$cmd'" >&2
  usage
  exit 1
fi

if [[ ! -x "$script" ]]; then
  echo "Error: command script '$script' exists but is not executable" >&2
  exit 1
fi

shift
exec "$script" "$@"
