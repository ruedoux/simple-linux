#!/usr/bin/env bash
set -euo pipefail

# sl-remind-notifications — persistent desktop notifications for simple-linux.
#
#   notify                                  (user) show due reminders + smartd alerts
#   set <name> [seconds] [title] [body]     create/override a reminder and start its countdown
#   set update|btrfs                        reset a built-in reminder's countdown
#   remove <name>                           delete a reminder (built-ins revert to default)
#   check-update                            (read-only) notify if a repo update is available
#   list                                    show reminders and when they will next fire
#
# smartd's "-M exec" runs this script with no arguments (SMARTD_* env set),
# which writes a disk-failure .alert file.
#
# Built-ins: weekly "update" and monthly "btrfs". User reminders are stored as
# <name>.reminder (interval/title/body) plus <name>.stamp (last-set time) under
# NOTIFY_ALERTS_DIR.

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

have_notify_send() {
  command -v notify-send >/dev/null 2>&1
}

send_notification() {
  local urgency="$1" title="$2" body="$3"
  notify-send -u "$urgency" "$title" "$body" 2>/dev/null || true
}

ensure_alerts_dir() {
  mkdir -p "$ALERTS_DIR"
  chmod 0755 "$ALERTS_DIR" 2>/dev/null || true
}

valid_name() {
  [ -n "$1" ] && [[ "$1" != */* ]]
}

remind() {
  local name="$1" interval="$2" title="$3" body="$4"
  local stamp="$ALERTS_DIR/${name}.stamp"

  [ -f "$stamp" ] || return 0

  local now last
  now="$(date +%s)"
  last="$(cat "$stamp")"

  if [ $((now - last)) -ge "$interval" ]; then
    send_notification normal "$title" "$body"
  fi
}

remind_builtin() {
  local name="$1" interval="$2" title="$3" body="$4"
  [ -f "$ALERTS_DIR/${name}.reminder" ] && return 0
  remind "$name" "$interval" "$title" "$body"
}

notify() {
  have_notify_send || return 0

  remind_builtin "update" "$UPDATE_INTERVAL" "System update" "Update the system and run a backup."
  remind_builtin "btrfs" "$BTRFS_INTERVAL" "Btrfs health check" "Run a btrfs scrub and health check."

  shopt -s nullglob
  local defs=("$ALERTS_DIR"/*.reminder)
  shopt -u nullglob

  local f name interval title body
  for f in "${defs[@]}"; do
    [ -f "$f" ] || continue

    name="$(basename "$f" .reminder)"
    interval="$(head -n 1 "$f")"
    title="$(sed -n '2p' "$f")"
    body="$(tail -n +3 "$f")"
    [ -n "$body" ] || body="$title"

    remind "$name" "$interval" "$title" "$body"
  done

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

    send_notification "$urgency" "$title" "$body"
  done
}

print_reminder_row() {
  local name="$1" interval="$2" now="$3"
  local stamp="$ALERTS_DIR/${name}.stamp"
  local last next last_h next_h status

  if [ -f "$stamp" ]; then
    last="$(cat "$stamp")"
    next=$((last + interval))
    last_h="$(date -d "@$last" '+%Y-%m-%d %H:%M:%S')"
    next_h="$(date -d "@$next" '+%Y-%m-%d %H:%M:%S')"
    if [ "$now" -ge "$next" ]; then
      status="due"
    else
      status="ok"
    fi
  else
    last_h="-"
    next_h="never"
    status="n/a"
  fi

  printf '%-12s  %-10s  %-19s  %-19s  %s\n' \
    "$name" "$interval" "$last_h" "$next_h" "$status"
}

list_reminders() {
  local now
  now="$(date +%s)"

  printf '%-12s  %-10s  %-19s  %-19s  %s\n' \
    "REMINDER" "INTERVAL" "LAST SET" "NEXT DUE" "STATUS"

  [ -f "$ALERTS_DIR/update.reminder" ] || print_reminder_row "update" "$UPDATE_INTERVAL" "$now"
  [ -f "$ALERTS_DIR/btrfs.reminder" ] || print_reminder_row "btrfs" "$BTRFS_INTERVAL" "$now"

  shopt -s nullglob
  local defs=("$ALERTS_DIR"/*.reminder)
  shopt -u nullglob

  local f name interval
  for f in "${defs[@]}"; do
    [ -f "$f" ] || continue

    name="$(basename "$f" .reminder)"
    interval="$(head -n 1 "$f")"
    print_reminder_row "$name" "$interval" "$now"
  done
}

set_reminder() {
  local name="$1" interval="$2" title="$3" body="${4:-}"
  local def stamp

  valid_name "$name" || { echo "Usage: sl-remind-notifications set <name> [seconds] [title] [body]" >&2; exit 1; }

  # `set <builtin>` with no definition args only resets the countdown stamp.
  if [ -z "$interval" ] && [ -z "$title" ]; then
    case "$name" in
      update|btrfs) ;;
      *) echo "Usage: sl-remind-notifications set <name> [seconds] [title] [body]" >&2; exit 1 ;;
    esac
    ensure_alerts_dir
    stamp="$ALERTS_DIR/${name}.stamp"
    printf '%s\n' "$(date +%s)" > "$stamp"
    chmod 0644 "$stamp" 2>/dev/null || true
    return 0
  fi

  [[ "$interval" =~ ^[0-9]+$ ]] || { echo "error: interval must be a positive number of seconds" >&2; exit 1; }
  [ -n "$title" ] || { echo "Usage: sl-remind-notifications set <name> [seconds] [title] [body]" >&2; exit 1; }

  ensure_alerts_dir
  def="$ALERTS_DIR/${name}.reminder"
  stamp="$ALERTS_DIR/${name}.stamp"

  {
    printf '%s\n' "$interval"
    printf '%s\n' "$title"
    printf '%s\n' "${body:-$title}"
  } > "$def"
  chmod 0644 "$def" 2>/dev/null || true

  printf '%s\n' "$(date +%s)" > "$stamp"
  chmod 0644 "$stamp" 2>/dev/null || true
}

remove_reminder() {
  local name="$1"

  valid_name "$name" || { echo "Usage: sl-remind-notifications remove <name>" >&2; exit 1; }

  rm -f "$ALERTS_DIR/${name}.reminder" "$ALERTS_DIR/${name}.stamp"
}

smartd_alert() {
  local device="${SMARTD_DEVICESTRING:-${SMARTD_DEVICE:-unknown}}"
  local fail_type="${SMARTD_FAILTYPE:-unknown}"
  local message="${SMARTD_MESSAGE:-No SMARTD_MESSAGE provided}"
  local timestamp
  timestamp="$(date +"%Y-%m-%d_%H-%M-%S-%3N")"

  ensure_alerts_dir

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
  have_notify_send || return 0

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
    send_notification normal "simple-linux update available" \
      "A new version is available — run 'sudo sl-system-sync' to update."
  fi
}

case "${1:-}" in
  check-update)
    check_update
    ;;
  notify)
    notify
    ;;
  list)
    list_reminders
    ;;
  set)
    set_reminder "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    ;;
  remove)
    remove_reminder "${2:-}"
    ;;
  *)
    # smartd "-M exec" runs this script with no subcommand, SMARTD_* env set.
    if [ -n "${SMARTD_MESSAGE:-}" ]; then
      smartd_alert
      exit 0
    fi
    echo "Usage: sl-remind-notifications [check-update|notify|list|set <name> [seconds] [title] [body]|remove <name>]" >&2
    exit 1
    ;;
esac
