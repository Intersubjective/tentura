#!/usr/bin/env bash
# Full-stack simultaneous-browser realtime proof.
#
# Starts one Tentura server, one Flutter web dev server, and Chromedriver. The
# Dart WebDriver test then owns two independent Chrome sessions/profiles. Five
# consecutive runs are the default exit gate; set REALTIME_MULTICLIENT_RUNS=1
# and REALTIME_MULTICLIENT_NEGATIVE_PROOFS=false while iterating locally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT/packages/client"
CHROMEDRIVER_PORT="${CHROMEDRIVER_PORT:-4444}"
CHROMEDRIVER_DIR="$ROOT/.local/chromedriver"
WEB_PORT=8888
RUNS="${REALTIME_MULTICLIENT_RUNS:-5}"
NEGATIVE_PROOFS="${REALTIME_MULTICLIENT_NEGATIVE_PROOFS:-true}"
SESSION_ID="${REALTIME_MULTICLIENT_SESSION_ID:-$(date +%Y%m%d-%H%M%S)}"
ARTIFACT_ROOT="${REALTIME_MULTICLIENT_ARTIFACT_ROOT:-$ROOT/reports/realtime-multiclient/$SESSION_ID}"
SERVER_LOG="$ARTIFACT_ROOT/server.log"
WEB_LOG="$ARTIFACT_ROOT/flutter-web.log"

log() { printf '\n[realtime-multiclient] %s\n' "$*"; }
die() { echo "[realtime-multiclient] ERROR: $*" >&2; exit 1; }

[[ -f "$ROOT/.env" ]] || die "missing $ROOT/.env"
QA_AUTH_TOKEN="${QA_AUTH_TOKEN:-$(grep -E '^QA_AUTH_TOKEN=' "$ROOT/.env" | cut -d= -f2-)}"
[[ -n "$QA_AUTH_TOKEN" ]] || die "QA_AUTH_TOKEN is missing"
grep -qE '^QA_AUTH_ENABLED=true' "$ROOT/.env" || die ".env needs QA_AUTH_ENABLED=true"
grep -qE '^QA_SIMPLE_LOGIN_MODE=true' "$ROOT/.env" || die ".env needs QA_SIMPLE_LOGIN_MODE=true"
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || die "REALTIME_MULTICLIENT_RUNS must be a positive integer"
[[ "$NEGATIVE_PROOFS" == true || "$NEGATIVE_PROOFS" == false ]] \
  || die "REALTIME_MULTICLIENT_NEGATIVE_PROOFS must be true or false"
mkdir -p "$ARTIFACT_ROOT"

STARTED_SERVER=""
STARTED_CHROMEDRIVER=""
STARTED_WEB=""
STARTED_CADDY=""
cleanup() {
  [[ -n "$STARTED_CADDY" ]] && kill "$STARTED_CADDY" >/dev/null 2>&1 || true
  [[ -n "$STARTED_WEB" ]] && pkill -P "$STARTED_WEB" >/dev/null 2>&1 || true
  [[ -n "$STARTED_WEB" ]] && kill "$STARTED_WEB" >/dev/null 2>&1 || true
  [[ -n "$STARTED_CHROMEDRIVER" ]] && kill "$STARTED_CHROMEDRIVER" >/dev/null 2>&1 || true
  [[ -n "$STARTED_SERVER" ]] && pkill -P "$STARTED_SERVER" >/dev/null 2>&1 || true
  [[ -n "$STARTED_SERVER" ]] && kill "$STARTED_SERVER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! curl -sf -m 3 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
  log "starting docker compose infrastructure"
  (cd "$ROOT" && docker compose up -d)
  for _ in $(seq 1 60); do
    curl -sf -m 2 http://127.0.0.1:8080/healthz >/dev/null 2>&1 && break
    sleep 2
  done
fi
curl -sf -m 2 http://127.0.0.1:8080/healthz >/dev/null || die "Hasura did not become healthy"

if ! curl -sf -m 3 http://127.0.0.1:2080/health >/dev/null 2>&1; then
  log "starting Tentura server"
  nohup "$ROOT/scripts/run-server-local.sh" >"$SERVER_LOG" 2>&1 &
  STARTED_SERVER=$!
  for _ in $(seq 1 90); do
    curl -sf -m 2 http://127.0.0.1:2080/health >/dev/null 2>&1 && break
    sleep 2
  done
fi
curl -sf -m 2 http://127.0.0.1:2080/health >/dev/null || die "Tentura server did not become healthy"

SMOKE_JSON="$(curl -sf -m 15 http://127.0.0.1:2080/_qa/integration/bootstrap \
  -H "Authorization: Bearer $QA_AUTH_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"runId":"realtime-runner-smoke"}')" || die "QA bootstrap failed"
SMOKE_HELPER="$(jq -r '.helperUserId' <<<"$SMOKE_JSON")"
curl -sf -m 10 http://127.0.0.1:2080/_qa/integration/realtime-socket \
  -H "Authorization: Bearer $QA_AUTH_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"userId\":\"$SMOKE_HELPER\",\"action\":\"resume\"}" >/dev/null \
  || die "QA realtime route unavailable; restart a stale local server"

command -v google-chrome >/dev/null || die "google-chrome is not installed"
CHROME_MAJOR="$(google-chrome --version | grep -oE '[0-9]+' | head -1)"
CHROMEDRIVER_BIN="$CHROMEDRIVER_DIR/chromedriver"
if [[ ! -x "$CHROMEDRIVER_BIN" ]] || ! "$CHROMEDRIVER_BIN" --version | grep -q " $CHROME_MAJOR\."; then
  log "fetching Chromedriver for Chrome $CHROME_MAJOR"
  CHROME_BUILD="$(google-chrome --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  URL="$(curl -sf https://googlechromelabs.github.io/chrome-for-testing/latest-patch-versions-per-build-with-downloads.json \
    | jq -r --arg build "$CHROME_BUILD" '.builds[$build].downloads.chromedriver[] | select(.platform=="linux64") | .url')"
  [[ -n "$URL" && "$URL" != null ]] || die "no Chromedriver for Chrome build $CHROME_BUILD"
  mkdir -p "$CHROMEDRIVER_DIR"
  TMPZIP="$(mktemp --suffix=.zip)"
  curl -sf -o "$TMPZIP" "$URL"
  unzip -o -q -j "$TMPZIP" 'chromedriver-linux64/chromedriver' -d "$CHROMEDRIVER_DIR"
  rm -f "$TMPZIP"
fi
if ! curl -sf -m 2 "http://127.0.0.1:$CHROMEDRIVER_PORT/status" >/dev/null 2>&1; then
  "$CHROMEDRIVER_BIN" --port="$CHROMEDRIVER_PORT" >"$ARTIFACT_ROOT/chromedriver.log" 2>&1 &
  STARTED_CHROMEDRIVER=$!
  for _ in $(seq 1 30); do
    curl -sf -m 2 "http://127.0.0.1:$CHROMEDRIVER_PORT/status" >/dev/null 2>&1 && break
    sleep 1
  done
fi
curl -sf -m 2 "http://127.0.0.1:$CHROMEDRIVER_PORT/status" >/dev/null || die "Chromedriver did not start"

if ss -tln 2>/dev/null | grep -qE "[.:]$WEB_PORT "; then
  die "port $WEB_PORT is busy; stop the existing Flutter web server"
fi
log "starting one Flutter web dev server"
(
  cd "$CLIENT_DIR"
  flutter run -d web-server \
    --profile \
    --web-hostname=localhost \
    --web-port="$WEB_PORT" \
    --dart-define-from-file=env/local-web.env \
    --dart-define=WS_SERVER_NAME=https://dev.lvh.me:9443
) >"$WEB_LOG" 2>&1 &
STARTED_WEB=$!
for _ in $(seq 1 180); do
  rg -q 'is being served at|Flutter run key commands' "$WEB_LOG" && break
  sleep 1
done
rg -q 'is being served at|Flutter run key commands' "$WEB_LOG" || die "Flutter web server did not finish compiling"
curl -sf -m 2 "http://localhost:$WEB_PORT/main.dart.js" >/dev/null || die "Flutter web output is unavailable"
if ! curl -ksf -m 3 https://dev.lvh.me:9443/ >/dev/null 2>&1; then
  command -v caddy >/dev/null || die "Caddy is required for the HTTPS app origin"
  log "starting local Caddy HTTPS proxy"
  (cd "$ROOT" && caddy run --config Caddyfile.local) >"$ARTIFACT_ROOT/caddy.log" 2>&1 &
  STARTED_CADDY=$!
  for _ in $(seq 1 30); do
    curl -ksf -m 2 https://dev.lvh.me:9443/ >/dev/null 2>&1 && break
    sleep 1
  done
fi
curl -ksf -m 5 https://dev.lvh.me:9443/ >/dev/null || die "Caddy local origin is unavailable"

cd "$CLIENT_DIR"
for run in $(seq 1 "$RUNS"); do
  RUN_ID="realtime-$(date +%s)-$run"
  RUN_DIR="$ARTIFACT_ROOT/run-$run"
  log "run $run/$RUNS ($RUN_ID)"
  QA_AUTH_TOKEN="$QA_AUTH_TOKEN" \
  REALTIME_MULTICLIENT_RUN_ID="$RUN_ID" \
  REALTIME_MULTICLIENT_ARTIFACT_DIR="$RUN_DIR" \
    dart run test_driver/realtime_multiclient_web_test.dart
done

jq -s '
  . as $runs |
  ([$runs[] | keys[]] | unique) as $keys |
  reduce $keys[] as $key ({};
    ($runs | map(.[$key]) | map(select(. != null)) | sort) as $samples |
    .[$key] = {
      samples_ms: $samples,
      p95_ms: $samples[((($samples | length) * 0.95 | ceil) - 1)]
    }
  )
' "$ARTIFACT_ROOT"/run-*/timings.json >"$ARTIFACT_ROOT/timings-summary.json"

if [[ "$NEGATIVE_PROOFS" == true ]]; then
  for disabled_path in live catch_up; do
    NEGATIVE_DIR="$ARTIFACT_ROOT/negative-$disabled_path"
    log "negative proof: disabling $disabled_path convergence"
    if QA_AUTH_TOKEN="$QA_AUTH_TOKEN" \
      REALTIME_MULTICLIENT_RUN_ID="negative-$disabled_path-$(date +%s)" \
      REALTIME_MULTICLIENT_ARTIFACT_DIR="$NEGATIVE_DIR" \
      REALTIME_MULTICLIENT_DISABLE_PATH="$disabled_path" \
        dart run test_driver/realtime_multiclient_web_test.dart; then
      die "driver unexpectedly passed with $disabled_path disabled"
    fi
    log "expected failure observed with $disabled_path disabled"
  done
fi

log "PASS: $RUNS consecutive simultaneous-client runs and negative proofs=$NEGATIVE_PROOFS"
