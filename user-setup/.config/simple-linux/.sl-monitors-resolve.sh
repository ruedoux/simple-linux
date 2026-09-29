#!/usr/bin/env bash
set -euo pipefail

_get_biggest_monitor() {
  hyprctl monitors -j \
    | jq '[.[] | { name, width, height, refreshRate }]' \
    | jq -r 'max_by(.width * .height) | .name'
}

monitors_resolve() {
  local SL_ROOT_DIR
  SL_ROOT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
  # shellcheck disable=SC1090
  source "$SL_ROOT_DIR/.sl-lib.sh"

  # Load config (non-fatal if either file is missing): managed defaults first,
  # then user overrides.
  set -a
  if [ -f "$SL_ROOT_DIR/config.default.env" ]; then
    # shellcheck disable=SC1091
    source "$SL_ROOT_DIR/config.default.env"
  fi
  if [ -f "$SL_ROOT_DIR/config.env" ]; then
    # shellcheck disable=SC1091
    source "$SL_ROOT_DIR/config.env"
  fi
  set +a

  # --- Parse monitor order from config (format: NAME[:SCALE][:DIRECTION]) ---
  local -a monitor_order=()
  declare -A mon_scale mon_direction
  if [ -n "${SL_MONITOR_ORDER:-}" ]; then
    IFS=',' read -ra monitor_order_raw <<< "$SL_MONITOR_ORDER"
    for entry in "${monitor_order_raw[@]}"; do
      local trimmed
      trimmed="$(echo "$entry" | xargs)"
      [ -z "$trimmed" ] && continue

      local name scale direction
      name=$(echo "$trimmed" | awk -F: '{print $1}')
      scale=$(echo "$trimmed" | awk -F: '{print $2}')
      direction=$(echo "$trimmed" | awk -F: '{print $3}')
      scale="${scale:-1}"
      direction="${direction:-right}"

      monitor_order+=("$name")
      mon_scale["$name"]="$scale"
      mon_direction["$name"]="$direction"
    done
  fi

  # --- Query hyprctl for connected monitors ---
  local monitors_json
  if ! monitors_json=$(hyprctl monitors -j 2>/dev/null); then
    log_err "Failed to query hyprctl monitors. Is Hyprland running?"
    return 1
  fi

  if [ "$(echo "$monitors_json" | jq 'length')" -eq 0 ]; then
    log_err "No monitors detected by hyprctl."
    return 1
  fi

  # --- Auto-detect order if empty ---
  if [ ${#monitor_order[@]} -eq 0 ]; then
    while IFS= read -r name; do
      monitor_order+=("$name")
      mon_scale["$name"]="1"
      mon_direction["$name"]="right"
    done < <(echo "$monitors_json" | jq -r '.[].name')
    log_start "Auto-detected monitor order: ${monitor_order[*]}"
  fi

  # --- Resolve main monitor ---
  local main_monitor="${SL_MAIN_MONITOR:-}"
  if [ -z "$main_monitor" ]; then
    main_monitor="$(_get_biggest_monitor)"
  fi

  # --- Generate monitor blocks (first = 0x0, rest = auto-center-<direction>) ---
  local monitor_blocks=""
  local is_first=1

  for mon in "${monitor_order[@]}"; do
    local w h r s
    w=$(echo "$monitors_json" | jq -r --arg name "$mon" '.[] | select(.name == $name) | .width // empty')
    h=$(echo "$monitors_json" | jq -r --arg name "$mon" '.[] | select(.name == $name) | .height // empty')
    r=$(echo "$monitors_json" | jq -r --arg name "$mon" '.[] | select(.name == $name) | .refreshRate // empty')
    s="${mon_scale[$mon]:-1}"

    if [ -z "$w" ] || [ "$w" = "null" ]; then
      log_warn "Monitor '$mon' not found in hyprctl output — skipping."
      continue
    fi

    local pos
    if [ "$is_first" -eq 1 ]; then
      pos="0x0"
      is_first=0
    else
      local dir="${mon_direction[$mon]:-right}"
      pos="auto-center-${dir}"
    fi

    monitor_blocks+="hl.monitor({"$'\n'
    monitor_blocks+="  output = \"$mon\","$'\n'
    monitor_blocks+="  mode = \"${w}x${h}@${r}\","$'\n'
    monitor_blocks+="  position = \"$pos\","$'\n'
    monitor_blocks+="  scale = \"$s\","$'\n'
    monitor_blocks+="})"$'\n'
    monitor_blocks+=$'\n'
  done

  monitor_blocks="${monitor_blocks%"$'\n'"}"

  # --- Generate workspace blocks ---
  local workspace_count="${SL_WORKSPACE_COUNT}"
  if ! [[ "$workspace_count" =~ ^[0-9]+$ ]] || [ "$workspace_count" -lt 1 ]; then
    log_err "SL_WORKSPACE_COUNT must be a positive integer, got '$workspace_count'"
    return 1
  fi

  local workspace_blocks=""
  for ws in $(seq 1 "$workspace_count"); do
    workspace_blocks+="hl.workspace_rule({ workspace = \"$ws\", monitor = \"$main_monitor\" })"$'\n'
  done
  workspace_blocks="${workspace_blocks%"$'\n'"}"

  # --- Generate hyprpaper blocks ---
  local hyprpaper_blocks=""
  for mon in "${monitor_order[@]}"; do
    hyprpaper_blocks+="wallpaper {"$'\n'
    hyprpaper_blocks+="  monitor = $mon"$'\n'
    hyprpaper_blocks+="  path = ~/.config/simple-linux/files/wallpaper.png"$'\n'
    hyprpaper_blocks+="  fit_mode = cover"$'\n'
    hyprpaper_blocks+="}"$'\n'
    hyprpaper_blocks+=$'\n'
  done

  # Export blocks for the template renderer (sl-controller.sh _render_templates)
  export SL_MONITOR_BLOCKS="$monitor_blocks"
  export SL_WORKSPACE_BLOCKS="$workspace_blocks"
  export SL_HYPRPAPER_BLOCKS="$hyprpaper_blocks"
  log_ok "Resolved monitors (${#monitor_order[@]} monitor(s): ${monitor_order[*]}, primary: $main_monitor)"
}

# Allow both sourcing and direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  monitors_resolve "$@"
fi
