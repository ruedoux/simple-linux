#!/bin/bash
# Self contained script, does not source or require other scripts since its copied on remote host.
set -euo pipefail

# Dependency checks
for dep in restic jq; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "\033[0;31m[ERROR]\033[0m '$dep' is required but not installed" >&2
    exit 1
  fi
done

RED_COLOR='\033[0;31m'
GREEN_COLOR='\033[0;32m'
BLUE_COLOR='\033[0;34m'
PURPLE_COLOR='\033[0;35m'
NO_COLOR='\033[0m'
TOOLSET_DEBUG=${TOOLSET_DEBUG:-false}
DRY_RUN=${DRY_RUN:-false}
RESTIC_PASSWORD=${RESTIC_PASSWORD:-""}

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

info() { echo -e "${BLUE_COLOR}[INFO]${NO_COLOR} $@"; }
error() { echo -e "${RED_COLOR}[ERROR]${NO_COLOR} $@"; }
debug() {
  if [[ "${TOOLSET_DEBUG:-}" == "true" ]]; then
    echo -e "${PURPLE_COLOR}[DEBUG]${NO_COLOR} $@"
  fi
}

get_json_value() {
  local config_file_path="$1"
  local key="$2"
  local value
  value=$(jq --arg key "$key" -er '.[$key]' "$config_file_path") || {
    error "'$key' is a required key in config file '$config_file_path'"
    exit 1
  }
  if [[ -z "$value" ]]; then
    error "'$key' must not be empty in config file '$config_file_path'"
    exit 1
  fi
  echo "$value"
}

ensure_file_exists() {
  local file_path=$1

  if ! [ -f "$file_path" ]; then
    error "File does not exist or is not accessible: '$file_path'"
    exit 1
  fi
}

ensure_repo_exists() {
  local repo_path="$1"

  if ! [[ -f "$repo_path/config" ]]; then
    if [[ -t 0 ]]; then
      read -p "No restic repo found at $repo_path. Create new repo there? [Y/n] " answer
      answer=${answer:-Y}
    else
      error "No restic repo found at '$repo_path' and stdin is not a terminal; cannot prompt"
      exit 1
    fi

    if [[ "$answer" =~ ^[Yy]$ ]]; then
      restic init --repo "$repo_path"
    else
      echo "Aborted."
      exit 1
    fi
  else
    if ! restic -r "$repo_path" cat config 2>&1; then
      error "'$repo_path' could not be validated — check password or repo integrity"
      exit 1
    fi
  fi
}

test_connection() {
  local server_name="$1"

  info "Testing connection to server: '$server_name'"
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server_name" exit 2>/dev/null; then
    info "Connection to server: '$server_name' successful"
  else
    error "Connection to server: '$server_name' failed"
    error "Ensure SSH key-based authentication is set up for '$server_name'"
    exit 1
  fi
}

require_rsync() {
  if ! command -v rsync &>/dev/null; then
    echo -e "\033[0;31m[ERROR]\033[0m 'rsync' is required but not installed" >&2
    return 1
  fi
}

rsync_copy() {
  local rsync_source=$1
  local rsync_destination=$2
  info "Copying '$rsync_source' to '$rsync_destination' with checksum"
  rsync -arzP --delete --checksum "$rsync_source" "$rsync_destination"
}

backup() {
  local config_file_path="$1"

  ensure_file_exists "$config_file_path"

  # Validate required JSON keys exist
  for key in "repo-root" "repo-name" "includes" "excludes"; do
    if ! jq -e "has(\"$key\")" "$config_file_path" > /dev/null; then
      error "Required key '$key' not found in config file '$config_file_path'"
      exit 1
    fi
  done

  local repo_root=$(get_json_value "$config_file_path" "repo-root")
  local repo_name=$(get_json_value "$config_file_path" "repo-name")
  local repo_path="${repo_root}/${repo_name}"

  local backup_tag=$(jq -r '.tag // "main"' "$config_file_path")
  local compression=$(jq -r '.compression // "max"' "$config_file_path")

  case "$compression" in
    auto|off|max) ;;
    *)
      error "Invalid compression value '$compression': must be one of auto, off, max"
      exit 1
      ;;
  esac

  if [[ -z "$backup_tag" ]]; then
    error "Tag must not be empty in config file '$config_file_path'"
    exit 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN: would backup to $repo_path"
    return 0
  fi

  local includes_file=$(mktemp)
  local excludes_file=$(mktemp)

  local lock_dir="${HOME}/.cache/sl-backup/locks"
  mkdir -p "$lock_dir"
  local lock_file="${lock_dir}/backup-$(echo "$repo_path" | sha256sum | cut -d' ' -f1).lock"
  exec 9>"$lock_file"
  if ! flock -n 9; then
    error "Another backup is already running for repo '$repo_path'. Exiting."
    exit 1
  fi
  trap 'rm -f "${includes_file:-}" "${excludes_file:-}"; exec 9>&-; rm -f "${lock_file:-}"' EXIT

  jq -r '.includes[]' "$config_file_path" > "$includes_file"
  jq -r '.excludes[]' "$config_file_path" > "$excludes_file"

  debug "Includes content:\n$(cat "$includes_file")"
  debug "Excludes content:\n$(cat "$excludes_file")"
  if ! [[ -n "$RESTIC_PASSWORD" ]]; then
    if jq -e "has(\"key\")" "$config_file_path" > /dev/null; then
      export RESTIC_PASSWORD=$(jq -r '.["key"]' "$config_file_path")
    elif [[ -t 0 ]]; then
      read -s -p "Enter repository password: " RESTIC_PASSWORD
      export RESTIC_PASSWORD
    else
      error "RESTIC_PASSWORD not set and stdin is not a terminal; cannot prompt"
      exit 1
    fi
  fi

  ensure_repo_exists "$repo_path"

  info "Running backup to '$repo_path'"

  restic -r "$repo_path" backup \
    --files-from "$includes_file" \
    --exclude-file "$excludes_file" \
    --tag "$backup_tag" \
    --compression "$compression" \
    --exclude-caches

  if jq -e '.["restic-forget-params"]' "$config_file_path" > /dev/null 2>&1; then
    local prune_params
    prune_params=$(jq -r '.["restic-forget-params"] | join(" ")' "$config_file_path")
    info "Pruning repo '$repo_path'"
    if ! restic -r "$repo_path" forget --prune --quiet $prune_params; then
      error "Backup succeeded but prune failed"
    fi
  else
    info "No restic-forget-params found; skipping prune"
  fi

  if jq -e '.["restic-check"] == true' "$config_file_path" > /dev/null 2>&1; then
    info "Running restic check on '$repo_path'"
    if ! restic -r "$repo_path" check; then
      error "Backup succeeded but restic check failed"
    fi
  fi

  info "Finished backing up to '$repo_path'"

  info "Listing snapshots for '$repo_path'"
  restic -r "$repo_path" snapshots

  info "Showing backups size"
  # GNU du only; use du -d 1 on BSD/macOS
  du --max-depth 1 -h "$repo_root"
  unset RESTIC_PASSWORD
}

backup_entry() {
  local config_file_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config)
        config_file_path="$2"
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        echo "Usage: $SCRIPT_NAME backup --config <file>"
        echo ""
        echo "  --config, -c <file>  JSON config file with repo-root, repo-name, includes, excludes, key"
        echo "  --dry-run, -n        Simulate without making changes"
        return 0
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

  if [[ -z "$config_file_path" ]]; then
      echo "Usage: $SCRIPT_NAME backup --config <file>"
      return 1
  fi

  backup "$config_file_path"
}

remote_backup() {
  local config_file_path="$1"

  ensure_file_exists "$config_file_path"
  local server_name=$(get_json_value "$config_file_path" "server")

  test_connection "$server_name"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN: would run backup on server '$server_name'"
    return 0
  fi

  # Verify restic and jq are available on the remote server
  info "Checking remote dependencies"
  for remote_dep in restic jq; do
    if ! ssh "$server_name" "command -v $remote_dep" &>/dev/null; then
      error "'$remote_dep' is not installed on remote server '$server_name'"
      exit 1
    fi
  done

  local script_name="$(basename "${BASH_SOURCE[0]}")"
  local remote_home
  remote_home=$(ssh "$server_name" 'echo $HOME')
  local script_destination_path="${remote_home}/.cache/sl-backup/${script_name}.XXXXXX-$$"
  ssh "$server_name" "mkdir -p ${remote_home}/.cache/sl-backup"
  rsync_copy "${BASH_SOURCE[0]}" "$server_name:$script_destination_path"

  local config_destination_path="${remote_home}/.cache/sl-backup/backup-config.XXXXXX.json-$$"
  rsync_copy "$config_file_path" "$server_name:$config_destination_path"

  local escaped_script_path=$(printf '%q' "$script_destination_path")
  local escaped_config_path=$(printf '%q' "$config_destination_path")

  info "Running backup on server '$server_name'"
  ssh "$server_name" "${escaped_script_path} backup --config ${escaped_config_path}; rc=\$?; rm -f ${escaped_script_path} ${escaped_config_path}; exit \$rc"
}

remote_backup_entry() {
  local config_file_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config)
        config_file_path="$2"
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        echo "Usage: $SCRIPT_NAME remote-backup --config <file>"
        echo ""
        echo "  --config, -c <file>  JSON config file with repo-root, repo-name, includes, excludes, key, server"
        echo "  --dry-run, -n        Simulate without making changes"
        return 0
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

  if [[ -z "$config_file_path" ]]; then
      echo "Usage: $SCRIPT_NAME remote-backup --config <file>"
      return 1
  fi

  require_rsync || exit 1
  remote_backup "$config_file_path"
}

sync_backup_internal() {
  local direction="$1"
  local local_config="$2"
  local dest_config="$3"
  local sync_repo_name="$4"

  ensure_file_exists "$local_config"
  ensure_file_exists "$dest_config"

  local local_repo_root=$(get_json_value "$local_config" "repo-root")
  local dest_repo_root=$(get_json_value "$dest_config" "repo-root")
  local server_name=$(get_json_value "$dest_config" "server")

  if [[ "$direction" == "push" ]]; then
    info "Pushing local repository '$sync_repo_name' to server '$server_name'"
    if ! [[ -f "$local_repo_root/$sync_repo_name/config" ]]; then
      error "Provided repo doesnt exist or isn't accessible: '$local_repo_root/$sync_repo_name'"
      exit 1
    fi
  else
    local remote_repo_path="$dest_repo_root/$sync_repo_name"
    info "Pulling remote repository '$sync_repo_name' from server '$server_name'"
    if ! ssh "$server_name" "[[ -f '$remote_repo_path/config' ]]"; then
      error "Provided repo doesn't exist or isn't accessible: '$server_name:$remote_repo_path'"
      exit 1
    fi
  fi

  test_connection "$server_name"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN: would ${direction} '$sync_repo_name' to/from server '$server_name'"
    return 0
  fi

  if [[ "$direction" == "push" ]]; then
    rsync_copy "$local_repo_root/$sync_repo_name/" "$server_name:$dest_repo_root/$sync_repo_name"
    info "Finished pushing '$sync_repo_name' to server '$server_name'"
    info "Showing destination repository sizes"
    # GNU du only; use du -d 1 on BSD/macOS
    ssh "$server_name" du --max-depth 1 -h "$dest_repo_root"
  else
    rsync_copy "$server_name:$dest_repo_root/$sync_repo_name/" "$local_repo_root/$sync_repo_name"
    info "Finished pulling '$sync_repo_name' from server '$server_name'"
    info "Showing destination repository sizes"
    # GNU du only; use du -d 1 on BSD/macOS
    du --max-depth 1 -h "$local_repo_root"
  fi
}

push_backup() {
  sync_backup_internal "push" "$1" "$2" "$3"
}

push_backup_entry() {
  local local_config_file_path=""
  local destination_config_file_path=""
  local repo_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -lc|--local-config)
        local_config_file_path="$2"
        shift 2
        ;;
      -dc|--destination-config)
        destination_config_file_path="$2"
        shift 2
        ;;
      -r|--repo)
        repo_name="$2"
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        echo "Usage: $SCRIPT_NAME push-backup --local-config <file> --destination-config <file> --repo <name>"
        echo ""
        echo "  --local-config, -lc <file>         Local config file"
        echo "  --destination-config, -dc <file>   Destination config file"
        echo "  --repo, -r <name>                  Repository name"
        echo "  --dry-run, -n                      Simulate without making changes"
        return 0
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

  if [[ -z "$local_config_file_path" || -z "$destination_config_file_path" || -z "$repo_name" ]]; then
      echo "Usage: $SCRIPT_NAME push-backup --local-config <file> --destination-config <file> --repo <name>"
      return 1
  fi

  require_rsync || exit 1
  push_backup "$local_config_file_path" "$destination_config_file_path" "$repo_name"
}

pull_backup() {
  sync_backup_internal "pull" "$1" "$2" "$3"
}

pull_backup_entry() {
  local local_config_file_path=""
  local destination_config_file_path=""
  local repo_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -lc|--local-config)
        local_config_file_path="$2"
        shift 2
        ;;
      -dc|--destination-config)
        destination_config_file_path="$2"
        shift 2
        ;;
      -r|--repo)
        repo_name="$2"
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        echo "Usage: $SCRIPT_NAME pull-backup --local-config <file> --destination-config <file> --repo <name>"
        echo ""
        echo "  --local-config, -lc <file>         Local config file"
        echo "  --destination-config, -dc <file>   Destination config file"
        echo "  --repo, -r <name>                  Repository name"
        echo "  --dry-run, -n                      Simulate without making changes"
        return 0
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

  if [[ -z "$local_config_file_path" || -z "$destination_config_file_path" || -z "$repo_name" ]]; then
      echo "Usage: $SCRIPT_NAME pull-backup --local-config <file> --destination-config <file> --repo <name>"
      return 1
  fi

  require_rsync || exit 1
  pull_backup "$local_config_file_path" "$destination_config_file_path" "$repo_name"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)
            shift
            remote_backup_entry "$@"
            exit $?
            ;;
        --push)
            shift
            push_backup_entry "$@"
            exit $?
            ;;
        --pull)
            shift
            pull_backup_entry "$@"
            exit $?
            ;;
        -h|--help)
            echo "Usage: $SCRIPT_NAME [--remote|--push|--pull] [args...]"
            echo ""
            echo "  (no flag)       Local backup:   --config <file>"
            echo "  --remote        Remote backup:   --config <file>"
            echo "  --push          Push repo:       --local-config <f> --destination-config <f> --repo <name>"
            echo "  --pull          Pull repo:       --local-config <f> --destination-config <f> --repo <name>"
            echo "  --dry-run, -n                    Simulate without making changes"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Default: local backup
backup_entry "$@"
