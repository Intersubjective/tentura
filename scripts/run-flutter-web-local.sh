#!/usr/bin/env bash
# Sync client dart-defines from .env and run Flutter web dev server for Caddy proxy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT/scripts/sync-client-local-config.sh"
bash "$ROOT/scripts/resolve_local_web_config.sh" --check-only

cd "$ROOT/packages/client"
dart run tool/apply_google_maps_web_key.dart --source
# Bind IPv4 explicitly: the web-server device otherwise binds whatever `localhost`
# resolves to (often IPv6 ::1), which Caddyfile.local's 127.0.0.1:8888 upstream
# cannot reach → 502 on app paths. Override with LOCAL_FLUTTER_HOSTNAME if needed.
exec flutter run -d web-server --web-port=8888 \
  --web-hostname="${LOCAL_FLUTTER_HOSTNAME:-127.0.0.1}" \
  --dart-define-from-file=env/local-web.env \
  "$@"
