#!/usr/bin/env bash
# Profile-web benchmark of the Constellation graph (issue #235 U40, I4):
# grab → first moved frame (mouse and touch), drag frame, pan frame, drop →
# ack → reflow and every > 50 ms main-thread task by phase, at N = 100/300/600
# in headless Chrome, from a `flutter drive --profile` build.
#
# Usage:
#   ./scripts/run_client_profile_web_bench_local.sh
#
# The benchmark uses in-memory repositories, so unlike
# run_client_integration_web_local.sh it needs no backend: only Google Chrome
# and a matching chromedriver (fetched to .local/chromedriver on demand).
# Numbers are written to packages/client/build/bench/constellation_profile_web.json
# and printed as a summary; the benchmark asserts no budgets.
#
# Optional env knobs:
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

cd "$CLIENT_DIR"
log "flutter drive --profile: $TARGET"
flutter drive \
  --profile \
  --driver="$DRIVER" \
  --target="$TARGET" \
  -d web-server \
  --browser-name=chrome \
  ${DRIVE_BROWSER_FLAGS[@]+"${DRIVE_BROWSER_FLAGS[@]}"} \
  --browser-dimension="${BROWSER_DIMENSION:-1600x1024}" \
  ${DEFINES[@]+"${DEFINES[@]}"} \
  --dart-define-from-file=env/integration-web.env
