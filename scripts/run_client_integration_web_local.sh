#!/usr/bin/env bash
# Run the Flutter web integration tests (packages/client/integration_test/*)
# headless against the local dev stack.
#
# Usage:
#   ./scripts/run_client_integration_web_local.sh                 # all tests
#   ./scripts/run_client_integration_web_local.sh integration_test/request_lifecycle_create_forward_inbox_test.dart
#
# What it does (reuses whatever is already running, starts what is not):
#   1. docker compose infra (postgres, meritrank, hasura, minio) — started if down
#   2. tentura-server on :2080 — started via scripts/run-server-local.sh if down
#   3. chromedriver on :4444 — auto-downloaded to .local/chromedriver to match
#      the installed Google Chrome major version
#   4. flutter drive -d web-server (headless Chrome) per test file
#
# The app under test is served by Flutter's dev server on localhost:8888 which
# proxies /api/v2, /api/v1/graphql and /_qa to the backend (web_dev_config.yaml
# in packages/client). Caddy is NOT in the test data path — only the compose
# infra and tentura-server are required. See docs/local-integration-tests.md.
#
# Requirements: .env at repo root with QA_AUTH_ENABLED=true, QA_AUTH_TOKEN,
# QA_SIMPLE_LOGIN_MODE=true (see .env.example); google-chrome; docker compose.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT/packages/client"
CHROMEDRIVER_PORT="${CHROMEDRIVER_PORT:-4444}"
CHROMEDRIVER_DIR="$ROOT/.local/chromedriver"
WEB_PORT=8888
SERVER_LOG="${SERVER_LOG:-/tmp/tentura-server-it.log}"

log() { printf '\n[integration] %s\n' "$*"; }
die() { echo "[integration] ERROR: $*" >&2; exit 1; }

# --- 0. env & QA token -------------------------------------------------------
[[ -f "$ROOT/.env" ]] || die "missing $ROOT/.env (copy .env.example)"
QA_AUTH_TOKEN="${QA_AUTH_TOKEN:-$(grep -E '^QA_AUTH_TOKEN=' "$ROOT/.env" | cut -d= -f2-)}"
[[ -n "$QA_AUTH_TOKEN" ]] || die "QA_AUTH_TOKEN not set in env or $ROOT/.env"
grep -qE '^QA_AUTH_ENABLED=true' "$ROOT/.env" || die ".env needs QA_AUTH_ENABLED=true"
grep -qE '^QA_SIMPLE_LOGIN_MODE=true' "$ROOT/.env" || die ".env needs QA_SIMPLE_LOGIN_MODE=true"

# --- 1. docker compose infra -------------------------------------------------
if ! curl -sf -m 3 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
  log "starting docker compose infra (hasura not answering)"
  (cd "$ROOT" && docker compose up -d)
  for _ in $(seq 1 60); do
    curl -sf -m 2 http://127.0.0.1:8080/healthz >/dev/null 2>&1 && break
    sleep 2
  done
  curl -sf -m 2 http://127.0.0.1:8080/healthz >/dev/null || die "hasura did not become healthy"
fi
log "infra OK (hasura :8080 healthy)"

# --- 2. tentura-server -------------------------------------------------------
STARTED_SERVER=""
if ! curl -sf -m 3 http://127.0.0.1:2080/health >/dev/null 2>&1; then
  log "starting tentura-server (log: $SERVER_LOG)"
  nohup "$ROOT/scripts/run-server-local.sh" >"$SERVER_LOG" 2>&1 &
  STARTED_SERVER=$!
  for _ in $(seq 1 60); do
    curl -sf -m 2 http://127.0.0.1:2080/health >/dev/null 2>&1 && break
    sleep 2
  done
  curl -sf -m 2 http://127.0.0.1:2080/health >/dev/null || die "tentura-server did not come up (see $SERVER_LOG)"
fi
log "tentura-server OK (:2080)"

# sanity: QA bootstrap endpoint answers (fails fast on token/env mismatch)
curl -sf -m 10 http://127.0.0.1:2080/_qa/integration/bootstrap \
  -H "Authorization: Bearer $QA_AUTH_TOKEN" -H 'Content-Type: application/json' \
  -d '{"runId":"runner-smoke"}' >/dev/null || die "QA bootstrap smoke call failed (check QA_* in .env, restart server)"
log "QA bootstrap OK"

# --- 3. chromedriver ---------------------------------------------------------
command -v google-chrome >/dev/null || die "google-chrome not installed"
CHROME_MAJOR="$(google-chrome --version | grep -oE '[0-9]+' | head -1)"
CHROMEDRIVER_BIN="$CHROMEDRIVER_DIR/chromedriver"
if [[ ! -x "$CHROMEDRIVER_BIN" ]] || ! "$CHROMEDRIVER_BIN" --version | grep -q " $CHROME_MAJOR\."; then
  log "fetching chromedriver for Chrome $CHROME_MAJOR"
  CHROME_BUILD="$(google-chrome --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  URL="$(curl -sf https://googlechromelabs.github.io/chrome-for-testing/latest-patch-versions-per-build-with-downloads.json \
    | jq -r --arg b "$CHROME_BUILD" '.builds[$b].downloads.chromedriver[] | select(.platform=="linux64") | .url')"
  [[ -n "$URL" && "$URL" != null ]] || die "no chromedriver download for Chrome build $CHROME_BUILD"
  mkdir -p "$CHROMEDRIVER_DIR"
  TMPZIP="$(mktemp --suffix=.zip)"
  curl -sf -o "$TMPZIP" "$URL"
  unzip -o -q -j "$TMPZIP" 'chromedriver-linux64/chromedriver' -d "$CHROMEDRIVER_DIR"
  rm -f "$TMPZIP"
fi
log "chromedriver: $("$CHROMEDRIVER_BIN" --version | head -1)"

STARTED_CHROMEDRIVER=""
if ! curl -sf -m 2 "http://127.0.0.1:$CHROMEDRIVER_PORT/status" >/dev/null 2>&1; then
  "$CHROMEDRIVER_BIN" --port="$CHROMEDRIVER_PORT" >/tmp/tentura-chromedriver.log 2>&1 &
  STARTED_CHROMEDRIVER=$!
  sleep 2
fi

cleanup() {
  [[ -n "$STARTED_CHROMEDRIVER" ]] && kill "$STARTED_CHROMEDRIVER" >/dev/null 2>&1 || true
  [[ -n "$STARTED_SERVER" ]] && pkill -P "$STARTED_SERVER" >/dev/null 2>&1 || true
  [[ -n "$STARTED_SERVER" ]] && kill "$STARTED_SERVER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- 4. free the web port (flutter drive binds localhost:8888) ---------------
if ss -tln 2>/dev/null | grep -qE "[.:]$WEB_PORT "; then
  die "port $WEB_PORT busy — stop the local flutter dev server first (fuser -k $WEB_PORT/tcp)"
fi

# --- 5. run the tests --------------------------------------------------------
if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=()
  while IFS= read -r f; do TARGETS+=("${f#"$CLIENT_DIR"/}"); done \
    < <(find "$CLIENT_DIR/integration_test" -maxdepth 1 -name '*_test.dart' | sort)
fi

cd "$CLIENT_DIR"
FAILED=()
for target in "${TARGETS[@]}"; do
  log "=== flutter drive: $target"
  if flutter drive \
    --driver=test_driver/integration_test.dart \
    --target="$target" \
    -d web-server \
    --browser-name=chrome \
    --dart-define-from-file=env/integration-web.env \
    --dart-define=QA_AUTH_TOKEN="$QA_AUTH_TOKEN" \
    --dart-define=QA_INTEGRATION_TEST_MODE=true; then
    log "PASS: $target"
  else
    log "FAIL: $target"
    FAILED+=("$target")
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "FAILED: ${FAILED[*]}"
  exit 1
fi
log "all ${#TARGETS[@]} integration test file(s) passed"
