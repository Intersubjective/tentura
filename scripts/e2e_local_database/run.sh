#!/usr/bin/env bash
# Run through scripts/run_with_test_cleanup.sh (also serializes the build).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ ! -d "$ROOT/scripts/e2e_local_database/node_modules/playwright" ]]; then
  npm ci --prefix "$ROOT/scripts/e2e_local_database" \
    --cache "${XDG_CACHE_HOME:-$HOME/.cache}/npm" \
    --ignore-scripts --no-audit --no-fund
fi
WEB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tentura-local-db-web.XXXXXX")"
trap 'rm -rf "$WEB_DIR"' EXIT
cd "$ROOT/packages/client"
flutter build web --wasm --no-pub --no-web-resources-cdn \
  --target=integration_test/support/local_database_browser_app.dart \
  --output="$WEB_DIR"
cd "$ROOT/scripts/e2e_local_database"
LOCAL_DATABASE_WEB_DIR="$WEB_DIR" node --test "$@" suite.mjs
