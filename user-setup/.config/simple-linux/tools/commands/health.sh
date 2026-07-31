#!/bin/bash
set -euo pipefail

. "${TOOLSET_SCRIPT_DIR}/global.sh"

PASS=0
FAIL=0
WARN=0
SKIP=0

# Bold is not defined in global.sh, define it here
BOLD='\033[1m'

# ── Output helpers ───────────────────────────────────────────────────────────

# Use $((VAR+1)) instead of ((VAR++)) because ((0++)) returns exit code 1,
# which would abort the script under 'set -e'.
check_pass() { echo -e "  ${GREEN_COLOR}✓${NO_COLOR}  $1"; PASS=$((PASS+1)); }
check_fail() { echo -e "  ${RED_COLOR}✗${NO_COLOR}  $1"; FAIL=$((FAIL+1)); }
check_warn() { echo -e "  ${PURPLE_COLOR}⚠${NO_COLOR}  $1"; WARN=$((WARN+1)); }
check_skip() { echo -e "  ${BLUE_COLOR}~${NO_COLOR}  $1"; SKIP=$((SKIP+1)); }

section() { echo ""; echo -e "${BOLD}── $1 ──${NO_COLOR}"; }

in_wheel() {
  groups "$USER" 2>/dev/null | grep -q '\bwheel\b'
}

# ── Filesystem ───────────────────────────────────────────────────────────────

check_disk_space() {
  local paths=("/" "/home" "/var/log")
  local warn_threshold=85
  local all_ok=true
  local p usage

  for p in "${paths[@]}"; do
    if ! df "$p" &>/dev/null; then
      check_warn "Disk $p: not mounted or inaccessible"
      all_ok=false
      continue
    fi

    usage=$(df -h "$p" | awk 'NR==2 {print $5}' | tr -d '%')

    if [ "$usage" -ge "$warn_threshold" ]; then
      check_warn "Disk $p: ${usage}% used"
      all_ok=false
    fi
  done

  if $all_ok; then
    check_pass "Disk space: all mountpoints below ${warn_threshold}%"
  fi
}

# ── Tools ────────────────────────────────────────────────────────────────────

check_toolkit_deps() {
  local deps_str="${SL_TOOLSET_DEPS:-}"
  if [ -z "$deps_str" ]; then
    check_skip "Toolkit deps: SL_TOOLSET_DEPS not set in config.env"
    return
  fi

  local -a deps
  read -ra deps <<< "$deps_str"
  local missing=()
  local d

  for d in "${deps[@]}"; do
    if ! command -v "$d" &>/dev/null; then
      missing+=("$d")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    check_pass "Toolkit deps: all ${#deps[@]} available (${deps[*]})"
  else
    local present=$(( ${#deps[@]} - ${#missing[@]} ))
    check_fail "Toolkit deps: ${present}/${#deps[@]} available, missing: ${missing[*]}"
  fi
}

# ── System Settings Consistency ──────────────────────────────────────────────

check_settings_consistency() {
  if [ -z "${ENABLE_DEV_EXTRAS:-}" ] && [ -z "${ENABLE_GAMING:-}" ]; then
    check_skip "settings.env: not found, skipping consistency checks"
    return
  fi

  local ok=true

  if [[ "${ENABLE_DEV_EXTRAS:-}" == "true" ]]; then
    command -v nerdctl &>/dev/null || { check_warn "ENABLE_DEV_EXTRAS=true but nerdctl not installed"; ok=false; }
    command -v dotnet &>/dev/null  || { check_warn "ENABLE_DEV_EXTRAS=true but dotnet not installed";  ok=false; }
  fi

  if [[ "${ENABLE_GAMING:-}" == "true" ]]; then
    command -v steam &>/dev/null || { check_warn "ENABLE_GAMING=true but steam not installed"; ok=false; }
  fi

  if $ok; then
    check_pass "settings.env: all declared features consistent"
  fi
}

# ── User Environment ─────────────────────────────────────────────────────────

check_config_env() {
  local cfg="${SL_CONFIG_PATH:-}"
  if [ -z "$cfg" ] || [ ! -f "$cfg" ]; then
    check_fail "config.env: not found at ${cfg:-SL_CONFIG_PATH not set}"
    return
  fi

  local required=("SL_FONT" "SL_TERMINAL" "SL_THEME_MODE" "SL_MAIN_MONITOR")
  local missing=()

  for var in "${required[@]}"; do
    if [ -z "${!var:-}" ]; then
      missing+=("$var")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    check_pass "config.env: all required variables set"
  else
    check_fail "config.env: missing ${missing[*]}"
  fi
}

check_dotfiles() {
  local home="${HOME:-}"
  local files=(
    "$home/.config/hypr/hyprland.lua"
    "$home/.config/nvim/init.lua"
    "$home/.config/kitty/kitty.conf"
  )
  local missing=()

  for f in "${files[@]}"; do
    [ -f "$f" ] || missing+=("$(basename "$(dirname "$f")")/$(basename "$f")")
  done

  if [ ${#missing[@]} -eq 0 ]; then
    check_pass "dotfiles: key configs present (hyprland, nvim, kitty)"
  else
    check_fail "dotfiles: missing ${missing[*]}"
  fi
}

check_pyenv() {
  if ! command -v pyenv &>/dev/null; then
    check_skip "pyenv: not installed"
    return
  fi

  local configured="${SL_PYENV_PYTHON_VER:-}"
  if [ -z "$configured" ]; then
    check_warn "pyenv: SL_PYENV_PYTHON_VER not set in config.env"
    return
  fi

  local current
  current=$(pyenv version 2>/dev/null | awk '{print $1}' || true)

  if [ -z "$current" ]; then
    check_warn "pyenv: no global Python version set"
    return
  fi

  # Compare prefix (e.g. configured "3.12" matches "3.12" and "3.12.4")
  if [[ "$current" == "$configured" || "$current" == "$configured".* ]]; then
    check_pass "pyenv: Python $current matches configured $configured"
  else
    check_fail "pyenv: Python $current does not match configured $configured"
  fi
}

# ── Summary ──────────────────────────────────────────────────────────────────

print_summary() {
  echo ""
  echo -e "─────────────────────────"
  printf "  ${GREEN_COLOR}passed: %d${NO_COLOR}   ${RED_COLOR}failed: %d${NO_COLOR}   ${PURPLE_COLOR}warned: %d${NO_COLOR}" "$PASS" "$FAIL" "$WARN"
  printf "   ${BLUE_COLOR}skipped: %d${NO_COLOR}" "$SKIP"
  echo ""
  echo -e "─────────────────────────"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  echo -e "${BOLD}  s l   h e a l t h${NO_COLOR}"
  echo "======================="

  section "filesystem"
  check_disk_space

  section "tools"
  check_toolkit_deps

  section "system"
  check_settings_consistency

  section "user"
  check_config_env
  check_dotfiles
  check_pyenv

  print_summary

  if [ "$FAIL" -gt 0 ]; then
    exit 1
  elif [ "$WARN" -gt 0 ]; then
    exit 2
  fi
  exit 0
}

main
