#!/usr/bin/env bash
set -euo pipefail

SETUP_SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
export SETUP_SCRIPT_DIR

source "$SETUP_SCRIPT_DIR/settings.env"
source "$SETUP_SCRIPT_DIR/.lib.sh"

verify_checked

collect_passwords
echo "Target disk: ${DRIVE} — will be wiped."
lsblk -o NAME,SIZE,MODEL,TYPE "$DRIVE" 2>/dev/null || true
echo ""
"$SETUP_SCRIPT_DIR/scripts/arch-install.sh"
