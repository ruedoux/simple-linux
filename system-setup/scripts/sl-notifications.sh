#!/usr/bin/env bash
set -euo pipefail

# simple-linux persistent notification system.
#
#   sl-remind-notifications notify         (user) display smartd alerts + due reminders as desktop notifications
#   sl-remind-notifications reset <kind>   (root) write the current time to a reminder stamp, silencing it for another interval
#   sl-remind-notifications check-update   read-only check for a new repo version; notify user
#   sl-remind-notifications smartd         write a disk-failure alert (called by smartd -M exec)
#
# Reminders ("update" weekly, "btrfs" monthly) are driven by timestamp files
# (${kind}.stamp) rather than systemd timers or persisted .alert files. `notify`
# is read-only: it compares each stamp against the current time and shows the
# reminder once its interval has elapsed. Only root writes stamps — via `reset`
# or via `sl-system-sync` (which resets the "update" stamp after each update).

if [ -f /etc/simple-linux/settings.default.env ]; then
  # shellcheck disable=SC1091
  source /etc/simple-linux/settings.default.env
fi
if [ -f /etc/simple-linux/settings.env ]; then
  # shellcheck disable=SC1091
  source /etc/simple-linux/settings.env
fi

ALERTS_DIR="${NOTIFY_ALERTS_DIR:-/var/lib/simple-linux/alerts}"
UPDATE_INTERVAL="${NOTIFY_UPDATE_INTERVAL:-604800}"
BTRFS_INTERVAL="${NOTIFY_BTRFS_INTERVAL:-2592000}"

remind_if_due() {
  local kind="$1"
  local interval="$2"
  local title="$3"
  local body="$4"
  local stamp="$ALERTS_DIR/${kind}.stamp"

  [ -f "$stamp" ] || return 0

  local now last
  now="$(date +%s)"
  last="$(cat "$stamp")"

  if [ $((now - last)) -ge "$interval" ]; then
    notify-send -u normal "$title" "$body" 2>/dev/null || true
  fi
}

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0

  remind_if_due "update" "$UPDATE_INTERVAL" "System update" "Update the system and run a backup."
  remind_if_due "btrfs" "$BTRFS_INTERVAL" "Btrfs health check" "Run a btrfs scrub and health check."

  shopt -s nullglob
  local files=("$ALERTS_DIR"/*.alert)
  shopt -u nullglob

  local f title body urgency
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue

    title="$(head -n 1 "$f")"
    body="$(tail -n +2 "$f")"
    [ -n "$body" ] || body="$title"

    case "$(basename "$f")" in
      critical-*) urgency="critical" ;;
      *)          urgency="normal" ;;
    esac

    notify-send -u "$urgency" "$title" "$body" 2>/dev/null || true
  done
}

reset_reminder() {
  local kind="$1"
  local stamp="$ALERTS_DIR/${kind}.stamp"

  mkdir -p "$ALERTS_DIR"
  chmod 0755 "$ALERTS_DIR" 2>/dev/null || true
  printf '%s\n' "$(date +%s)" > "$stamp"
  chmod 0644 "$stamp" 2>/dev/null || true
}

smartd_alert() {
  local device="${SMARTD_DEVICESTRING:-${SMARTD_DEVICE:-unknown}}"
  local fail_type="${SMARTD_FAILTYPE:-unknown}"
  local message="${SMARTD_MESSAGE:-No SMARTD_MESSAGE provided}"
  local timestamp
  timestamp="$(date +"%Y-%m-%d_%H-%M-%S-%3N")"

  mkdir -p "$ALERTS_DIR"
  chmod 0755 "$ALERTS_DIR" 2>/dev/null || true

  local alert_file="$ALERTS_DIR/critical-${timestamp}.alert"
  {
    printf 'Disk health alert\n'
    printf 'Device: %s\n' "$device"
    printf 'Fail type: %s\n' "$fail_type"
    printf '%s\n' "$message"
  } > "$alert_file"
  chmod 0644 "$alert_file" 2>/dev/null || true
}

check_update() {
  command -v notify-send >/dev/null 2>&1 || return 0

  local repo="${SYSTEM_WIDE_DEST:-/opt/simple-linux}"
  [ -d "$repo/.git" ] || return 0

  local remote_url local_head remote_head
  remote_url="$(git config -f "$repo/.git/config" --get remote.origin.url 2>/dev/null || true)"
  [ -n "$remote_url" ] || return 0

  local_head="$(git -c safe.directory="$repo" -C "$repo" rev-parse HEAD 2>/dev/null || true)"
  [ -n "$local_head" ] || return 0

  remote_head="$(timeout 10 git ls-remote "$remote_url" HEAD 2>/dev/null | awk '{print $1}' || true)"
  [ -n "$remote_head" ] || return 0

  if [ "$local_head" != "$remote_head" ]; then
    notify-send -u normal "simple-linux update available" \
      "A new version is available — run 'sudo sl-system-sync' to update." 2>/dev/null || true
  fi
}

case "${1:-}" in
  check-update)
    check_update
    ;;
  smartd)
    smartd_alert
    ;;
  notify)
    notify
    ;;
  reset)
    case "${2:-}" in
      update|btrfs)
        reset_reminder "$2"
        ;;
      *)
        echo "Usage: sl-remind-notifications reset [update|btrfs]" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Usage: sl-remind-notifications [check-update|smartd|notify|reset <update|btrfs>]" >&2
    exit 1
    ;;
esac
