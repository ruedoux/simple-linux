#!/usr/bin/env bash
set -euo pipefail

# sl-notifications — persistent desktop notifications for simple-linux.
#
#   set <name> <interval> <msg...>   create/override a reminder and start its countdown
#   check                             echo the message of every due reminder (one per line)
#   notify                            (user) send due reminders + smartd alerts as notifications
#   reset <name>                      reset a reminder's countdown (last = now)
#   remove <name>                     delete a reminder
#   list                              show all reminders and when they will next fire
#   check-update                      (read-only) notify if a repo update is available
#
# Each reminder is one file <name>.stamp under NOTIFY_ALERTS_DIR:
#   last: <epoch-seconds>       when the countdown started / was last reset
#   interval: <seconds>         how long to wait before the reminder fires
#   msg: <text>                 message shown when the reminder is due
#
# smartd's "-M exec" runs this script with no arguments (SMARTD_* env set),
# which writes a disk-failure .alert file.

if [ -f /etc/simple-linux/settings.default.env ]; then
  # shellcheck disable=SC1091
  source /etc/simple-linux/settings.default.env
fi
if [ -f /etc/simple-linux/settings.env ]; then
  # shellcheck disable=SC1091
  source /etc/simple-linux/settings.env
fi

ALERTS_DIR="${NOTIFY_ALERTS_DIR:-/var/lib/simple-linux/alerts}"

usage() {
  echo "Usage: sl-notifications [set <name> <interval> <msg...>|check|notify|reset <name>|remove <name>|list|check-update]" >&2
}

have_notify_send() {
  command -v notify-send >/dev/null 2>&1
}

send_notification() {
  local urgency="$1" title="$2" body="${3:-}"
  if [ -n "$body" ]; then
    notify-send -u "$urgency" "$title" "$body" 2>/dev/null || true
  else
    notify-send -u "$urgency" "$title" 2>/dev/null || true
  fi
}

ensure_alerts_dir() {
  mkdir -p "$ALERTS_DIR"
  chmod 0755 "$ALERTS_DIR" 2>/dev/null || true
}

valid_name() {
  [ -n "$1" ] && [[ "$1" != */* ]]
}

stamp_last()     { sed -n 's/^last: //p' "$1"; }
stamp_interval() { sed -n 's/^interval: //p' "$1"; }
stamp_msg()      { sed -n 's/^msg: //p' "$1"; }

is_due() {
  local name="$1"
  local f="$ALERTS_DIR/$name.stamp"
  [ -f "$f" ] || return 1

  local last interval now
  last="$(stamp_last "$f")"
  interval="$(stamp_interval "$f")"
  [[ "$last" =~ ^[0-9]+$ ]] || return 1
  [[ "$interval" =~ ^[0-9]+$ ]] || return 1

  now="$(date +%s)"
  [ $((now - last)) -ge "$interval" ]
}

check() {
  shopt -s nullglob
  local files=("$ALERTS_DIR"/*.stamp)
  shopt -u nullglob

  local f msg
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    if is_due "$(basename "$f" .stamp)"; then
      msg="$(stamp_msg "$f")"
      [ -n "$msg" ] && printf '%s\n' "$msg"
    fi
  done
}

notify() {
  have_notify_send || return 0

  local msg
  while IFS= read -r msg; do
    [ -n "$msg" ] && send_notification normal "$msg"
  done < <(check)

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

set_stamp() {
  local name="${1:-}" interval="${2:-}"

  valid_name "$name" || { usage; exit 1; }
  [[ "$interval" =~ ^[0-9]+$ ]] || { echo "error: interval must be a positive number of seconds" >&2; exit 1; }

  shift 2
  local msg="$*"
  [ -n "$msg" ] || { usage; exit 1; }

  ensure_alerts_dir
  local f="$ALERTS_DIR/$name.stamp"
  {
    printf 'last: %s\n' "$(date +%s)"
    printf 'interval: %s\n' "$interval"
    printf 'msg: %s\n' "$msg"
  } > "$f"
  chmod 0644 "$f" 2>/dev/null || true
}

reset_stamp() {
  local name="${1:-}"

  valid_name "$name" || { usage; exit 1; }

  local f="$ALERTS_DIR/$name.stamp"
  [ -f "$f" ] || { echo "error: no reminder '$name' — use 'set' first" >&2; exit 1; }

  local interval msg
  interval="$(stamp_interval "$f")"
  msg="$(stamp_msg "$f")"

  {
    printf 'last: %s\n' "$(date +%s)"
    printf 'interval: %s\n' "$interval"
    printf 'msg: %s\n' "$msg"
  } > "$f"
  chmod 0644 "$f" 2>/dev/null || true
}

remove_stamp() {
  local name="${1:-}"

  valid_name "$name" || { usage; exit 1; }
  rm -f "$ALERTS_DIR/$name.stamp"
}

list_stamps() {
  local now
  now="$(date +%s)"

  printf '%-12s  %-10s  %-19s  %-19s  %s\n' \
    "REMINDER" "INTERVAL" "LAST SET" "NEXT FIRE" "STATUS"

  shopt -s nullglob
  local files=("$ALERTS_DIR"/*.stamp)
  shopt -u nullglob

  local f name last interval next status
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue

    name="$(basename "$f" .stamp)"
    last="$(stamp_last "$f")"
    interval="$(stamp_interval "$f")"
    [[ "$last" =~ ^[0-9]+$ ]] || continue
    [[ "$interval" =~ ^[0-9]+$ ]] || continue

    next=$((last + interval))
    if [ "$now" -ge "$next" ]; then status="due"; else status="ok"; fi

    printf '%-12s  %-10s  %-19s  %-19s  %s\n' \
      "$name" "$interval" \
      "$(date -d "@$last" '+%Y-%m-%d %H:%M:%S')" \
      "$(date -d "@$next" '+%Y-%m-%d %H:%M:%S')" \
      "$status"
  done
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

case "${1:-}" in
  set)
    shift
    set_stamp "$@"
    ;;
  check)
    check
    ;;
  notify)
    notify
    ;;
  reset)
    shift
    reset_stamp "${1:-}"
    ;;
  remove)
    shift
    remove_stamp "${1:-}"
    ;;
  list)
    list_stamps
    ;;
  check-update)
    check_update
    ;;
  *)
    # smartd "-M exec" runs this script with no subcommand, SMARTD_* env set.
    if [ -n "${SMARTD_MESSAGE:-}" ]; then
      smartd_alert
      exit 0
    fi
    usage
    exit 1
    ;;
esac
