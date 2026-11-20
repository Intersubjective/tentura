#!/usr/bin/env bash
# Run the local integration entry point and its real metadata helper in a
# scratch checkout. Stub the services and browser tools instead of using them.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_BASE="$(mktemp -d)"
cleanup() {
  local pid_file
  for pid_file in "$TMP_BASE"/*/server.pid; do
    [[ -f "$pid_file" ]] || continue
    kill "$(cat "$pid_file")" 2>/dev/null || true
  done
  rm -rf "$TMP_BASE"
}
trap cleanup EXIT
TARGET=integration_test/x_test.dart
METADATA_URL=http://127.0.0.1:8080/v1/metadata
CONSISTENT='{"is_consistent":true,"inconsistent_objects":[]}'
INCONSISTENT='{"is_consistent":false,"inconsistent_objects":[{"name":"beacon","reason":"column lineage_parent_beacon_id does not exist (42703)"}]}'

stub() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$2" >"$1"
  chmod +x "$1"
}

fail() {
  echo "FAIL: $1" >&2
  sed 's/^/  stdout: /' "$OUT" >&2
  sed 's/^/  stderr: /' "$ERR" >&2
  sed 's/^/  event: /' "$EVENTS" >&2
  exit 1
}

# run_case <name> <status> <body> [env assignments...]
run_case() {
  local name="$1" status="$2" body="$3"
  shift 3
  CASE_DIR="$TMP_BASE/$name"
  ROOT="$CASE_DIR/root"
  OUT="$CASE_DIR/stdout"
  ERR="$CASE_DIR/stderr"
  EVENTS="$CASE_DIR/events"
  local bin="$CASE_DIR/bin"
  mkdir -p "$ROOT/scripts" "$ROOT/hasura" "$ROOT/packages/client/env" "$bin"
  : >"$EVENTS"
  cp "$REAL_ROOT/scripts/run_client_integration_web_local.sh" "$ROOT/scripts/"
  cp "$REAL_ROOT/scripts/hasura_apply_metadata.sh" "$ROOT/scripts/real-hasura-apply.sh"
  cp "$REAL_ROOT/hasura/metadata.json" "$ROOT/hasura/"
  cp "$REAL_ROOT/packages/client/env/integration-web-caddy.env" "$ROOT/packages/client/env/"
  cat >"$ROOT/.env" <<'ENV'
QA_AUTH_ENABLED=true
QA_SIMPLE_LOGIN_MODE=true
QA_AUTH_TOKEN=stub-qa-token
ENV

  # Mark requests made by the helper while preserving its real HTTP handling.
  stub "$ROOT/scripts/hasura_apply_metadata.sh" '
export METADATA_HELPER_RUNNING=1
exec bash "$(dirname "$0")/real-hasura-apply.sh" "$@"'
  stub "$ROOT/scripts/run-server-local.sh" '
echo server-start >>"$EVENTS"
echo "$$" >"$STUB_STATE/server.pid"
exec sleep 30'
  stub "$ROOT/scripts/run_with_test_cleanup.sh" '
echo test-cleanup-wrapper >>"$EVENTS"
exit 91'

  cat >"$bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
url="" method="" payload="" secret="" output="" write_out="" fail_http=0
while (($#)); do
  case "$1" in
    http://*|https://*) url="$1"; shift ;;
    -X|--request) method="$2"; shift 2 ;;
    -d|--data|--data-raw|--data-binary) payload="$2"; shift 2 ;;
    -H|--header)
      if [[ "${2,,}" == x-hasura-admin-secret:* ]]; then
        secret="${2#*: }"
      fi
      shift 2 ;;
    -o|--output) output="$2"; shift 2 ;;
    -w|--write-out) write_out="$2"; shift 2 ;;
    -D|--dump-header|-m|--max-time|--connect-timeout) shift 2 ;;
    -sf|-fs|-f|--fail|--fail-with-body) fail_http=1; shift ;;
    -s|-S|-sS|--silent|--show-error) shift ;;
    *) echo "unexpected curl argument: $1" >&2; exit 2 ;;
  esac
done

status=200
body=""
case "$url" in
  http://127.0.0.1:8080/healthz|http://127.0.0.1:4444/status|http://127.0.0.1:2080/_qa/integration/bootstrap) ;;
  http://127.0.0.1:2080/health)
    if [[ "$START_WITHOUT_SERVER" == 1 && ! -s "$STUB_STATE/server.pid" ]]; then
      echo server-health-unavailable >>"$EVENTS"
      exit 7
    fi
    echo server-health-ready >>"$EVENTS"
    ;;
  http://127.0.0.1:2080/api/v2/graphql)
    body="$SCHEMA_BODY"
    ;;
  http://127.0.0.1:8080/v1/metadata)
    case "$(jq -er '.type' <<<"$payload")" in
      reload_remote_schema) body='{"message":"success"}' ;;
      replace_metadata)
        # curl -d sends POST unless the caller explicitly selects a method.
        printf 'replace_metadata|%s|%s|%s|%s\n' "${method:-POST}" "$url" "$secret" \
          "${METADATA_HELPER_RUNNING:-0}" >>"$EVENTS"
        printf '%s\n' "$payload" >"$STUB_STATE/request.json"
        status="$REPLACE_STATUS"
        body="$REPLACE_BODY"
        ;;
      *) echo "unexpected metadata operation" >&2; exit 2 ;;
    esac
    ;;
  https://dev.lvh.me:9443/)
    body=$'HTTP/2 200\ncross-origin-embedder-policy: require-corp\n\n<script src="flutter_bootstrap.js"></script>'
    ;;
  *) echo "unexpected curl URL: $url" >&2; exit 2 ;;
esac

if (( ! fail_http || status < 400 )); then
  if [[ -n "$output" ]]; then
    printf '%s' "$body" >"$output"
  else
    printf '%s' "$body"
  fi
fi
printf '%b' "${write_out//\%\{http_code\}/$status}"
if ((fail_http && status >= 400)); then exit 22; fi
CURL
  chmod +x "$bin/curl"
  stub "$bin/flutter" 'echo "flutter $*" >>"$EVENTS"'
  stub "$bin/docker" 'echo "unexpected docker call: $*" >&2; exit 2'
  stub "$bin/google-chrome" 'echo "Google Chrome 120.0.1.2"'
  stub "$ROOT/.local/chromedriver/chromedriver" 'echo "ChromeDriver 120.0.1.2"'
  stub "$bin/caddy" 'echo "unexpected Caddy start: $*" >&2; exit 2'
  stub "$bin/ss" '
if [[ "$TENTURA_WEB_E2E_WASM" == 1 ]]; then
  echo "LISTEN 0 128 127.0.0.1:9443 0.0.0.0:*"
fi'
  stub "$bin/pgrep" 'exit 1'
  stub "$bin/pkill" 'exit 0'

  RC=0
  env -u HASURA_GRAPHQL_ADMIN_SECRET -u HASURA_URL -u METADATA_FILE -u METADATA_HELPER_RUNNING \
    PATH="$bin:$PATH" EVENTS="$EVENTS" STUB_STATE="$CASE_DIR" SERVER_LOG="$CASE_DIR/server.log" \
    START_WITHOUT_SERVER=0 TENTURA_WEB_E2E_WASM=0 CHROMEDRIVER_PORT=4444 \
    SCHEMA_BODY='{"data":{"__type":{"name":"ConstellationAnchorOpInput"}}}' \
    REPLACE_STATUS="$status" REPLACE_BODY="$body" "$@" \
    timeout --kill-after=2s 20s bash "$ROOT/scripts/run_client_integration_web_local.sh" "$TARGET" \
    >"$OUT" 2>"$ERR" || RC=$?

  [[ "$RC" != 124 && "$RC" != 137 ]] || fail "runner timed out"
  ! grep -qx 'test-cleanup-wrapper' "$EVENTS" || fail "runner invoked run_with_test_cleanup.sh"
}

assert_replaced() {
  local expected_secret="$1"
  [[ "$(grep -c '^replace_metadata|' "$EVENTS")" == 1 ]] \
    || fail "expected exactly one replace_metadata request"
  grep -Fxq "replace_metadata|POST|$METADATA_URL|$expected_secret|1" "$EVENTS" \
    || fail "metadata must be sent by hasura_apply_metadata.sh as POST with the expected admin secret"
  jq -e --slurpfile source "$ROOT/hasura/metadata.json" \
    '.args.metadata == $source[0].metadata' "$CASE_DIR/request.json" >/dev/null \
    || fail "replacement payload must contain the metadata object from hasura/metadata.json"
}

assert_success() {
  local expected_secret="$1"
  [[ "$RC" == 0 ]] || fail "runner must exit 0 after a consistent apply and a passing drive (exit=$RC)"
  [[ "$(grep -c '^flutter drive ' "$EVENTS")" == 1 ]] \
    || fail "runner must drive exactly once"
  grep -qF -- "--target=$TARGET " "$EVENTS" \
    || fail "flutter drive must run the requested target"
  assert_replaced "$expected_secret"
  awk '/^replace_metadata\|/ {replaced=1} /^flutter drive / {exit !replaced}' "$EVENTS" \
    || fail "metadata must be replaced before flutter drive"
  grep -Eiq 'hasura metadata.*(applied|\bok\b)' "$OUT" "$ERR" \
    || fail "runner must report successful Hasura metadata application"
}

assert_rejected() {
  ! grep -q '^flutter drive ' "$EVENTS" \
    || fail "runner reached flutter drive despite the configured Hasura metadata failure (exit=$RC)"
  [[ "$RC" != 0 ]] || fail "runner must exit non-zero when applying metadata fails"
  grep -q '^replace_metadata|' "$EVENTS" \
    || fail "runner must attempt metadata replacement before reporting the failure"
  grep -Eiq '^\[integration\] ERROR:.*hasura metadata' "$ERR" \
    || fail "stderr must contain an integration error naming Hasura metadata"
}

assert_started_server_stopped() {
  [[ -s "$CASE_DIR/server.pid" ]] || fail "fixture did not start a server"
  local pid state
  pid="$(cat "$CASE_DIR/server.pid")"
  for _ in {1..20}; do
    state="$(ps -o stat= -p "$pid" || true)"
    if [[ -z "$state" || "$state" == Z* ]]; then
      rm "$CASE_DIR/server.pid"
      return
    fi
    sleep 0.05
  done
  fail "runner left its server running (pid=$pid)"
}

healthy_server() {
  run_case healthy 200 "$CONSISTENT"
  assert_success password
}

custom_admin_secret() {
  run_case custom-secret 200 "$CONSISTENT" HASURA_GRAPHQL_ADMIN_SECRET=s3cret
  assert_success s3cret
}

server_started_by_runner() {
  run_case delayed-health 200 "$CONSISTENT" START_WITHOUT_SERVER=1
  grep -qx server-health-unavailable "$EVENTS" && grep -qx server-start "$EVENTS" \
    && grep -qx server-health-ready "$EVENTS" \
    || fail "runner must start the unavailable server and wait for a successful health check"
  assert_success password
  awk '
    /^server-health-unavailable$/ {unavailable=1}
    /^server-start$/ && unavailable {started=1}
    /^server-health-ready$/ && started {ready=1}
    /^replace_metadata\|/ {exit !ready}
  ' "$EVENTS" || fail "metadata must be replaced only after server startup and successful health check"
  assert_started_server_stopped
}

schema_failure_after_startup() {
  run_case schema-failure 200 "$CONSISTENT" START_WITHOUT_SERVER=1 \
    SCHEMA_BODY='{"data":{"__type":null}}'
  [[ "$RC" == 1 ]] || fail "runner must exit 1 when the schema probe rejects the server (exit=$RC)"
  grep -Fq 'ERROR: tentura-server schema is outdated or cannot be verified' "$ERR" \
    || fail "runner must report the schema failure"
  ! grep -q '^flutter drive ' "$EVENTS" || fail "runner reached flutter drive despite the schema failure"
  assert_started_server_stopped
}

http_failure() {
  run_case http-failure 400 '{"error":"cannot replace metadata"}'
  assert_rejected
}

error_body() {
  run_case error-body 200 '{"error":"metadata validation failed"}'
  assert_rejected
}

inconsistent_metadata() {
  run_case inconsistent 200 "$INCONSISTENT"
  assert_rejected
  grep -Fq 'lineage_parent_beacon_id' "$OUT" "$ERR" \
    || fail "output must include the reason supplied for the inconsistent Hasura object"
}

wasm_success() {
  run_case wasm 200 "$CONSISTENT" TENTURA_WEB_E2E_WASM=1
  grep -Eq '^flutter drive .*--wasm( |$)' "$EVENTS" || fail "fixture must exercise WASM drive"
  assert_success password
}

wasm_failure() {
  run_case wasm-failure 400 '{"error":"cannot replace metadata"}' TENTURA_WEB_E2E_WASM=1
  assert_rejected
}

failed=0
run_test() {
  local description="$1" test="$2" result
  set +e
  (
    set -e
    "$test"
  )
  result=$?
  set -e
  if ((result == 0)); then
    echo "OK: $description"
  else
    echo "FAIL: $description" >&2
    failed=1
  fi
}

run_test 'applies repository metadata with the default secret before driving the requested target' healthy_server
run_test 'authenticates metadata replacement with the configured Hasura admin secret' custom_admin_secret
run_test 'waits for the server it starts to become healthy before replacing metadata' server_started_by_runner
run_test 'stops the server it starts when the schema probe fails' schema_failure_after_startup
run_test 'reports an HTTP failure applying metadata and skips flutter drive' http_failure
run_test 'reports a metadata error in a successful HTTP response and skips flutter drive' error_body
run_test 'reports the inconsistent object reason and skips flutter drive' inconsistent_metadata
run_test 'applies repository metadata before launching WASM drive' wasm_success
run_test 'skips WASM drive when metadata application fails' wasm_failure
exit "$failed"
