#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_ROOT/.lib.sh"

DESTDIR="${1:-}"

SETTINGS_DIR="$DESTDIR/etc/simple-linux"
TRACK_FILE="$DESTDIR/var/lib/simple-linux/installed-files"

# Declarative manifest: mode|source (relative to repo) |destination (relative to $DESTDIR)
MANIFESTS=(
  "644|.lib.sh|etc/simple-linux/lib.sh"
  "755|scripts/sl-system-sync.sh|usr/local/bin/sl-system-sync"
  "755|scripts/sl-system-health.sh|usr/local/bin/sl-system-health"
  "755|scripts/sl-notifications.sh|usr/local/bin/sl-notifications"
)

# Absolute install paths recorded for the next run's removal pass.
TRACKED_FILES=()

clear_old_files() {
  if [ ! -f "$TRACK_FILE" ]; then
    log_ok "No previous install to clean up"
    return 0
  fi

  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    rm -f "$DESTDIR$path"
  done < "$TRACK_FILE"
  log_ok "Removed files from previous install"
}

install_settings() {
  install -d -m 0755 "$DESTDIR/var/lib/simple-linux"

  install -D -m 644 "$SCRIPT_ROOT/settings.default.env" "$SETTINGS_DIR/settings.default.env"
  log_ok "Installed /etc/simple-linux/settings.default.env"
  TRACKED_FILES+=("/etc/simple-linux/settings.default.env")

  # User overrides: installed once, never overwritten on update (and never tracked).
  if [ ! -f "$SETTINGS_DIR/settings.env" ]; then
    install -D -m 644 "$SCRIPT_ROOT/settings.env" "$SETTINGS_DIR/settings.env"
    log_ok "Installed /etc/simple-linux/settings.env"
  else
    log_ok "Preserved existing /etc/simple-linux/settings.env"
  fi
}

install_manifest_files() {
  local entry mode src dest
  for entry in "${MANIFESTS[@]}"; do
    IFS='|' read -r mode src dest <<< "$entry"
    install -D -m "$mode" "$SCRIPT_ROOT/$src" "$DESTDIR/$dest"
    log_ok "Installed /$dest"
    TRACKED_FILES+=("/$dest")
  done
}

install_alerts_dir() {
  install -d -m 0755 "$DESTDIR/var/lib/simple-linux/alerts"
}

record_installed_files() {
  printf '%s\n' "${TRACKED_FILES[@]}" > "$TRACK_FILE"
  log_ok "Recorded ${#TRACKED_FILES[@]} files for next cleanup"
}

main() {
  log_step "Syncing system files from repo"
  run_step clear_old_files "removing previously installed files"
  run_step install_settings "installing settings"
  run_step install_manifest_files "installing manifest files"
  run_step install_alerts_dir "creating alerts directory"
  run_step record_installed_files "recording installed files"

  if [ -z "$DESTDIR" ]; then
    log_ok "Done. Run 'sudo sl-system-sync' to apply system changes."
  else
    log_ok "Done. System files installed to $DESTDIR"
  fi
}

main
