#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/hasura_check_metadata.sh"
APPLY="$ROOT/scripts/hasura_apply_metadata.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# Replace only the HTTP transport. Check the request before serving the
# fixture so a script that only prints a status cannot pass.
cat > curl <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
url= method= secret= payload= output= write_out=
while (($#)); do
  case "$1" in
    -H|--header)
      if [[ "${2,,}" == x-hasura-admin-secret:* ]]; then
        secret="${2#*:}"
        secret="${secret# }"
      fi
      shift 2 ;;
    -d|--data|--data-raw|--data-binary|--json)
      payload="$2"; shift 2 ;;
    -X|--request) method="$2"; shift 2 ;;
    -o|--output) output="$2"; shift 2 ;;
    -w|--write-out) write_out="$2"; shift 2 ;;
    -m|--max-time|--connect-timeout) shift 2 ;;
    --url) url="$2"; shift 2 ;;
    http://*|https://*) url="$1"; shift ;;
    -*) shift ;;
    *)
      printf '%s\n' invalid >>"$REQUEST_LOG"
      echo "Unexpected curl argument: $1" >&2
      exit 2 ;;
  esac
done
expected_operation=get_inconsistent_metadata
payload_shape='(.args // {}) == {}'
if [[ "$SCENARIO" == apply ]]; then
  expected_operation=replace_metadata
  payload_shape='.args.metadata | type == "object"'
  if [[ "$(jq -r .type <<<"$payload")" == reload_remote_schema ]]; then
    exit 0
  fi
fi
if [[ -z "$url" || -z "$secret" || "${method:-POST}" != POST ]] ||
    ! jq -e --arg type "$expected_operation" ".type == \$type and ($payload_shape)" \
      <<<"$payload" >/dev/null; then
  printf '%s\n' invalid >>"$REQUEST_LOG"
  echo 'Unexpected Hasura metadata request' >&2
  exit 2
fi
printf '%s\t%s\n' "$url" "$secret" >>"$REQUEST_LOG"
if [[ "$SCENARIO" == unreachable ]]; then
  echo 'curl: (7) Failed to connect to metadata.test' >&2
  exit 7
fi

body='{"is_consistent":true,"inconsistent_objects":[]}'
if [[ "$SCENARIO" == inconsistent ]]; then
  body='{"is_consistent":false,"inconsistent_objects":[
    {"name":"table beacon_bud_observer in source default","type":"table",
     "reason":"relation public.beacon_bud_observer does not exist"},
    {"name":"select permission on beacon for role user","type":"select_permission",
     "reason":"column lineage_parent_beacon_id does not exist"}
  ]}'
fi
if [[ -n "$output" && "$output" != - ]]; then
  printf '%s' "$body" >"$output"
else
  printf '%s' "$body"
fi
printf '%b' "${write_out//\%\{http_code\}/200}"
CURL
chmod +x curl
command -v jq >/dev/null || { echo 'Test requires jq' >&2; exit 2; }
printf '%s\n' '{"metadata":{"version":3,"sources":[]}}' >metadata.json

reference_request() {
  local hasura_url="$1" admin_secret="$2"
  : >reference
  if ! env PATH="$WORK:$PATH" REQUEST_LOG="$WORK/reference" SCENARIO=apply \
    HASURA_URL="$hasura_url" HASURA_GRAPHQL_ADMIN_SECRET="$admin_secret" \
    METADATA_FILE="$WORK/metadata.json" timeout 5s bash "$APPLY" >apply.log 2>&1; then
    echo 'FAIL: could not observe the apply command Metadata API request' >&2
    cat apply.log >&2
    return 1
  fi
  local endpoint used_secret
  IFS=$'\t' read -r endpoint used_secret <reference
  # With no override, the observed apply request supplies the default endpoint.
  [[ "$used_secret" == "$admin_secret" && "$endpoint" == */v1/metadata &&
    ( -z "$hasura_url" || "$endpoint" == "${hasura_url%/}/v1/metadata" ) ]] || {
    echo 'FAIL: the apply command did not use the expected endpoint and admin secret' >&2
    return 1
  }
}

run_case() {
  local scenario="$1" description="$2" hasura_url="$3"
  local admin_secret="fixture-${WORK##*/}-$scenario"
  local secret_input=("HASURA_GRAPHQL_ADMIN_SECRET=$admin_secret")
  if [[ "$scenario" == missing-secret ]]; then
    secret_input=(-u HASURA_GRAPHQL_ADMIN_SECRET)
  else
    reference_request "$hasura_url" "$admin_secret" || return 1
  fi
  if [[ ! -f "$CHECK" ]]; then
    printf 'FAIL: %s (missing operator command scripts/hasura_check_metadata.sh)\n' "$description" >&2
    return 1
  fi

  local status=0 request_log="$WORK/requests"
  : >"$request_log"
  env PATH="$WORK:$PATH" REQUEST_LOG="$request_log" SCENARIO="$scenario" \
    HASURA_URL="$hasura_url" env "${secret_input[@]}" \
    timeout --verbose --kill-after=1s 5s bash "$CHECK" >stdout 2>stderr || status=$?

  if ((status >= 124)) || rg -q '^timeout: sending signal' stderr; then
    printf 'FAIL: %s (checker timed out or did not exit normally, status %s)\n' \
      "$description" "$status" >&2
    cat stdout stderr >&2
    return 1
  fi
  local passed=no failed=no
  ((status == 0)) || failed=yes
  if [[ "$scenario" == missing-secret ]]; then
    if [[ "$failed" == yes ]] &&
      rg -qi 'secret|HASURA_GRAPHQL_ADMIN_SECRET' stdout stderr; then
      passed=yes
    fi
  elif [[ -s "$request_log" ]] && ! rg -qFvx -- "$(cat reference)" "$request_log"; then
    case "$scenario" in
      consistent)
        if [[ "$status" == 0 && "$(awk 'END { print NR }' stdout)" == 1 ]] &&
          rg -q '\bOK\b' stdout; then
          passed=yes
        fi ;;
      inconsistent)
        if [[ "$failed" == yes ]] &&
          cat stdout stderr | awk '
            /table beacon_bud_observer in source default/ { table = 1 }
            /relation public\.beacon_bud_observer does not exist/ { relation = 1 }
            /select permission on beacon for role user/ { permission = 1 }
            /column lineage_parent_beacon_id does not exist/ { lineage = 1 }
            END { exit !(table && relation && permission && lineage) }
          '; then
          passed=yes
        fi ;;
      unreachable)
        if [[ "$failed" == yes ]] &&
          rg -qi 'failed|unreachable|connect|transport|network' stdout stderr; then
          passed=yes
        fi ;;
    esac
  fi
  if [[ "$scenario" != consistent ]] && rg -q '\bOK\b' stdout stderr; then
    passed=no
  fi
  if [[ "$passed" == yes ]]; then
    printf 'OK: %s\n' "$description"
  else
    printf 'FAIL: %s (exit %s)\n' "$description" "$status" >&2
    cat "$request_log" stdout stderr >&2
    return 1
  fi
}

failures=0
run_case consistent 'consistent metadata returns a one-line OK' \
  'http://metadata.test:8181/api/' || failures=$((failures + 1))
run_case inconsistent 'inconsistent metadata fails and reports every object name and reason' \
  'http://other-metadata.test:8282/internal' || failures=$((failures + 1))
run_case unreachable 'an unreachable Metadata API fails with an error' \
  '' || failures=$((failures + 1))
run_case missing-secret 'a missing admin secret fails with an error' \
  'http://metadata.test:8181/api/' || failures=$((failures + 1))
[[ "$failures" == 0 ]]
