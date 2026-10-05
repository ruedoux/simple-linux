#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
DESTDIR="${1:-}"

SETTINGS_DIR="$DESTDIR/etc/simple-linux"
TRACK_FILE="$DESTDIR/var/lib/simple-linux/installed-files"

# Declarative manifest: mode|source (relative to repo) |destination (relative to $DESTDIR)
manifest=(
  "644|.lib.sh|etc/simple-linux/lib.sh"
  "755|scripts/sl-system-sync.sh|usr/local/bin/sl-system-sync"
  "755|scripts/sl-system-health.sh|usr/local/bin/sl-system-health"
  "755|scripts/sl-notifications.sh|usr/local/bin/sl-remind-notifications"
)

echo "Syncing system files from repo..."

# Remove every file installed by the previous run, so renames/deletions in the
# repo are reflected without manual cleanup. Paths are absolute and recorded
# without the DESTDIR prefix (so the installed system and /mnt bootstrap both
# resolve correctly via $DESTDIR$path below).
if [ -f "$TRACK_FILE" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    rm -f "$DESTDIR$path"
  done < "$TRACK_FILE"
fi

install -d -m 0755 "$DESTDIR/var/lib/simple-linux"
install -D -m 644 "$SCRIPT_ROOT/settings.default.env" "$SETTINGS_DIR/settings.default.env"

# User overrides: installed once, never overwritten on update (and never tracked).
if [ ! -f "$SETTINGS_DIR/settings.env" ]; then
  install -D -m 644 "$SCRIPT_ROOT/settings.env" "$SETTINGS_DIR/settings.env"
fi

tracked=("/etc/simple-linux/settings.default.env")
for entry in "${manifest[@]}"; do
  IFS='|' read -r mode src dest <<< "$entry"
  install -D -m "$mode" "$SCRIPT_ROOT/$src" "$DESTDIR/$dest"
  tracked+=("/$dest")
done

install -d -m 0755 "$DESTDIR/var/lib/simple-linux/alerts"

# Record installed files for the next run's removal pass.
printf '%s\n' "${tracked[@]}" > "$TRACK_FILE"

if [ -z "$DESTDIR" ]; then
  echo "Done. Run 'sudo sl-system-sync' to apply system changes."
else
  echo "Done. System files installed to $DESTDIR"
fi
