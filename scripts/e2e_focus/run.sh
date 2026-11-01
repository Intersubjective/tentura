#!/usr/bin/env bash
# Invoke through run_with_test_cleanup.sh; requires the local Docker services.
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
node scripts/e2e_focus/local_stack_fixture.mjs "$@"
