#!/bin/bash
set -euo pipefail

SCRIPT_ROOT="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
DESTDIR="${1:-}"

echo "Syncing system files from repo..."
install -D -m 644 "$SCRIPT_ROOT/settings.env" "$DESTDIR/etc/simple-linux/settings.env"
install -D -m 644 "$SCRIPT_ROOT/.lib.sh" "$DESTDIR/etc/simple-linux/lib.sh"
install -D -m 755 "$SCRIPT_ROOT/scripts/sl-system-sync.sh" "$DESTDIR/usr/local/bin/sl-system-sync"
install -D -m 755 "$SCRIPT_ROOT/scripts/sl-system-health.sh" "$DESTDIR/usr/local/bin/sl-system-health"

if [ -z "$DESTDIR" ]; then
  echo "Done. Run 'sudo sl-system-sync' to apply system changes."
else
  echo "Done. System files installed to $DESTDIR"
fi
