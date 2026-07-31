#!/bin/bash
set -euo pipefail

SCRIPT_ROOT="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

echo "Syncing system files from repo..."
install -D -m 644 "$SCRIPT_ROOT/settings.env" /etc/simple-linux/settings.env
install -D -m 644 "$SCRIPT_ROOT/.lib.sh" /etc/simple-linux/lib.sh
install -D -m 755 "$SCRIPT_ROOT/scripts/sl-system-sync.sh" /usr/local/bin/sl-system-sync
echo "Done. Run 'sudo sl-system-sync' to apply system changes."
