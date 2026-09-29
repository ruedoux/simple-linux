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

install -D -m 644 "$SCRIPT_ROOT/.lib.sh" "$SETTINGS_DIR/lib.sh"
install -D -m 755 "$SCRIPT_ROOT/scripts/sl-system-sync.sh" "$DESTDIR/usr/local/bin/sl-system-sync"
install -D -m 755 "$SCRIPT_ROOT/scripts/sl-system-health.sh" "$DESTDIR/usr/local/bin/sl-system-health"
install -D -m 755 "$SCRIPT_ROOT/scripts/sl-smartd-alert" "$DESTDIR/usr/local/bin/sl-smartd-alert"
install -D -m 755 "$SCRIPT_ROOT/scripts/sl-remind" "$DESTDIR/usr/local/bin/sl-remind"
install -D -m 644 "$SCRIPT_ROOT/systemd/sl-remind@.service" "$DESTDIR/usr/lib/systemd/system/sl-remind@.service"
install -D -m 644 "$SCRIPT_ROOT/systemd/sl-remind-update.timer" "$DESTDIR/usr/lib/systemd/system/sl-remind-update.timer"
install -D -m 644 "$SCRIPT_ROOT/systemd/sl-remind-btrfs.timer" "$DESTDIR/usr/lib/systemd/system/sl-remind-btrfs.timer"
install -d -m 0755 "$DESTDIR/var/lib/simple-linux/alerts"

if [ -z "$DESTDIR" ]; then
  echo "Done. Run 'sudo sl-system-sync' to apply system changes."
else
  echo "Done. System files installed to $DESTDIR"
fi
