#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
. "${TOOLSET_SCRIPT_DIR}/global.sh"

# Override to stderr since stdout is captured by eval
info()  { echo -e "${BLUE}[INFO]${RESET} $*" >&2; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

switch_account() {
  local account_name="$1"
  local account_dir="$2"
  local account_file="$account_dir/$account_name"

  if [ ! -f "$account_file" ]; then
    error "Account profile '$account_name' not found in $account_dir"
    return 1
  fi

  unset SSH_KEY USER_NAME USER_EMAIL
  . "$account_file"

  if [ -z "${SSH_KEY:-}" ] || [ -z "${USER_NAME:-}" ] || [ -z "${USER_EMAIL:-}" ]; then
    error "Account profile must define SSH_KEY, USER_NAME, and USER_EMAIL"
    return 1
  fi

  if [ ! -f "$SSH_KEY" ]; then
    error "SSH key not found: $SSH_KEY"
    return 1
  fi

  # Kill existing ssh-agent
  local ssh_agent_pid
  ssh_agent_pid="$(pgrep -u "$USER" ssh-agent 2>/dev/null || true)"
  if [ -n "$ssh_agent_pid" ]; then
    kill "$ssh_agent_pid" 2>/dev/null || true
    info "[git] Killed ssh-agent: $ssh_agent_pid"
  fi

  # Start new ssh-agent and eval its env into this script's process
  local agent_output
  agent_output="$(ssh-agent -s)" || {
    error "Failed to start ssh-agent"
    return 1
  }
  eval "$agent_output" >/dev/null

  # Add the key
  local ssh_add_output
  ssh_add_output="$(ssh-add "$SSH_KEY" 2>&1)" || {
    error "Failed to add SSH key: $SSH_KEY"
    error "$ssh_add_output"
    return 1
  }
  info "[git] $ssh_add_output"

  # Set git config globally (writes to file, no eval needed)
  git config --global user.name "$USER_NAME"
  git config --global user.email "$USER_EMAIL"
  info "[git] Switched to $account_name account ($USER_NAME <$USER_EMAIL>)"

  # Print only the two export lines to stdout for eval by caller
  echo "$agent_output" | head -2
}

main() {
  local account_name=""
  local account_dir="$HOME/.config/git-accounts"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--account)
        account_name="$2"
        shift 2
        ;;
      -d|--dir)
        account_dir="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: eval \"\$(toolset.sh git-switch --account <name> [--dir <path>])\""
        echo ""
        echo "Switches git user and SSH key for the current shell session."
        echo ""
        echo "Options:"
        echo "  -a, --account <name>   Account profile name (file in the accounts directory)"
        echo "  -d, --dir <path>       Directory containing account profiles (default: ~/.config/git-accounts)"
        return 0
        ;;
      -*)
        error "Unknown option: $1"
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [ -z "$account_name" ]; then
    error "Usage: eval \"\$(toolset.sh git-switch --account <name> [--dir <path>])\""
    return 1
  fi

  switch_account "$account_name" "$account_dir"
}

main "$@"
