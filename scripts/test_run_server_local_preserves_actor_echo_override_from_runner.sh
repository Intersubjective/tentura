#!/usr/bin/env bash
# Behavioural tests for scripts/run-server-local.sh:
# - When the caller exports REALTIME_ACTOR_ECHO_ENABLED, it must reach the server
#   process even when repo-root .env defines the same name with a different value.
# - When the caller does not set it, the value from .env must still reach the server.
# - Other .env exports (here: LOCAL_TEST_ONLY_SENTINEL) must still be visible so a
#   fix cannot "win" by skipping .env.
#
# Run: bash scripts/test_run_server_local_preserves_actor_echo_override_from_runner.sh
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_SRC="${REAL_ROOT}/scripts/run-server-local.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $1"; }

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

ROOT="$TMP_BASE/root"
BIN="$TMP_BASE/bin"
STATE="$TMP_BASE/state"
mkdir -p "$ROOT/scripts" "$ROOT/packages/server/bin" "$BIN" "$STATE"

cp "$SCRIPT_SRC" "$ROOT/scripts/run-server-local.sh"
chmod +x "$ROOT/scripts/run-server-local.sh"

printf '#!/usr/bin/env bash\nexit 0\n' >"$ROOT/scripts/validate_local_server_env.sh"
chmod +x "$ROOT/scripts/validate_local_server_env.sh"

: >"$ROOT/packages/server/bin/tentura.dart"

# ss: no listeners (avoids flaky exit 1 when port 2080 is in use on the host).
# dart stub: records env seen by the server process and proves it was invoked.
stub_ss="$BIN/ss"
printf '#!/usr/bin/env bash\n# No listeners; grep in run-server-local must not match.\nexit 0\n' >"$stub_ss"
chmod +x "$stub_ss"

stub_dart="$BIN/dart"
cat >"$stub_dart" <<STUB
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="\${STATE_DIR:?}"
touch "\$STATE_DIR/dart_stub_ran"
printf '%s' "\${REALTIME_ACTOR_ECHO_ENABLED:-}" >"\$STATE_DIR/actor_echo_at_server_start"
printf '%s' "\${LOCAL_TEST_ONLY_SENTINEL:-}" >"\$STATE_DIR/dotenv_sentinel_at_server_start"
exit 0
STUB
chmod +x "$stub_dart"

PATH_EXPORT="$BIN:/usr/bin:/bin"
if ! command -v setsid >/dev/null 2>&1; then
  fail "setsid is required to exercise run-server-local.sh (expected on Linux)"
fi

write_dotenv_actor_and_sentinel() {
  local actor_val="$1"
  cat >"$ROOT/.env" <<EOF
REALTIME_ACTOR_ECHO_ENABLED=${actor_val}
LOCAL_TEST_ONLY_SENTINEL=from_repo_root_dotenv
EOF
}

assert_stub_ran_and_sentinel() {
  [[ -f "$STATE/dart_stub_ran" ]] \
    || fail "dart stub was not invoked (missing $STATE/dart_stub_ran) — run-server-local may have exited before starting the server (e.g. port in use) or did not reach dart"
  local sent
  sent="$(cat "$STATE/dotenv_sentinel_at_server_start")"
  [[ "$sent" == from_repo_root_dotenv ]] \
    || fail "LOCAL_TEST_ONLY_SENTINEL in server process was '$sent' (expected 'from_repo_root_dotenv' — .env must still be loaded)"
}

# run_one <expected_actor_echo> [env args for env(1)...]
run_one() {
  local expected="$1"
  shift
  rm -f "$STATE"/*
  mkdir -p "$STATE"
  set +e
  env "$@" PATH="$PATH_EXPORT" STATE_DIR="$STATE" \
    bash "$ROOT/scripts/run-server-local.sh" >/dev/null 2>&1
  local rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || fail "run-server-local.sh exited $rc (expected 0 under stub dart; check port/ss/dart path)"
  assert_stub_ran_and_sentinel
  local got
  got="$(cat "$STATE/actor_echo_at_server_start")"
  [[ "$got" == "$expected" ]] \
    || fail "server process saw REALTIME_ACTOR_ECHO_ENABLED='$got' (expected '$expected')"
}

# Caller true, .env false — runner must not be overwritten by .env.
write_dotenv_actor_and_sentinel false
run_one true REALTIME_ACTOR_ECHO_ENABLED=true
ok "when caller sets true and .env has false, server sees true and .env sentinel is present"

# Caller false, .env true — runner must not be overwritten by .env (no hard-code-true fix).
write_dotenv_actor_and_sentinel true
run_one false REALTIME_ACTOR_ECHO_ENABLED=false
ok "when caller sets false and .env has true, server sees false and .env sentinel is present"

# Caller unset: server must see .env (guards against dropping .env load).
write_dotenv_actor_and_sentinel false
run_one false -u REALTIME_ACTOR_ECHO_ENABLED
ok "when caller does not set REALTIME_ACTOR_ECHO_ENABLED and .env has false, server sees false"

write_dotenv_actor_and_sentinel true
run_one true -u REALTIME_ACTOR_ECHO_ENABLED
ok "when caller does not set REALTIME_ACTOR_ECHO_ENABLED and .env has true, server sees true"

echo "All run_server_local actor-echo override tests passed."
