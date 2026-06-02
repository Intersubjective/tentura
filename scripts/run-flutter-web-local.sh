#!/usr/bin/env bash
# Sync client dart-defines from .env and run Flutter web dev server for Caddy proxy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT/scripts/sync-client-local-config.sh"
bash "$ROOT/scripts/resolve_local_web_config.sh" --check-only

cd "$ROOT/packages/client"
exec flutter run -d web-server --web-port=8888 \
  --dart-define-from-file=env/local-web.env \
  "$@"
