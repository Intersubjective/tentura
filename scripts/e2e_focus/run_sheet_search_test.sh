#!/usr/bin/env bash
# #741: the capability search keeps typing (Requirements + Edit labels,
# clear × and hover, EN and RU). Invoke through run_with_test_cleanup.sh;
# requires the local Docker services, the QA API and static Caddy (README).
# Usage: run_sheet_search_test.sh [cycles=10]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ ! -d "$ROOT/scripts/e2e_focus/node_modules/playwright" ]]; then
  npm ci --prefix "$ROOT/scripts/e2e_focus" \
    --cache "${XDG_CACHE_HOME:-$HOME/.cache}/npm" --ignore-scripts --no-audit --no-fund
fi
cd "$ROOT/packages/client"
flutter build web --profile --wasm --no-pub --no-web-resources-cdn \
  --dart-define-from-file=env/local-web.env \
  --output="${FOCUS_WEB_DIR:-/tmp/tentura-focus-profile-web}"
cd "$ROOT"
node scripts/e2e_focus/sheet_search_keeps_typing.mjs "${1:-10}"
