#!/usr/bin/env bash
# One browser integration target; no API/database fixtures are needed because
# it mounts the production discussion widget through the shared room harness.
# Invoke through scripts/run_with_test_cleanup.sh to serialize and bound it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DRIVER_PORT=4445
WEB_PORT=8888
if ss -ltn | rg -q ":(${DRIVER_PORT}|${WEB_PORT})[[:space:]]"; then
  echo 'Typing browser test needs free ports 4445 and 8888' >&2
  exit 1
fi
"$ROOT/.local/chromedriver/chromedriver" --port="$DRIVER_PORT" \
  >"${TMPDIR:-/tmp}/tentura-typing-chromedriver.log" 2>&1 &
DRIVER_PID=$!
trap 'kill "$DRIVER_PID" 2>/dev/null || true; wait "$DRIVER_PID" 2>/dev/null || true' EXIT
for _ in {1..30}; do
  if curl --silent --fail --max-time 1 "http://127.0.0.1:$DRIVER_PORT/status" >/dev/null; then
    break
  fi
  sleep 0.1
done
cd "$ROOT/packages/client"
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=test/room_typing_message_visibility_web_test.dart \
  -d web-server \
  --browser-name=chrome \
  --web-browser-flag=--no-sandbox \
  --browser-dimension=375x667@1 \
  --driver-port="$DRIVER_PORT" \
  --web-hostname=127.0.0.1 \
  --web-port="$WEB_PORT" \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
