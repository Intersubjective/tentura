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
  env CLIENT_SERVER_NAME=https://dev.tentura.io IMAGE_SERVER= \
  bash "$RESOLVE" --check-only

# --- invalid URLs ---
run_fail "invalid IMAGE_SERVER" \
  env CLIENT_SERVER_NAME=https://dev.tentura.io IMAGE_SERVER=not-a-url \
  bash "$RESOLVE" --check-only

run_fail "path-only CLIENT_SERVER_NAME" \
  env CLIENT_SERVER_NAME=/invite/foo IMAGE_SERVER=https://cdn.example/bucket \
  bash "$RESOLVE" --check-only

# --- valid single-origin config ---
output="$(
  env \
    CLIENT_SERVER_NAME=https://dev.tentura.io \
    IMAGE_SERVER=https://cdn.example/tentura \
    bash "$RESOLVE" --check-only 2>&1
)"
echo "$output" | grep -q 'CLIENT_SERVER_NAME=https://dev.tentura.io' \
  || { echo "FAIL: expected CLIENT_SERVER_NAME in output" >&2; exit 1; }
echo "$output" | grep -q 'IMAGE_SERVER=https://cdn.example/tentura' \
  || { echo "FAIL: expected IMAGE_SERVER in output" >&2; exit 1; }
echo "OK: resolves CLIENT_SERVER_NAME and IMAGE_SERVER"

echo "All resolve_deploy_web_config tests passed."
