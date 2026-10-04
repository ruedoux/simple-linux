#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
DESTDIR="${1:-}"

SETTINGS_DIR="$DESTDIR/etc/simple-linux"

echo "Syncing system files from repo..."

install -D -m 644 "$SCRIPT_ROOT/settings.default.env" "$SETTINGS_DIR/settings.default.env"

# User overrides: installed once, never overwritten on update.
if [ ! -f "$SETTINGS_DIR/settings.env" ]; then
  install -D -m 644 "$SCRIPT_ROOT/settings.env" "$SETTINGS_DIR/settings.env"
fi

# Declarative manifest: mode|source (relative to repo) |destination (relative to $DESTDIR)
while IFS='|' read -r mode src dest; do
  [ -n "$mode" ] || continue
  install -D -m "$mode" "$SCRIPT_ROOT/$src" "$DESTDIR/$dest"
done <<'EOF'
644|.lib.sh|etc/simple-linux/lib.sh
755|scripts/sl-system-sync.sh|usr/local/bin/sl-system-sync
755|scripts/sl-system-health.sh|usr/local/bin/sl-system-health
755|scripts/sl-remind|usr/local/bin/sl-remind
644|systemd/sl-remind@.service|usr/lib/systemd/system/sl-remind@.service
644|systemd/sl-remind-update.timer|usr/lib/systemd/system/sl-remind-update.timer
644|systemd/sl-remind-btrfs.timer|usr/lib/systemd/system/sl-remind-btrfs.timer
EOF

install -d -m 0755 "$DESTDIR/var/lib/simple-linux/alerts"

if [ -z "$DESTDIR" ]; then
  echo "Done. Run 'sudo sl-system-sync' to apply system changes."
else
  echo "Done. System files installed to $DESTDIR"
fi
