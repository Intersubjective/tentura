#!/usr/bin/env bash
# Profile-web benchmark of the Constellation graph (issue #235 U40, I4):
# grab → first moved frame (mouse and touch), drag frame, pan frame, drop →
# ack → reflow and every > 50 ms main-thread task by phase, at N = 100/300/600
# in Chrome, from a `flutter drive --profile` build.
#
# Usage:
#   ./scripts/run_client_profile_web_bench_local.sh                    # production: --wasm, headless
#   TENTURA_BENCH_JS=1 ./scripts/run_client_profile_web_bench_local.sh # dart2js/CanvasKit fallback
#   TENTURA_BENCH_HEADED=1 ./scripts/run_client_profile_web_bench_local.sh
#
# Renderer. By default the benchmark builds with `--wasm`, the configuration
# production ships (`flutter build web --wasm`): multi-threaded skwasm, which
# needs the page to be cross-origin isolated. Production gets COOP/COEP from
# the Caddyfile; here flutter drive's dev server sends them
# (packages/client/web_dev_config.yaml). TENTURA_BENCH_JS=1 drops `--wasm` and
# measures the dart2js/CanvasKit build, which is what browsers without WasmGC
# get from Flutter's loader (Firefox and every iOS browser by default).
#
# Reading the numbers. Under skwasm the FrameTiming build duration includes the
# scene's wait in the engine's render queue (renderScene / _kickRenderLoop:
# build-finish is stamped when the previous frame's raster on the render worker
# is done), so it is not the framework's work and runs high in headless Chrome.
# Judge per-frame framework work by the "fw Frame" column (the framework's own
# "Frame" measure, p50/p95/max), reported next to build/raster/total for drag
# and pan. The summary starts and ends with the renderer that actually ran
# (skwasm/canvaskit), whether the page was crossOriginIsolated, and whether
# Chrome was headless or headed.
#
# The benchmark uses in-memory repositories, so unlike
# run_client_integration_web_local.sh it needs no backend: only Google Chrome
# and a matching chromedriver (fetched to .local/chromedriver on demand).
# Numbers are written to packages/client/build/bench/constellation_profile_web.json
# and printed as a summary; the benchmark asserts no budgets.
#
# Optional env knobs:
#   TENTURA_BENCH_JS=1               dart2js/CanvasKit build (no --wasm)
#   TENTURA_BENCH_HEADED=1           pass --no-headless (needs a display); the
#       default headless Chrome is what CI-like runs see, headed is closer to a
#       user's browser (its compositor paces frames differently)
#   TENTURA_WEB_CHROME_NO_SANDBOX=1  pass --web-browser-flag=--no-sandbox
#   BROWSER_DIMENSION=WxH            browser window (default 1600x1024)
#   CHROMEDRIVER_PORT                default 4444
#   TENTURA_BENCH_SOFTWARE_GL=1      keep headless Chrome's SwiftShader WebGL.
#       By default the browser is pointed at the host GPU through ANGLE/Vulkan
#       (raster times from software GL say nothing about real devices); the
#       WebGL renderer actually used is recorded in the JSON.
#   TENTURA_BENCH_PROFILE_OBJECTS=1  diagnostic run: per-widget build/layout/
#       paint Timeline events from grab through reflow (adds overhead; not the
#       benchmark's numbers)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT/packages/client"
CHROMEDRIVER_PORT="${CHROMEDRIVER_PORT:-4444}"
CHROMEDRIVER_DIR="$ROOT/.local/chromedriver"
WEB_PORT=8888
TARGET=integration_test/constellation_profile_web_bench_test.dart
DRIVER=test_driver/constellation_profile_web_bench_driver.dart
REPORT="$CLIENT_DIR/build/bench/constellation_profile_web.json"

log() { printf '\n[bench] %s\n' "$*"; }
die() { echo "[bench] ERROR: $*" >&2; exit 1; }

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

if ss -tln 2>/dev/null | grep -qE "[.:]$WEB_PORT "; then
  die "port $WEB_PORT busy — stop the local flutter dev server first"
fi

CHROME_SCOPED_PATTERN='--user-data-dir=/tmp/\.org\.chromium\.Chromium\.scoped_dir'
PREEXISTING_CHROME="$(pgrep -f -- "$CHROME_SCOPED_PATTERN" 2>/dev/null | sort -u || true)"
STARTED_CHROMEDRIVER=""
CHROMEDRIVER_PGID=""
if ! curl -sf -m 2 "http://127.0.0.1:$CHROMEDRIVER_PORT/status" >/dev/null 2>&1; then
  setsid "$CHROMEDRIVER_BIN" --port="$CHROMEDRIVER_PORT" >/tmp/tentura-chromedriver-bench.log 2>&1 &
  STARTED_CHROMEDRIVER=$!
  CHROMEDRIVER_PGID="$(ps -o pgid= -p "$STARTED_CHROMEDRIVER" 2>/dev/null | tr -d ' ' || true)"
  sleep 2
fi

# Same leaked-browser reaping as run_client_integration_web_local.sh.
cleanup() {
  if [[ -n "$CHROMEDRIVER_PGID" ]]; then
    kill -- "-$CHROMEDRIVER_PGID" >/dev/null 2>&1 || true
  elif [[ -n "$STARTED_CHROMEDRIVER" ]]; then
    kill "$STARTED_CHROMEDRIVER" >/dev/null 2>&1 || true
  fi
  local now leaked
  now="$(pgrep -f -- "$CHROME_SCOPED_PATTERN" 2>/dev/null | sort -u || true)"
  leaked="$(comm -13 <(printf '%s\n' "$PREEXISTING_CHROME") <(printf '%s\n' "$now") 2>/dev/null || true)"
  if [[ -n "${leaked//[[:space:]]/}" ]]; then
    # shellcheck disable=SC2086
    kill $leaked >/dev/null 2>&1 || true
    sleep 2
    # shellcheck disable=SC2086
    kill -9 $leaked >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

MODE_FLAGS=()
if [[ "${TENTURA_BENCH_JS:-}" == "1" ]]; then
  REQUESTED_RENDERER=canvaskit
  BUILD_LABEL="dart2js (CanvasKit fallback)"
else
  REQUESTED_RENDERER=skwasm
  BUILD_LABEL="--wasm (production: skwasm)"
  MODE_FLAGS+=(--wasm)
fi
if [[ "${TENTURA_BENCH_HEADED:-}" == "1" ]]; then
  REQUESTED_BROWSER=headed
  MODE_FLAGS+=(--no-headless)
else
  REQUESTED_BROWSER=headless
fi

DRIVE_BROWSER_FLAGS=()
if [[ "${TENTURA_WEB_CHROME_NO_SANDBOX:-}" == "1" ]]; then
  DRIVE_BROWSER_FLAGS+=(--web-browser-flag=--no-sandbox)
fi

if [[ "${TENTURA_BENCH_SOFTWARE_GL:-}" != "1" ]]; then
  DRIVE_BROWSER_FLAGS+=(
    --web-browser-flag=--use-angle=vulkan
    --web-browser-flag=--enable-features=Vulkan
    --web-browser-flag=--ignore-gpu-blocklist
  )
fi
DEFINES=()
if [[ "${TENTURA_BENCH_PROFILE_OBJECTS:-}" == "1" ]]; then
  DEFINES+=(--dart-define=CONSTELLATION_BENCH_PROFILE_OBJECTS=true)
fi

log "environment"
lscpu | grep -E 'Model name' | sed 's/^/[bench]   /' || true
echo "[bench]   threads: $(nproc)"
echo "[bench]   $(google-chrome --version)"
echo "[bench]   $("$CHROMEDRIVER_BIN" --version | head -1)"
flutter --version 2>/dev/null | head -1 | sed 's/^/[bench]   /'
echo "[bench]   commit: $(git -C "$ROOT" rev-parse --short HEAD)$(git -C "$ROOT" diff --quiet || echo ' (dirty)')"
echo "[bench]   load average: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "[bench]   requested: $BUILD_LABEL, $REQUESTED_BROWSER Chrome"

cd "$CLIENT_DIR"
# A failed run must not leave the previous run's numbers looking current.
rm -f "$REPORT"
log "flutter drive --profile${MODE_FLAGS[*]:+ ${MODE_FLAGS[*]}}: $TARGET"
set +e
flutter drive \
  --profile \
  ${MODE_FLAGS[@]+"${MODE_FLAGS[@]}"} \
  --driver="$DRIVER" \
  --target="$TARGET" \
  -d web-server \
  --browser-name=chrome \
  ${DRIVE_BROWSER_FLAGS[@]+"${DRIVE_BROWSER_FLAGS[@]}"} \
  --browser-dimension="${BROWSER_DIMENSION:-1600x1024}" \
  ${DEFINES[@]+"${DEFINES[@]}"} \
  --dart-define-from-file=env/integration-web.env
DRIVE_RC=$?
set -e

# What actually ran, from the browser's own report: a --wasm build falls back
# to single-threaded skwasm when the page is not cross-origin isolated, and to
# the dart2js build when the browser lacks WasmGC.
if [[ -f "$REPORT" ]]; then
  RAN="$(jq -r '.environment | "\(.renderer // "unknown") \(.crossOriginIsolated // "unknown") \(if .headless == true then "headless" elif .headless == false then "headed" else "unknown" end)"' "$REPORT")"
  read -r RAN_RENDERER RAN_COI RAN_BROWSER <<<"$RAN"
  log "ran: renderer=$RAN_RENDERER crossOriginIsolated=$RAN_COI $RAN_BROWSER (requested $REQUESTED_RENDERER, $REQUESTED_BROWSER)"
  if [[ "$RAN_RENDERER" != "$REQUESTED_RENDERER" ]]; then
    echo "[bench] WARNING: requested $REQUESTED_RENDERER but $RAN_RENDERER ran — these are not the requested configuration's numbers" >&2
  fi
  if [[ "$RAN_RENDERER" == skwasm && "$RAN_COI" != true ]]; then
    echo "[bench] WARNING: skwasm without crossOriginIsolated is single-threaded (no COOP/COEP headers?) — not the production configuration" >&2
  fi
  if [[ "$RAN_BROWSER" != "$REQUESTED_BROWSER" ]]; then
    echo "[bench] WARNING: requested $REQUESTED_BROWSER Chrome but it ran $RAN_BROWSER" >&2
  fi
else
  log "no report at $REPORT"
fi
exit "$DRIVE_RC"
