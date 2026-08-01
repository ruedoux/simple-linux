#!/usr/bin/env bash

set -euo pipefail

. "${TOOLSET_SCRIPT_DIR}/global.sh"

DEFAULT_DOCKER_PATH="${SL_CONTAINERS_DIR:-}"
OPENCODE_VERSION="1.18.4"
IMAGE="opencode-custom:$OPENCODE_VERSION"
BUILD=false

WORKSPACE="${WORKSPACE:-$(pwd)}"
WORKSPACE="$(realpath "$WORKSPACE")"

OPENCODE_CONFIG="${OPENCODE_CONFIG:-${SL_OPENCODE_DIR:-}}"
OPENCODE_CACHE="${OPENCODE_CACHE:-${SL_CONTAINERS_PERSISTENT_DIR:-}/opencode/cache}"
OPENCODE_SHARE="${OPENCODE_SHARE:-${SL_CONTAINERS_PERSISTENT_DIR:-}/opencode/share}"
OPENCODE_STATE="${OPENCODE_STATE:-${SL_CONTAINERS_PERSISTENT_DIR:-}/opencode/state}"

mkdir -p $OPENCODE_CONFIG
mkdir -p $OPENCODE_CACHE
mkdir -p $OPENCODE_SHARE
mkdir -p $OPENCODE_STATE

if [[ "${1:-}" == "--build" ]]; then
  BUILD=true
fi

if [[ "$BUILD" == true ]]; then
  nerdctl build -f $DEFAULT_DOCKER_PATH/opencode.Dockerfile \
    --build-arg OPENCODE_VERSION=$OPENCODE_VERSION \
    -t "$IMAGE" \
    $DEFAULT_DOCKER_PATH
fi

validate_opencode_paths() {
    [[ -n "${DEFAULT_DOCKER_PATH:-}" ]] || { error "SL_CONTAINERS_DIR not set. Add it to ${SL_CONFIG_PATH:-config.env}"; return 1; }
    [[ -n "${OPENCODE_CONFIG:-}" ]] || { error "SL_OPENCODE_DIR not set. Add it to ${SL_CONFIG_PATH:-config.env}"; return 1; }
    [[ -n "${SL_CONTAINERS_PERSISTENT_DIR:-}" ]] || { error "SL_CONTAINERS_PERSISTENT_DIR not set. Add it to ${SL_CONFIG_PATH:-config.env}"; return 1; }
}
validate_opencode_paths || exit 1

nerdctl run --rm -it \
  --net internet \
  -v "$WORKSPACE:/workspace" \
  -v "$OPENCODE_CONFIG:/root/.config/opencode" \
  -v "$OPENCODE_CACHE:/root/.cache/opencode" \
  -v "$OPENCODE_SHARE:/root/.local/share/opencode" \
  -v "$OPENCODE_STATE:/root/.local/state/opencode" \
  -w /workspace \
  "$IMAGE"
