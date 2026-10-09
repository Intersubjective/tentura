#!/usr/bin/env bash
# Behavioural tests for scripts/run_client_integration_web_local.sh when a
# tentura-server is already answering /health on :2080. The runner reuses a
# healthy server, so it must verify that the server's GraphQL schema is current
# (supports the constellation placement apply mutation) instead of trusting
# /health alone. A server whose schema is outdated, or whose schema cannot be
# verified, must never reach `flutter drive`: every placement apply would fail
# with "Unknown GraphQL type".
#
# The script is copied into a scratch checkout. Everything the runner shells out
# to (curl, docker, flutter, google-chrome, chromedriver, ss, pgrep, pkill,
# fuser, lsof and the sibling helper scripts) is a stub, so the only reason to
# stop before `flutter drive` is the schema check. The curl stub answers any
# request to /api/v2/graphql from the case's schema state, independent of the
# request body, and answers with a superset of introspection shapes (`__type`
# and the mutation field list) so it does not pin how the probe is phrased.
#
# Every probe and every flutter call is appended to one EVENTS log, which lets
# the tests assert the invariant "flutter drive only runs after the most recent
# schema probe saw a current schema".
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REAL_ROOT}/scripts/run_client_integration_web_local.sh"

[[ -f "$SCRIPT" ]] || { echo "missing $SCRIPT" >&2; exit 1; }

fail() {
  echo "FAIL: $1" >&2
  [[ -f "${OUT:-}" ]] && sed 's/^/  out: /' "$OUT" >&2
  [[ -f "${EVENTS:-}" ]] && sed 's/^/  event: /' "$EVENTS" >&2
  [[ -f "${CURL_LOG:-}" ]] && sed 's/^/  curl: /' "$CURL_LOG" >&2
  exit 1
}
ok() { echo "OK: $1"; }

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

stub() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$1"
  chmod +x "$1"
}

# run_case <name> <stale|current|probe_fail|probe_empty|probe_errors|probe_html>
# Sets T, ROOT, OUT, EVENTS, CURL_LOG, RC. Runs the runner against a single
# integration target so no test discovery is needed.
run_case() {
  local name="$1" schema_state="$2"

  T="$TMP_BASE/$name"
  ROOT="$T/root"
  OUT="$T/out.log"
  EVENTS="$T/events.log"
  CURL_LOG="$T/curl.log"
  local BIN="$T/bin"
  mkdir -p "$ROOT/scripts" "$ROOT/packages/client" "$BIN"
  : >"$EVENTS"
  : >"$CURL_LOG"
  echo "$schema_state" >"$T/schema_state"
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
  env PATH="$BIN:$PATH" CURL_LOG="$CURL_LOG" EVENTS="$EVENTS" T_DIR="$T" \
    timeout 45 bash "$ROOT/scripts/run_client_integration_web_local.sh" \
    integration_test/placement_probe_test.dart >"$OUT" 2>&1
  RC=$?
  set -e
}

probed_schema_endpoint() {
  grep -q '^probe:' "$EVENTS" && grep -q '/api/v2/graphql' "$CURL_LOG"
}

flutter_ran() { grep -q '^flutter' "$EVENTS"; }

# flutter drive may run only when the most recent schema probe saw a current
# schema (and there was one).
flutter_only_after_current_probe() {
  awk '/^probe:/{last=$0} /^flutter/{if (last != "probe:current") bad=1} END{exit bad?1:0}' "$EVENTS"
}

# The runner printed an error that points at the server schema.
reported_schema_problem() {
  grep -iqE 'ERROR:.*(schema|graphql|introspect|stale|outdated|out.of.date|ConstellationAnchor)' "$OUT"
}

# assert_server_not_trusted: the run must stop before flutter with a schema
# error, without any acceptable restart having happened.
assert_rejected() {
  probed_schema_endpoint \
    || fail "runner must probe the reused server's /api/v2/graphql schema before trusting it"
  flutter_only_after_current_probe \
    || fail "flutter drive must not run unless the latest schema probe saw a current schema"
  ! flutter_ran || fail "flutter drive must not run against a server whose schema is not verified current"
  [[ "$RC" -ne 0 ]] || fail "runner must exit non-zero when the server schema is not verified current (rc=$RC)"
  reported_schema_problem || fail "runner must report an ERROR that names the server schema problem"
}

# --- case 1: healthy server with an outdated schema --------------------------
# Either the runner refuses it, or it restarts the server and verifies the new
# schema is current before running the tests.
run_case outdated_schema stale
probed_schema_endpoint \
  || fail "runner must probe the reused server's /api/v2/graphql schema before trusting it"
flutter_only_after_current_probe \
  || fail "flutter drive must not run unless the latest schema probe saw a current schema"
if flutter_ran; then
  [[ -f "$T/server_starts" ]] \
    || fail "an outdated server may only be used after it was restarted with a current build"
  [[ "$RC" -eq 0 ]] || fail "after restarting an outdated server the run must succeed (rc=$RC)"
  ok "restarts an outdated server and verifies the schema before the test run"
else
  [[ "$RC" -ne 0 ]] || fail "runner stopped before flutter but exited 0 for an outdated server"
  reported_schema_problem || fail "runner must report an ERROR that names the outdated server schema"
  ok "rejects a healthy server whose schema lacks the placement apply mutation"
fi

# --- case 2: schema probe cannot be verified ---------------------------------
for state in probe_fail probe_empty probe_errors probe_html; do
  run_case "unverifiable_$state" "$state"
  assert_rejected
  ok "does not accept a server whose schema probe fails ($state)"
done

# --- case 3: healthy server with a current schema ----------------------------
run_case current_schema current
probed_schema_endpoint \
  || fail "runner must probe the reused server's /api/v2/graphql schema before trusting it"
grep -q 'tentura-server OK' "$OUT" || fail "a current server must be reused (rc=$RC)"
grep -q 'QA bootstrap OK' "$OUT" || fail "runner must pass the QA bootstrap check with a current server"
[[ ! -f "$T/server_starts" ]] || fail "a current healthy server must not be restarted"
flutter_ran || fail "runner must reach the test run against a current server (rc=$RC)"
[[ "$(grep -c '^flutter' "$EVENTS")" -eq 1 ]] || fail "flutter drive must run once for the one requested target"
grep -q '^flutter .*integration_test/placement_probe_test.dart' "$EVENTS" \
  || fail "flutter drive must target the requested integration test"
flutter_only_after_current_probe || fail "flutter drive must follow a current schema probe"
[[ "$RC" -eq 0 ]] || fail "run against a current server must succeed (rc=$RC)"
ok "reuses a healthy server whose schema supports placement apply and runs the tests"

echo "All run_client_integration_web_local stale-server tests passed."
