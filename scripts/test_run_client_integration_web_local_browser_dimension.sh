#!/usr/bin/env bash
# Behavioural tests for the per-target browser window size of
# scripts/run_client_integration_web_local.sh. Targets that assert a phone
# viewport get a phone-sized headless Chrome window unless BROWSER_DIMENSION
# is set explicitly:
#   - constellation_trust_chain_edges_phone_test.dart asserts a 375x667 app
#     viewport; Chrome's toolbar takes 139 px, so the window is 375x806.
#   - request_threads_navigation_test.dart keeps its 390x844 window.
#   - every other target keeps the 1600x1024 default.
# An explicit BROWSER_DIMENSION always wins. Everything the runner shells out
# to is stubbed (same style as the no-sandbox test).
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REAL_ROOT}/scripts/run_client_integration_web_local.sh"
[[ -f "$SCRIPT" ]] || { echo "missing $SCRIPT" >&2; exit 1; }

fail() { echo "FAIL: $1" >&2; [[ -f "${OUT:-}" ]] && sed 's/^/  out: /' "$OUT" >&2; exit 1; }
ok() { echo "OK: $1"; }

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

stub() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$1"
  chmod +x "$1"
}

PHONE_TARGET=integration_test/constellation_trust_chain_edges_phone_test.dart
THREADS_TARGET=integration_test/request_threads_navigation_test.dart
OTHER_TARGET=integration_test/placement_probe_test.dart

# run_case <name> <target> [BROWSER_DIMENSION value]
# Sets T, ROOT, OUT, EVENTS, RC. Runs the runner against a single target.
run_case() {
  local name="$1" target="$2" dimension="${3:-}"

  T="$TMP_BASE/$name"
  ROOT="$T/root"
  OUT="$T/out.log"
  EVENTS="$T/events.log"
  local BIN="$T/bin"
  mkdir -p "$ROOT/scripts" "$ROOT/packages/client" "$BIN"
  : >"$EVENTS"
  cp "$SCRIPT" "$ROOT/scripts/"
  cat >"$ROOT/.env" <<'EOF'
QA_AUTH_ENABLED=true
QA_SIMPLE_LOGIN_MODE=true
QA_AUTH_TOKEN=tok
EOF

  stub "$ROOT/scripts/run-server-local.sh" 'exit 0'
  cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*) url="$a";; esac; done
case "$url" in
  */api/v2/graphql)
    echo '{"data":{"__type":{"name":"ConstellationAnchorOpInput","kind":"INPUT_OBJECT"},"__schema":{"mutationType":{"fields":[{"name":"constellationAnchorsApply"}]}}}}'
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BIN/curl"

  stub "$BIN/flutter" 'echo "flutter $*" >>"$EVENTS"; exit 0'
  stub "$BIN/docker" 'exit 0'
  stub "$BIN/google-chrome" 'echo "Google Chrome 120.0.1.2"'
  stub "$ROOT/.local/chromedriver/chromedriver" 'echo "ChromeDriver 120.0.1.2"'
  stub "$BIN/ss" 'exit 0'
  # Never touch the host's processes or ports.
  stub "$BIN/pgrep" 'exit 1'
  stub "$BIN/pkill" 'exit 0'
  stub "$BIN/fuser" 'exit 1'
  stub "$BIN/lsof" 'exit 1'

  set +e
  if [[ -n "$dimension" ]]; then
    env BROWSER_DIMENSION="$dimension" PATH="$BIN:$PATH" EVENTS="$EVENTS" T_DIR="$T" \
      timeout 45 bash "$ROOT/scripts/run_client_integration_web_local.sh" \
      "$target" >"$OUT" 2>&1
  else
    env -u BROWSER_DIMENSION PATH="$BIN:$PATH" EVENTS="$EVENTS" T_DIR="$T" \
      timeout 45 bash "$ROOT/scripts/run_client_integration_web_local.sh" \
      "$target" >"$OUT" 2>&1
  fi
  RC=$?
  set -e
}

flutter_line() { grep '^flutter' "$EVENTS" || true; }

# expect_dimension <label> <target> <dimension>
expect_dimension() {
  local label="$1" target="$2" dimension="$3"
  [[ "$RC" -eq 0 ]] || fail "$label: run must succeed (rc=$RC)"
  [[ "$(grep -c '^flutter' "$EVENTS")" -eq 1 ]] || fail "$label: flutter drive must run once"
  flutter_line | grep -q -- "--target=$target" \
    || fail "$label: flutter drive must run $target"
  flutter_line | grep -q -- "--browser-dimension=$dimension\( \|$\)" \
    || fail "$label: flutter drive must get --browser-dimension=$dimension, got: $(flutter_line)"
  grep -qF "=== flutter drive: $target (browser $dimension)" "$OUT" \
    || fail "$label: log must read '=== flutter drive: $target (browser $dimension)'"
}

run_case phone_default "$PHONE_TARGET"
expect_dimension "phone smoke, BROWSER_DIMENSION unset" "$PHONE_TARGET" 375x806
ok "phone smoke defaults to a 375x806 window (a 375x667 app viewport)"

run_case phone_explicit "$PHONE_TARGET" 1280x800
expect_dimension "phone smoke, BROWSER_DIMENSION=1280x800" "$PHONE_TARGET" 1280x800
ok "an explicit BROWSER_DIMENSION wins for the phone smoke"

run_case threads_default "$THREADS_TARGET"
expect_dimension "request threads, BROWSER_DIMENSION unset" "$THREADS_TARGET" 390x844
ok "request threads journey still defaults to 390x844"

run_case other_default "$OTHER_TARGET"
expect_dimension "other target, BROWSER_DIMENSION unset" "$OTHER_TARGET" 1600x1024
ok "any other target still defaults to 1600x1024"

echo "All run_client_integration_web_local browser-dimension tests passed."
