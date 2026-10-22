#!/usr/bin/env bash
# Run the Flutter web integration tests (packages/client/integration_test/*)
# headless against the local dev stack.
#
# Usage:
#   ./scripts/run_client_integration_web_local.sh                 # all tests
#   ./scripts/run_client_integration_web_local.sh integration_test/request_lifecycle_create_forward_inbox_test.dart
#   TENTURA_WEB_E2E_WASM=1 ./scripts/run_client_integration_web_local.sh ...   # wasm build behind Caddy
#
# Two modes:
#   default  dart2js debug build; Chrome opens the app on flutter drive's dev
#            server (http://localhost:8888), which proxies the API itself.
#            Caddy is not involved.
#   TENTURA_WEB_E2E_WASM=1
#            the production renderer: `flutter drive --wasm` (skwasm), opened
#            at https://dev.lvh.me:9443/ through the local Caddy
#            (Caddyfile.local with LOCAL_ROOT_SPLIT=off
#            LOCAL_FLUTTER_UPSTREAM=localhost:8888). Caddy proxies app paths to
#            the dev server on :8888, sends COOP/COEP (multi-threaded skwasm
#            needs a cross-origin isolated page) and routes /api, WebSocket
#            and /_qa paths to the backend; the app is built with
#            env/integration-web-caddy.env (SERVER_NAME/WS_SERVER_NAME =
#            https://dev.lvh.me:9443). The runner starts Caddy if nothing
#            listens on :9443 and stops it on exit; `/` is served from a page
#            it renders from web/index.html. A Caddy that is already running
#            is reused only if it serves the app (not the landing) at `/` —
#            start it with the two variables above. Needs `caddy` on PATH and
#            Caddy's local CA trusted (./scripts/trust-caddy-local-ca.sh). The
#            plain dev-server path does not work for --wasm: the QA bootstrap
#            POST to /_qa/ returns 404 there.
#
# What it does (reuses whatever is already running, starts what is not):
#   1. docker compose infra (postgres, meritrank, hasura, minio) — started if down
#   2. tentura-server on :2080 — started via scripts/run-server-local.sh if down
#   3. chromedriver on :4444 — auto-downloaded to .local/chromedriver to match
#      the installed Google Chrome major version
#   4. flutter drive -d web-server (headless Chrome) per test file
#
# Default mode: the app under test is served by Flutter's dev server on
# localhost:8888 which proxies /api/v2, /api/v1/graphql and /_qa to the backend
# (web_dev_config.yaml in packages/client). Caddy is NOT in the test data path —
# only the compose infra and tentura-server are required. See
# docs/local-integration-tests.md.
#
# Optional env knobs:
#   TENTURA_WEB_E2E_WASM=1  wasm build behind Caddy (see "Two modes" above)
#   CADDY_LOG               log of a Caddy this runner starts
#       (default /tmp/tentura-caddy-it.log)
#   TENTURA_WEB_CHROME_NO_SANDBOX=1  pass --web-browser-flag=--no-sandbox to
#       flutter drive. Needed inside Alloy's per-bead bwrap sandbox, whose
#       mounts are nosuid: Chrome's default setuid sandbox then aborts with
#       "SUID sandbox helper binary was found, but is not configured correctly".
#       Off by default; normal runs are unchanged. The leftover-Chrome cleanup
#       matches the --user-data-dir command-line pattern; the sandbox has a
#       private /tmp but shares the host's pids (no --unshare-pid), so a
#       Chrome that was already running before this runner started is still
#       recorded as pre-existing and left alone.
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
CADDY_LOG="${CADDY_LOG:-/tmp/tentura-caddy-it.log}"
WASM_MODE=0
[[ "${TENTURA_WEB_E2E_WASM:-}" == "1" ]] && WASM_MODE=1
CADDY_ORIGIN=https://dev.lvh.me:9443
CADDY_PORT=9443

log() { printf '\n[integration] %s\n' "$*"; }
die() { echo "[integration] ERROR: $*" >&2; exit 1; }

# --- 0. env & QA token -------------------------------------------------------
ENV_FILE="$ROOT/.env"
REGEN_JWT=0
ensure_kv() {
  grep -qE "^$1=" "$ENV_FILE" || printf '%s=%s\n' "$1" "$2" >>"$ENV_FILE"
}
if [[ ! -f "$ENV_FILE" ]]; then
  [[ -f "$ROOT/.env.example" ]] || die "missing $ROOT/.env (copy .env.example)"
  cp "$ROOT/.env.example" "$ENV_FILE"
  example_pub="$(grep -E '^JWT_PUBLIC_PEM=' "$ROOT/.env.example" || true)"
  current_pub="$(grep -E '^JWT_PUBLIC_PEM=' "$ENV_FILE" || true)"
  if [[ -z "$current_pub" || "$current_pub" == "$example_pub" ]]; then
    bash "$ROOT/scripts/gen-dev-jwt.sh"
    REGEN_JWT=1
  fi
  ensure_kv ENVIRONMENT dev
  ensure_kv QA_AUTH_ENABLED true
  ensure_kv QA_AUTH_TOKEN local-dev-qa-token
  ensure_kv QA_SIMPLE_LOGIN_MODE true
fi
QA_AUTH_TOKEN="${QA_AUTH_TOKEN:-$(grep -E '^QA_AUTH_TOKEN=' "$ENV_FILE" | cut -d= -f2-)}"
[[ -n "$QA_AUTH_TOKEN" ]] || die "QA_AUTH_TOKEN not set in env or $ENV_FILE"
grep -qE '^QA_AUTH_ENABLED=true' "$ENV_FILE" || die ".env needs QA_AUTH_ENABLED=true"
grep -qE '^QA_SIMPLE_LOGIN_MODE=true' "$ENV_FILE" || die ".env needs QA_SIMPLE_LOGIN_MODE=true"

# --- 1. docker compose infra -------------------------------------------------
if ! curl -sf -m 3 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
  log "starting docker compose infra (hasura not answering)"
  (cd "$ROOT" && docker compose up -d)
  if [[ "$REGEN_JWT" == "1" ]]; then
    (cd "$ROOT" && docker compose up -d --force-recreate hasura)
  fi
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

# A reused server may predate the current build; /health cannot tell. Placement
# apply needs ConstellationAnchorOpInput, so refuse a server whose GraphQL schema
# lacks it (or cannot be introspected) rather than fail every apply mid-run.
if ! curl -sf -m 10 http://127.0.0.1:2080/api/v2/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ __type(name: \"ConstellationAnchorOpInput\") { name } }"}' \
  | jq -e '.data.__type.name == "ConstellationAnchorOpInput"' >/dev/null 2>&1; then
  die "tentura-server schema is outdated or cannot be verified (no ConstellationAnchorOpInput on :2080/api/v2/graphql) — restart it from the current build (stop the server on :2080 and rerun)"
fi
log "tentura-server schema OK (ConstellationAnchorOpInput)"

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

CHROME_SCOPED_PATTERN='--user-data-dir=/tmp/\.org\.chromium\.Chromium\.scoped_dir'
# Browsers alive before this run: cleanup must never touch someone else's.
PREEXISTING_CHROME="$(pgrep -f -- "$CHROME_SCOPED_PATTERN" 2>/dev/null | sort -u || true)"

STARTED_CHROMEDRIVER=""
CHROMEDRIVER_PGID=""
if ! curl -sf -m 2 "http://127.0.0.1:$CHROMEDRIVER_PORT/status" >/dev/null 2>&1; then
  # setsid: chromedriver and every Chrome it spawns share one process group, so
  # cleanup can reap the whole tree at once (see cleanup() below).
  setsid "$CHROMEDRIVER_BIN" --port="$CHROMEDRIVER_PORT" >/tmp/tentura-chromedriver.log 2>&1 &
  STARTED_CHROMEDRIVER=$!
  CHROMEDRIVER_PGID="$(ps -o pgid= -p "$STARTED_CHROMEDRIVER" 2>/dev/null | tr -d ' ' || true)"
  sleep 2
fi

# `flutter drive` leaves its Chrome running whenever a target fails or times out,
# and SIGTERM to chromedriver does not reap those sessions. Orphaned browsers get
# reparented to init and survive indefinitely — each holding ~1 GiB of RSS plus a
# ~500 MiB --user-data-dir under /tmp, which is tmpfs, i.e. RAM. Nine such
# instances (oldest 6 days) once cost ~9 GiB on a dev box. Reap them explicitly.
reap_leaked_browsers() {
  local now leaked
  now="$(pgrep -f -- "$CHROME_SCOPED_PATTERN" 2>/dev/null | sort -u || true)"
  leaked="$(comm -13 <(printf '%s\n' "$PREEXISTING_CHROME") <(printf '%s\n' "$now") 2>/dev/null || true)"
  [[ -z "${leaked//[[:space:]]/}" ]] && return 0
  # shellcheck disable=SC2086
  kill $leaked >/dev/null 2>&1 || true
  sleep 2
  # shellcheck disable=SC2086
  kill -9 $leaked >/dev/null 2>&1 || true
}

STARTED_CADDY=""
cleanup() {
  if [[ -n "$STARTED_CADDY" ]]; then
    kill "$STARTED_CADDY" >/dev/null 2>&1 || true
    wait "$STARTED_CADDY" 2>/dev/null || true
  fi
  if [[ -n "$CHROMEDRIVER_PGID" ]]; then
    kill -- "-$CHROMEDRIVER_PGID" >/dev/null 2>&1 || true
  elif [[ -n "$STARTED_CHROMEDRIVER" ]]; then
    kill "$STARTED_CHROMEDRIVER" >/dev/null 2>&1 || true
  fi
  reap_leaked_browsers
  [[ -n "$STARTED_SERVER" ]] && pkill -P "$STARTED_SERVER" >/dev/null 2>&1 || true
  [[ -n "$STARTED_SERVER" ]] && kill "$STARTED_SERVER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- 4. free the web port (flutter drive binds localhost:8888) ---------------
if ss -tln 2>/dev/null | grep -qE "[.:]$WEB_PORT "; then
  die "port $WEB_PORT busy — stop the local flutter dev server first (fuser -k $WEB_PORT/tcp)"
fi

# --- 4b. wasm mode: Caddy HTTPS origin ----------------------------------------
DEFINES_FILE=env/integration-web.env
MODE_FLAGS=()
if [[ "$WASM_MODE" == "1" ]]; then
  DEFINES_FILE=env/integration-web-caddy.env
  MODE_FLAGS+=(--wasm "--web-launch-url=$CADDY_ORIGIN/")
  [[ -f "$CLIENT_DIR/$DEFINES_FILE" ]] || die "missing $CLIENT_DIR/$DEFINES_FILE"
  command -v caddy >/dev/null || die "TENTURA_WEB_E2E_WASM=1 needs caddy on PATH"
  if ! ss -tln 2>/dev/null | grep -qE "[.:]$CADDY_PORT "; then
    # With LOCAL_ROOT_SPLIT=off Caddy serves `/` itself from LOCAL_APP_ROOT
    # (every other app path goes to the dev server). Render that page from
    # web/index.html so the run does not depend on a stale build/web.
    CADDY_APP_ROOT="$CLIENT_DIR/build/integration-web-caddy"
    mkdir -p "$CADDY_APP_ROOT"
    sed 's|\$FLUTTER_BASE_HREF|/|' "$CLIENT_DIR/web/index.html" >"$CADDY_APP_ROOT/index.html"
    log "starting Caddy on :$CADDY_PORT (log: $CADDY_LOG)"
    (
      cd "$ROOT"
      LOCAL_ROOT_SPLIT=off LOCAL_FLUTTER_UPSTREAM=localhost:$WEB_PORT \
        LOCAL_APP_ROOT="$CADDY_APP_ROOT" exec caddy run --config Caddyfile.local
    ) >"$CADDY_LOG" 2>&1 &
    STARTED_CADDY=$!
    for _ in $(seq 1 30); do
      ss -tln 2>/dev/null | grep -qE "[.:]$CADDY_PORT " && break
      kill -0 "$STARTED_CADDY" 2>/dev/null || die "Caddy exited (see $CADDY_LOG)"
      sleep 1
    done
  else
    log "reusing the Caddy already on :$CADDY_PORT (it must run with LOCAL_ROOT_SPLIT=off LOCAL_FLUTTER_UPSTREAM=localhost:$WEB_PORT)"
  fi
  # Before flutter drive runs, `/` is the only app path that answers: it must
  # be the app page (not the landing, i.e. root split off) with COOP/COEP, over
  # a TLS certificate this machine trusts.
  root_ok=0
  for _ in $(seq 1 15); do
    if root_page="$(curl -sS -m 5 -D - "$CADDY_ORIGIN/" 2>&1)"; then
      root_ok=1
      break
    fi
    sleep 1
  done
  [[ "$root_ok" == "1" ]] || die "cannot fetch $CADDY_ORIGIN/ ($(printf '%s' "$root_page" | tail -1)); is Caddy's local CA trusted? (./scripts/trust-caddy-local-ca.sh)"
  grep -q 'flutter_bootstrap.js' <<<"$root_page" \
    || die "$CADDY_ORIGIN/ does not serve the app page (landing root split on, or no index.html under its LOCAL_APP_ROOT?) — restart Caddy with LOCAL_ROOT_SPLIT=off LOCAL_FLUTTER_UPSTREAM=localhost:$WEB_PORT, or stop it and let this runner start one"
  grep -qi '^cross-origin-embedder-policy:' <<<"$root_page" \
    || die "$CADDY_ORIGIN/ sends no Cross-Origin-Embedder-Policy; skwasm would run single-threaded"
  log "Caddy OK ($CADDY_ORIGIN, app at /, COOP/COEP)"
fi

# --- 5. run the tests --------------------------------------------------------
if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=()
  # Profile-only benchmark runs via run_client_profile_web_bench_local.sh.
  while IFS= read -r f; do TARGETS+=("${f#"$CLIENT_DIR"/}"); done \
    < <(find "$CLIENT_DIR/integration_test" -maxdepth 1 -name '*_test.dart' \
      ! -name 'constellation_profile_web_bench_test.dart' | sort)
fi

DRIVE_BROWSER_FLAGS=()
if [[ "${TENTURA_WEB_CHROME_NO_SANDBOX:-}" == "1" ]]; then
  DRIVE_BROWSER_FLAGS+=(--web-browser-flag=--no-sandbox)
fi

if [[ "$WASM_MODE" == "1" ]]; then
  log "mode: --wasm (skwasm) via Caddy $CADDY_ORIGIN/, defines $DEFINES_FILE"
else
  log "mode: dart2js debug on the dev server http://localhost:$WEB_PORT/, defines $DEFINES_FILE"
fi

cd "$CLIENT_DIR"
FAILED=()
for target in "${TARGETS[@]}"; do
  browser_dimension="${BROWSER_DIMENSION:-1600x1024}"
  if [[ -z "${BROWSER_DIMENSION:-}" && \
        "$target" == "integration_test/request_threads_navigation_test.dart" ]]; then
    # This journey asserts the compact nested-route/browser-history contract.
    # WidgetTester.setSurfaceSize is not a valid substitute on Flutter Web: it
    # constrains the render surface while MediaQuery retains the real browser
    # viewport, producing an impossible mixed window class/layout.
    browser_dimension="390x844"
  fi
  log "=== flutter drive: $target (browser $browser_dimension)"
  if flutter drive \
    ${MODE_FLAGS[@]+"${MODE_FLAGS[@]}"} \
    --driver=test_driver/integration_test.dart \
    --target="$target" \
    -d web-server \
    --browser-name=chrome \
    ${DRIVE_BROWSER_FLAGS[@]+"${DRIVE_BROWSER_FLAGS[@]}"} \
    --browser-dimension="$browser_dimension" \
    --dart-define-from-file="$DEFINES_FILE" \
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
