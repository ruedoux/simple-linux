#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
. "${TOOLSET_SCRIPT_DIR}/global.sh"

create_alert() {
  local alert_dir="$1"
  local alert_message="$2"
  local time_stamp
  time_stamp=$(date +"%Y-%m-%d_%H-%M-%S-%3N")
  local alert_file="$alert_dir/$time_stamp.alert"

  mkdir -p "$alert_dir"
  printf "%b" "$alert_message" > "$alert_file"
}

send_notify() {
  local title="$1"
  local message="$2"
  local urgency="${3:-normal}"

  echo -e "${GREEN}[NOTIFY]${RESET} ${message}"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
  fi
}

list_alerts() {
  local alert_dir="$1"

  mkdir -p "$alert_dir"
  shopt -s nullglob

  local alerts=("$alert_dir"/*.alert)
  if [ ${#alerts[@]} -eq 0 ]; then
    info "No alerts found."
    echo
    return
  fi

  for alert in "${alerts[@]}"; do
    echo -e "${RED}$(basename "$alert")${RESET}"
    cat "$alert"
    echo
  done
}

remind() {
  local last_reminder_file="$1"
  local remind_seconds="$2"
  local reminder_content="$3"

  if ! [[ "$remind_seconds" =~ ^[0-9]+$ ]] || [ "$remind_seconds" -le 0 ]; then
    error "seconds must be a positive integer"
    exit 1
  fi

  local seconds_epoch
  seconds_epoch=$(date +%s)

  if [ ! -f "$last_reminder_file" ]; then
    echo "$seconds_epoch" > "$last_reminder_file"
    info "Reminder will trigger every $remind_seconds seconds"
  fi

  local last_reminder_epoch
  last_reminder_epoch=$(cat "$last_reminder_file")
  if [ $((seconds_epoch - last_reminder_epoch)) -ge "$remind_seconds" ]; then
    send_notify "Reminder" "$reminder_content"
    echo "$seconds_epoch" > "$last_reminder_file"
  fi
}

cmd_create_alert() {
  local SCRIPT_NAME
  SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
  local alert_dir=""
  local alert_message=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dir)
        alert_dir="$2"
        shift 2
        ;;
      -m|--message)
        alert_message="$2"
        shift 2
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

  if [[ -z "$alert_dir" || -z "$alert_message" ]]; then
    echo "Usage: $SCRIPT_NAME create-alert -d <dir> -m <message>"
    return 1
  fi

  create_alert "$alert_dir" "$alert_message"
}

cmd_list_alerts() {
  local SCRIPT_NAME
  SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
  local alert_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dir)
        alert_dir="$2"
        shift 2
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

  if [[ -z "$alert_dir" ]]; then
    echo "Usage: $SCRIPT_NAME list-alerts -d <dir>"
    return 1
  fi

  list_alerts "$alert_dir"
}

cmd_remind() {
  local SCRIPT_NAME
  SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
  local remind_file=""
  local remind_seconds=""
  local remind_content=""
  local remind_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file)
        remind_file="$2"
        shift 2
        ;;
      -s|--seconds)
        remind_seconds="$2"
        shift 2
        ;;
      -c|--content)
        remind_content="$2"
        shift 2
        ;;
      -d|--dir)
        remind_dir="$2"
        shift 2
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

  # Dir-only mode: list all state files
  if [[ -n "$remind_dir" && -z "$remind_file" && -z "$remind_seconds" && -z "$remind_content" ]]; then
    mkdir -p "$remind_dir"
    shopt -s nullglob
    local state_files=("$remind_dir"/*)
    if [ ${#state_files[@]} -eq 0 ]; then
      info "No active reminders found."
      echo
    else
      for f in "${state_files[@]}"; do
        echo -e "${RED}$(basename "$f")${RESET} — $(cat "$f")"
      done
    fi
    return
  fi

  if [[ -z "$remind_file" || -z "$remind_seconds" || -z "$remind_content" ]]; then
    echo "Usage: $SCRIPT_NAME remind -f <file> -s <seconds> -c <content>"
    echo "       $SCRIPT_NAME remind -d <dir>"
    return 1
  fi

  remind "$remind_file" "$remind_seconds" "$remind_content"
}


cmd_send_notify() {
  local SCRIPT_NAME
  SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
  local title=""
  local message=""
  local urgency="normal"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--title)
        title="$2"
        shift 2
        ;;
      -m|--message)
        message="$2"
        shift 2
        ;;
      -u|--urgency)
        urgency="$2"
        shift 2
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

  if [[ -z "$title" || -z "$message" ]]; then
    echo "Usage: $SCRIPT_NAME send-notify -t <title> -m <message> [-u <urgency>]"
    return 1
  fi

  send_notify "$title" "$message" "$urgency"
}

cmd_setup_smartd() {
  local alerts_dir="${TOOLSET_SCRIPT_DIR}/alerts"
  local email=""
  local smartd_conf="/etc/smartd.conf"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dir)
        alerts_dir="$2"
        shift 2
        ;;
      -e|--email)
        email="$2"
        shift 2
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

  local script_path
  script_path="$(realpath "${BASH_SOURCE[0]}")"
  local abs_alerts_dir
  abs_alerts_dir="$(realpath -m "$alerts_dir")"

  local email_flag=""
  if [[ -n "$email" ]]; then
    email_flag="-m $email "
  fi

  local exec_line="DEVICESCAN ${email_flag}-M exec $script_path create-alert -d $abs_alerts_dir -m \"Fail type: \$SMARTD_FAILTYPE\n\$SMARTD_MESSAGE\""
  if [[ ! -f "$smartd_conf" ]]; then
    error "$smartd_conf not found. Is smartd installed?"
    return 1
  fi

  if grep -qF "$script_path create-alert" "$smartd_conf"; then
    info "smartd.conf already contains an entry for this script. Replacing it."
    sudo sed -i "\|$script_path create-alert|d" "$smartd_conf"
  fi

  echo "$exec_line" | sudo tee -a "$smartd_conf" > /dev/null
  info "Added to $smartd_conf:"
  echo "  $exec_line"
  echo
  info "Restart smartd to apply: sudo systemctl restart smartd"
}

case "$1" in
  create-alert)
    shift
    cmd_create_alert "$@"
    ;;
  list-alerts)
    shift
    cmd_list_alerts "$@"
    ;;
  remind)
    shift
    cmd_remind "$@"
    ;;
  send-notify)
    shift
    cmd_send_notify "$@"
    ;;
  setup-smartd)
    shift
    cmd_setup_smartd "$@"
    ;;
  *)
    echo "Usage: $SCRIPT_NAME [create-alert|list-alerts|remind|send-notify|setup-smartd]"
    exit 1
    ;;
esac
