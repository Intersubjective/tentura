#!/usr/bin/env bash
# Regression for tentura-py46: dev-up must finish when infra is healthy but
# Hasura's Tentura remote schema is temporarily unreachable. Either waiting
# for the API before applying metadata or retrying metadata may satisfy this.
# Like test_run_realtime_multiclient_web_local.sh, run real scripts in a
# scratch checkout with fake external services; never touch local infra/.env.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT
ROOT="$TMP_BASE/root"
BIN="$TMP_BASE/bin"
LOG="$TMP_BASE/calls.log"
mkdir -p "$ROOT/scripts" "$ROOT/hasura" "$BIN" "$TMP_BASE/state"
: >"$LOG"
printf '0\n' >"$TMP_BASE/state/api_contacts"
cp "$REAL_ROOT/scripts/dev-up.sh" "$ROOT/scripts/"
cp "$REAL_ROOT/scripts/hasura_apply_metadata.sh" "$ROOT/scripts/"
cp "$REAL_ROOT/hasura/metadata.json" "$ROOT/hasura/"
printf 'JWT_PUBLIC_PEM=example-placeholder\n' >"$ROOT/.env.example"
printf 'JWT_PUBLIC_PEM=already-generated-dev-key\n' >"$ROOT/.env"

stub() {
  printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$2" >"$1"
  chmod +x "$1"
}

stub "$BIN/docker" '
echo "docker|$*" >>"$CALL_LOG"
case "$1" in
  compose) exit 0 ;;
  inspect) echo healthy ;;
  *) echo "Unexpected docker call: $*" >&2; exit 1 ;;
esac'

stub "$ROOT/scripts/run-server-local.sh" '
echo "server-start" >>"$CALL_LOG"'

# Time is represented by API contacts: first two see connection-refused,
# then the service becomes ready. This covers health polling and metadata
# retries without requiring a specific fix or real background processes.
stub "$BIN/curl" '
url=""; payload=""; output=""; write_out=""; fail_http=0
while (($#)); do
  case "$1" in
    -o|--output) output="$2"; shift 2 ;;
    -w|--write-out) write_out="$2"; shift 2 ;;
    -d|--data|--data-raw|--data-binary) payload="$2"; shift 2 ;;
    -H|--header|-X|--request|-m|--max-time|--connect-timeout)
      shift 2 ;;
    http://*|https://*) url="$1"; shift ;;
    --fail|--fail-with-body) fail_http=1; shift ;;
    -*) [[ "$1" != --* && "$1" == *f* ]] && fail_http=1; shift ;;
    *) echo "Unexpected curl argument: $1" >&2; exit 1 ;;
  esac
done
status=200; body=""
case "$url" in
  http://127.0.0.1:8080/healthz)
    echo "hasura-health|200" >>"$CALL_LOG" ;;
  http://127.0.0.1:2080/health|http://127.0.0.1:8080/v1/metadata)
    contacts="$(cat "$STATE_DIR/api_contacts")"
    contacts=$((contacts + 1))
    printf "%s\n" "$contacts" >"$STATE_DIR/api_contacts"
    ready=no
    if ((contacts >= 3)); then ready=yes; fi
    if [[ "$url" == */health ]]; then
      echo "api-health|ready=$ready" >>"$CALL_LOG"
      if [[ "$ready" == no ]]; then exit 7; fi
    else
      operation="$(jq -r .type <<<"$payload")"
      echo "metadata|$operation|ready=$ready" >>"$CALL_LOG"
      if [[ "$ready" == no ]]; then
        status=400
        body="{\"error\":\"cannot continue due to inconsistent metadata\",\"internal\":[{\"name\":\"remote_schema tentura\",\"reason\":\"Connection refused: {{TENTURA_GRAPHQL_URL}}\"}]}"
      else
        body="{\"is_consistent\":true,\"inconsistent_objects\":[]}"
        if [[ "$operation" == replace_metadata ]]; then
          touch "$STATE_DIR/metadata_applied"
        fi
      fi
    fi ;;
  *) echo "Unexpected curl URL: $url" >&2; exit 1 ;;
esac
if [[ "$output" != /dev/null ]]; then
  if [[ -n "$output" ]]; then printf "%s" "$body" >"$output"
  else printf "%s" "$body"; fi
fi
printf "%b" "${write_out//\%\{http_code\}/$status}"
if ((fail_http && status >= 400)); then exit 22; fi'

stub "$BIN/sleep" 'echo "sleep|$*" >>"$CALL_LOG"'

set +e
env -u METADATA_FILE -u HASURA_URL -u HASURA_GRAPHQL_ADMIN_SECRET \
  PATH="$BIN:$PATH" CALL_LOG="$LOG" STATE_DIR="$TMP_BASE/state" \
  timeout 20s bash "$ROOT/scripts/dev-up.sh" >"$TMP_BASE/output.log" 2>&1
rc=$?
set -e

fail() {
  echo "FAIL: $1" >&2
  cat "$TMP_BASE/output.log" >&2
  sed 's/^/  call: /' "$LOG" >&2
  exit 1
}

[[ "$rc" == 0 ]] || fail "dev-up must survive temporary remote-schema connection refusal and complete (exit=$rc)"
[[ -f "$TMP_BASE/state/metadata_applied" ]] \
  || fail "dev-up must apply consistent metadata after the Tentura API becomes ready"
grep -q '^metadata|replace_metadata|ready=yes$' "$LOG" \
  || fail "metadata replacement must succeed against a ready Tentura API"
echo "OK: dev-up completes and applies metadata despite delayed Tentura API readiness"
