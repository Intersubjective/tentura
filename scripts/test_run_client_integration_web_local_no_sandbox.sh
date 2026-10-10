#!/usr/bin/env bash
# Behavioural tests for the TENTURA_WEB_CHROME_NO_SANDBOX knob of
# scripts/run_client_integration_web_local.sh: with =1 the runner passes
# --web-browser-flag=--no-sandbox to `flutter drive` (needed under Alloy's
# nosuid bwrap sandbox); without it the flutter command line is unchanged.
# Everything the runner shells out to is stubbed (same style as the
# stale_server test).
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

# run_case <name> [env assignment for the runner]
# Sets T, ROOT, OUT, EVENTS, CURL_LOG, RC. Runs the runner against a single
# integration target so no test discovery is needed.
run_case() {
  local name="$1" extra_env="${2:-}"

  T="$TMP_BASE/$name"
  ROOT="$T/root"
  OUT="$T/out.log"
  EVENTS="$T/events.log"
  CURL_LOG="$T/curl.log"
  local BIN="$T/bin"
  mkdir -p "$ROOT/scripts" "$ROOT/packages/client" "$BIN"
  : >"$EVENTS"
  : >"$CURL_LOG"
  echo current >"$T/schema_state"
  cp "$SCRIPT" "$ROOT/scripts/"
  cat >"$ROOT/.env" <<'EOF'
QA_AUTH_ENABLED=true
QA_SIMPLE_LOGIN_MODE=true
QA_AUTH_TOKEN=tok
EOF

  # A restarted server runs the current build: restarting heals an outdated
  # schema, but never an unverifiable one.
  stub "$ROOT/scripts/run-server-local.sh" '
echo started >>"$T_DIR/server_starts"
[[ "$(cat "$T_DIR/schema_state")" == stale ]] && echo current >"$T_DIR/schema_state"
exit 0'

  cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$CURL_LOG"
url=""
for a in "$@"; do case "$a" in http*) url="$a";; esac; done
case "$url" in
  */api/v2/graphql)
    # Give a just-restarted server time to flip the schema state.
    sleep 0.3
    state="$(cat "$T_DIR/schema_state")"
    echo "probe:$state" >>"$EVENTS"
    case "$state" in
      stale)
        echo '{"data":{"__type":null,"__schema":{"mutationType":{"fields":[{"name":"constellationAnchorUpsert"},{"name":"constellationAnchorDelete"}]}}}}'
        ;;
      current)
        echo '{"data":{"__type":{"name":"ConstellationAnchorOpInput","kind":"INPUT_OBJECT"},"__schema":{"mutationType":{"fields":[{"name":"constellationAnchorUpsert"},{"name":"constellationAnchorDelete"},{"name":"constellationAnchorsApply"}]}}}}'
        ;;
      probe_fail) exit 22 ;;
      probe_empty) ;;
      probe_errors) echo '{"errors":[{"message":"Not Found"}]}' ;;
      probe_html) echo '<html><body>502 Bad Gateway</body></html>' ;;
    esac
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
  # Never touch the host's processes or ports, whichever way a restart is done.
  stub "$BIN/pgrep" 'exit 1'
  stub "$BIN/pkill" 'exit 0'
  stub "$BIN/fuser" 'exit 1'
  stub "$BIN/lsof" 'exit 1'

  set +e
  env ${extra_env:+"$extra_env"} PATH="$BIN:$PATH" CURL_LOG="$CURL_LOG" EVENTS="$EVENTS" T_DIR="$T" \
    timeout 45 bash "$ROOT/scripts/run_client_integration_web_local.sh" \
    integration_test/placement_probe_test.dart >"$OUT" 2>&1
  RC=$?
  set -e
}

flutter_line() { grep '^flutter' "$EVENTS"; }

run_case default
[[ "$RC" -eq 0 ]] || fail "default run must succeed (rc=$RC)"
flutter_line | grep -q 'integration_test/placement_probe_test.dart' || fail "flutter drive must run"
! flutter_line | grep -q -- '--no-sandbox' || fail "default run must not pass --no-sandbox"
! flutter_line | grep -q -- '--web-browser-flag' || fail "default run must not pass any --web-browser-flag"
ok "default: no browser flags"

run_case other_value TENTURA_WEB_CHROME_NO_SANDBOX=0
[[ "$RC" -eq 0 ]] || fail "=0 run must succeed (rc=$RC)"
! flutter_line | grep -q -- '--no-sandbox' || fail "=0 must not pass --no-sandbox"
ok "=0: no browser flags"

run_case no_sandbox TENTURA_WEB_CHROME_NO_SANDBOX=1
[[ "$RC" -eq 0 ]] || fail "=1 run must succeed (rc=$RC)"
flutter_line | grep -q -- '--web-browser-flag=--no-sandbox' || fail "=1 must pass --web-browser-flag=--no-sandbox"
[[ "$(grep -c '^flutter' "$EVENTS")" -eq 1 ]] || fail "flutter drive must run once"
ok "=1: --web-browser-flag=--no-sandbox passed to flutter drive"

echo "All run_client_integration_web_local no-sandbox tests passed."
