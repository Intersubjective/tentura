#!/usr/bin/env bash
# Behavioural tests for scripts/run_realtime_multiclient_web_local.sh in a
# fresh worktree: docker compose must join the shared `tentura` project (unless
# the caller chose another, or the stack is already healthy), and the gitignored
# packages/client/env/local-web.env must exist when `flutter run` reads it.
#
# The script is copied into a scratch checkout; docker, flutter, curl, dart and
# the sibling helper scripts are stubs that append to a call log.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REAL_ROOT}/scripts/run_realtime_multiclient_web_local.sh"

fail() { echo "FAIL: $1" >&2; [[ -f "${LOG:-}" ]] && sed 's/^/  call: /' "$LOG" >&2; exit 1; }
ok() { echo "OK: $1"; }

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

stub() { # stub <path> <body...>
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$1"
  chmod +x "$1"
}

# run_case <name> [ENV=VALUE ...]; sets ROOT, LOG. Env "HEALTHY=1" pre-marks
# the main stack as already serving Hasura.
run_case() {
  local name="$1"; shift
  T="$TMP_BASE/$name"
  ROOT="$T/root"
  LOG="$T/calls.log"
  local BIN="$T/bin"
  mkdir -p "$ROOT/scripts" "$ROOT/packages/client" "$BIN" "$T/state"
  : >"$LOG"
  cp "$SCRIPT" "$ROOT/scripts/"
  printf 'QA_AUTH_ENABLED=true\nQA_SIMPLE_LOGIN_MODE=true\nQA_AUTH_TOKEN=tok\n' >"$ROOT/.env"

  # Helper scripts the runner shells out to.
  stub "$ROOT/scripts/sync-client-local-config.sh" '
echo "sync|cwd=$PWD|args=$*" >>"$CALL_LOG"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/packages/client/env"
echo SERVER_NAME=x >"$ROOT/packages/client/env/local-web.env"'
  stub "$ROOT/scripts/resolve_local_web_config.sh" 'echo "resolve|cwd=$PWD|args=$*" >>"$CALL_LOG"'
  stub "$ROOT/scripts/run-server-local.sh" 'touch "$STATE_DIR/server_started"; exec sleep 120'
  stub "$ROOT/.local/chromedriver/chromedriver" 'echo "ChromeDriver 120.0.1.2"'

  # PATH stubs.
  stub "$BIN/docker" '
echo "docker|cwd=$PWD|proj=${COMPOSE_PROJECT_NAME-<unset>}|args=$*" >>"$CALL_LOG"
touch "$STATE_DIR/healthy"'
  stub "$BIN/flutter" '
def=""
for a in "$@"; do case "$a" in --dart-define-from-file=*) def="${a#*=}";; esac; done
exists=no; [[ -n "$def" && -f "$def" ]] && exists=yes
echo "flutter|cwd=$PWD|define_file=$def|define_file_exists=$exists|args=$*" >>"$CALL_LOG"
echo "is being served at http://localhost:8888"'
  stub "$BIN/dart" '
if [[ -n "${REALTIME_MULTICLIENT_ARTIFACT_DIR:-}" ]]; then
  mkdir -p "$REALTIME_MULTICLIENT_ARTIFACT_DIR"; echo "{\"a\":1}" >"$REALTIME_MULTICLIENT_ARTIFACT_DIR/timings.json"
fi'
  stub "$BIN/curl" '
url=""; for a in "$@"; do case "$a" in http*) url="$a";; esac; done
case "$url" in
  *:8080/healthz) [[ -f "$STATE_DIR/healthy" ]] ;;
  *:2080/health) [[ -f "$STATE_DIR/server_started" ]] ;;
  *_qa/integration/bootstrap) echo "{\"helperUserId\":\"u1\"}" ;;
  *) exit 0 ;;
esac'
  stub "$BIN/ss" 'exit 0'
  stub "$BIN/git" 'echo abc123'
  stub "$BIN/google-chrome" 'echo "Google Chrome 120.0.1.2"'

  local -a extra=()
  local a
  for a in "$@"; do
    if [[ "$a" == HEALTHY=1 ]]; then touch "$T/state/healthy"; else extra+=("$a"); fi
  done

  set +e
  env -u COMPOSE_PROJECT_NAME ${extra[@]+"${extra[@]}"} \
    PATH="$BIN:$PATH" CALL_LOG="$LOG" STATE_DIR="$T/state" \
    REALTIME_MULTICLIENT_RUNS=1 REALTIME_MULTICLIENT_NEGATIVE_PROOFS=false \
    REALTIME_MULTICLIENT_ARTIFACT_ROOT="$T/artifacts" \
    timeout 120 bash "$ROOT/scripts/run_realtime_multiclient_web_local.sh" >"$T/out.log" 2>&1
  RC=$?
  set -e
}

# Effective compose project of the (first) docker compose up call.
effective_project() {
  local line
  line="$(grep -m1 '^docker|' "$LOG")" || return 1
  if [[ "$line" =~ (^|[[:space:]])(-p|--project-name)[[:space:]=]+([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[3]}"
  elif [[ "$line" =~ --project-name=([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    sed -E 's/^docker\|cwd=[^|]*\|proj=([^|]*)\|.*/\1/' <<<"$line"
  fi
}

line_of() { grep -n "^$1|" "$LOG" | head -1 | cut -d: -f1 || true; }

# --- case 1: stack down, COMPOSE_PROJECT_NAME unset ---
run_case default
[[ -n "$(line_of flutter)" ]] || { cat "$T/out.log" >&2; fail "runner never reached flutter run (rc=$RC)"; }
[[ -n "$(line_of docker)" ]] || fail "docker compose up was not run when the stack is down"
proj="$(effective_project)"
[[ "$proj" == tentura ]] \
  || fail "docker compose must run in shared project 'tentura' (got '$proj'); a plain assignment without export/-p does not reach docker"
ok "docker compose defaults to the shared tentura project"

flutter_line="$(line_of flutter)"
sync_line="$(line_of sync)"
[[ -n "$sync_line" ]] || fail "sync-client-local-config.sh was not run (env/local-web.env missing in worktrees)"
(( sync_line < flutter_line )) || fail "sync-client-local-config.sh must run before flutter run"
grep -q '^flutter|.*define_file_exists=yes|' "$LOG" \
  || fail "the --dart-define-from-file path flutter reads must exist at flutter run time"
ok "client env file exists when flutter run reads it"

check_line="$(grep -n '^resolve|.*args=.*--check-only' "$LOG" | head -1 | cut -d: -f1 || true)"
[[ -n "$check_line" ]] || fail "resolve_local_web_config.sh --check-only was not run"
(( check_line < flutter_line )) || fail "local web config check must run before flutter run"
ok "local web config validated before flutter run"

# --- case 2: caller-chosen project is respected ---
run_case override COMPOSE_PROJECT_NAME=custom
[[ -n "$(line_of docker)" ]] || fail "override case: docker compose up not run"
[[ "$(effective_project)" == custom ]] \
  || fail "an existing COMPOSE_PROJECT_NAME must not be overridden (got '$(effective_project)')"
ok "existing COMPOSE_PROJECT_NAME is respected"

# --- case 3: main stack already healthy (shared-stack scenario) ---
# Either skipping compose or running it idempotently in the tentura project is fine.
run_case healthy HEALTHY=1
[[ -n "$(line_of flutter)" ]] || fail "healthy case: runner never reached flutter run"
if [[ -n "$(line_of docker)" ]]; then
  [[ "$(effective_project)" == tentura ]] \
    || fail "healthy case: if compose runs it must join project 'tentura' (got '$(effective_project)')"
fi
grep -q '^flutter|.*define_file_exists=yes|' "$LOG" \
  || fail "healthy case: client env file must still be generated before flutter run"
ok "healthy stack never clashes with main project and still syncs client env"

echo "All run_realtime_multiclient_web_local tests passed."
