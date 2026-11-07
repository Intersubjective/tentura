#!/usr/bin/env bash
# Invoke through run_with_test_cleanup.sh. Uses an isolated fake cookie server;
# QA_INTEGRATION_TEST_MODE must stay off so production document navigation runs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ ! -d "$ROOT/scripts/e2e_session_account/node_modules" ]]; then
  npm ci --prefix "$ROOT/scripts/e2e_session_account" \
    --cache "${XDG_CACHE_HOME:-$HOME/.cache}/npm" \
    --ignore-scripts --no-audit --no-fund
fi
WEB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tentura-session-account-web.XXXXXX")"
trap 'rm -rf "$WEB_DIR"' EXIT
cd "$ROOT/scripts/e2e_session_account"
SESSION_ACCOUNT_WEB_DIR="$WEB_DIR" node --test session_account_changed.test.mjs
