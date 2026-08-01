#!/bin/bash
set -euo pipefail

# Standalone sudo command — sources system-wide truth from /etc
# Installed to /usr/local/bin/sl-system-health during USB setup.
# Reports system health status. Read-only — never modifies the system.

source /etc/simple-linux/settings.env
source /etc/simple-linux/lib.sh

PASS=0
FAIL=0
WARN=0
SKIP=0

check_pass() { log_ok "$1"; PASS=$((PASS+1)); }
check_fail() { log_err "$1"; FAIL=$((FAIL+1)); }
check_warn() { log_warn "$1"; WARN=$((WARN+1)); }
check_skip() { echo -e "  ~ $1"; SKIP=$((SKIP+1)); }

section() { echo ""; echo -e "${BOLD}── $1 ──${RESET}"; }

in_wheel() {
  [[ $EUID -eq 0 ]] && return 0
  groups "$USER" 2>/dev/null | grep -q '\bwheel\b'
}

need_sudo() {
  if [ "${HAS_SUDO:-}" == "true" ]; then
    return 0
  fi
  check_skip "$1"
  return 1
}

preflight() {
  echo -e "${BOLD}  s l   h e a l t h${RESET}"
  echo "======================="

  if in_wheel; then
    HAS_SUDO=true
  else
    HAS_SUDO=false
    echo ""
    check_warn "Some checks require sudo — run with a wheel account for full report"
    echo ""
  fi
}

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

check_btrfs() {
  if ! command -v btrfs &>/dev/null; then
    check_skip "Btrfs: btrfs tools not installed"
    return
  fi

  if ! need_sudo "Btrfs: checks require sudo"; then
    return
  fi

  # Scrub status
  if sudo btrfs scrub status / &>/dev/null; then
    local scrub_out
    scrub_out=$(sudo btrfs scrub status / 2>/dev/null || true)
    if echo "$scrub_out" | grep -q "no stats available"; then
      check_skip "Btrfs scrub: never run"
    elif echo "$scrub_out" | grep -q "ERROR"; then
      check_fail "Btrfs scrub: errors detected — run 'btrfs scrub start /'"
    else
      check_pass "Btrfs scrub: healthy"
    fi
  else
    check_skip "Btrfs scrub: / is not btrfs or not accessible"
  fi

  # Allocation / usage warning (suggests balance if heavily unbalanced)
  local usage_out
  usage_out=$(sudo btrfs fi usage / 2>/dev/null || true)
  if [ -n "$usage_out" ]; then
    # Check if any data/metadata is < 10% allocated reserved — a balance may help
    local alloc_warn=false
    if echo "$usage_out" | awk '/Device allocated/{found=1} found && /^[[:space:]]*$/ {exit}' | grep -E '^\s+Data' | awk '{print $4}' | grep -qE '^0|\.[0-9]+'; then
      alloc_warn=true
    fi
    if $alloc_warn; then
      check_warn "Btrfs: allocation may be unbalanced — consider running 'btrfs balance start /'"
    else
      check_pass "Btrfs allocation: looks healthy"
    fi
  fi
}

check_toolkit_deps() {
  local deps_str="${SL_TOOLSET_DEPS:-}"
  if [ -z "$deps_str" ]; then
    check_skip "Toolkit deps: SL_TOOLSET_DEPS not set in settings.env"
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

check_packages() {
  local expected=()

  # Always-installed base packages
  for var in PACKAGES OTHER_PACKAGES; do
    local -a pkgs
    read -ra pkgs <<< "${!var:-}"
    expected+=("${pkgs[@]}")
  done

  # Conditional: gaming
  if [[ "${ENABLE_GAMING:-}" == "true" ]]; then
    local -a pkgs
    read -ra pkgs <<< "${GAMING_PACKAGES:-}"
    expected+=("${pkgs[@]}")
  fi

  # Conditional: dev extras
  if [[ "${ENABLE_DEV_EXTRAS:-}" == "true" ]]; then
    local -a pkgs
    read -ra pkgs <<< "${DEV_EXTRA_PACKAGES:-}"
    expected+=("${pkgs[@]}")
  fi

  local missing=()
  for pkg in "${expected[@]}"; do
    [[ -z "$pkg" ]] && continue
    if ! pacman -Qi "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    check_pass "Packages: all ${#expected[@]} installed"
  else
    for m in "${missing[@]}"; do
      log_err "  - ${m}"
    done
    check_fail "Packages: ${#missing[@]}/${#expected[@]} missing — run 'sudo sl-system-sync'"
  fi
}

check_dangling() {
  echo ""
  log_step "Dangling pacman packages (pacman -Qtd)"
  local orphans
  orphans=$(pacman -Qtd 2>/dev/null | wc -l || true)
  if [ "$orphans" -eq 0 ]; then
    check_pass "Dangling packages: none"
  else
    pacman -Qtd 2>/dev/null
    check_warn "Dangling packages: ${orphans} found — review and remove with 'pacman -Rcns'"
  fi

  echo ""
  log_step "Broken symlinks (find / -xtype l)"

  # Exclude home directories and virtual filesystems
  local home_dirs
  home_dirs=$(awk -F: '{if($6 ~ /^\/home\// || $6 == "/root") print $6}' /etc/passwd | sort -u)
  local excludes
  excludes=$(printf '|%s' $home_dirs)
  excludes=${excludes:1}

  local broken
  if [ "${HAS_SUDO:-}" == "true" ]; then
    broken=$(sudo find / -path /dev -prune -o -path /proc -prune -o -path /run -prune -o -path /sys -prune -o -xtype l -print 2>/dev/null | grep -Ev "^($excludes)" || true)
  else
    broken=$(find / -path /dev -prune -o -path /proc -prune -o -path /run -prune -o -path /sys -prune -o -xtype l -print 2>/dev/null | grep -Ev "^($excludes)" || true)
    check_skip "Broken symlinks: running without sudo — results may be incomplete"
  fi

  if [ -z "$broken" ]; then
    check_pass "Broken symlinks: none found"
  else
    local tmpfile="/tmp/sl-health-broken-symlinks.txt"
    echo "$broken" > "$tmpfile"
    chmod 644 "$tmpfile"
    local count
    count=$(echo "$broken" | grep -c '^' || true)
    check_warn "Broken symlinks: ${count} found → ${tmpfile}"
  fi
}

print_summary() {
  echo ""
  echo -e "─────────────────────────"
  printf "  ${GREEN}passed: %d${RESET}   ${RED}failed: %d${RESET}   ${YELLOW}warned: %d${RESET}" "$PASS" "$FAIL" "$WARN"
  printf "   ${BLUE}skipped: %d${RESET}" "$SKIP"
  echo ""
  echo -e "─────────────────────────"
}

main() {
  preflight

  section "filesystem"
  check_disk_space

  section "btrfs"
  check_btrfs

  section "tools"
  check_toolkit_deps

  section "packages"
  check_packages

  section "dangling"
  check_dangling

  print_summary

  if [ "$FAIL" -gt 0 ]; then
    exit 1
  elif [ "$WARN" -gt 0 ]; then
    exit 2
  fi
  exit 0
}

main
