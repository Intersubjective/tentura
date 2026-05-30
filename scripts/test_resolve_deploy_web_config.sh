#!/usr/bin/env bash
# Tests for scripts/resolve_deploy_web_config.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVE="${ROOT}/scripts/resolve_deploy_web_config.sh"

run_ok() {
  local desc="$1"
  shift
  if "$@"; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc" >&2
    exit 1
  fi
}

run_fail() {
  local desc="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "FAIL: expected failure — $desc" >&2
    exit 1
  else
    echo "OK: $desc (failed as expected)"
  fi
}

# --- missing required ---
run_fail "missing CLIENT_SERVER_NAME" \
  env -u CLIENT_SERVER_NAME IMAGE_SERVER=https://cdn.example/bucket \
  bash "$RESOLVE" --check-only

run_fail "missing IMAGE_SERVER" \
  env CLIENT_SERVER_NAME=https://app.dev.tentura.io IMAGE_SERVER= \
  bash "$RESOLVE" --check-only

# --- invalid URLs ---
run_fail "invalid IMAGE_SERVER" \
  env CLIENT_SERVER_NAME=https://app.dev.tentura.io IMAGE_SERVER=not-a-url \
  bash "$RESOLVE" --check-only

run_fail "path-only CLIENT_SERVER_NAME" \
  env CLIENT_SERVER_NAME=/invite/foo IMAGE_SERVER=https://cdn.example/bucket \
  bash "$RESOLVE" --check-only

# --- derive invite + app base ---
output="$(
  env \
    CLIENT_SERVER_NAME=https://app.dev.tentura.io \
    IMAGE_SERVER=https://cdn.example/tentura \
    INVITE_LINK_HOST= \
    APP_BASE= \
    bash "$RESOLVE" --check-only 2>&1
)"
echo "$output" | grep -q 'INVITE_LINK_HOST=https://dev.tentura.io' \
  || { echo "FAIL: expected derived INVITE_LINK_HOST" >&2; exit 1; }
echo "$output" | grep -q 'APP_BASE=https://app.dev.tentura.io/' \
  || { echo "FAIL: expected derived APP_BASE" >&2; exit 1; }
echo "OK: derives INVITE_LINK_HOST and APP_BASE from CLIENT_SERVER_NAME"

# --- explicit overrides respected ---
output="$(
  env \
    CLIENT_SERVER_NAME=https://app.dev.tentura.io \
    IMAGE_SERVER=https://cdn.example/tentura \
    INVITE_LINK_HOST=https://custom.landing.io \
    APP_BASE=https://custom.app.io/ \
    bash "$RESOLVE" --check-only 2>&1
)"
echo "$output" | grep -q 'INVITE_LINK_HOST=https://custom.landing.io' \
  || { echo "FAIL: explicit INVITE_LINK_HOST not kept" >&2; exit 1; }
echo "$output" | grep -q 'APP_BASE=https://custom.app.io/' \
  || { echo "FAIL: explicit APP_BASE not kept" >&2; exit 1; }
echo "OK: explicit INVITE_LINK_HOST and APP_BASE preserved"

# --- APP_BASE must end with slash when explicit ---
run_fail "APP_BASE without trailing slash" \
  env \
    CLIENT_SERVER_NAME=https://app.dev.tentura.io \
    IMAGE_SERVER=https://cdn.example/tentura \
    APP_BASE=https://app.dev.tentura.io \
    bash "$RESOLVE" --check-only

echo "All resolve_deploy_web_config tests passed."
