#!/usr/bin/env bash
# Check the running Hasura Metadata API without changing its metadata.
set -euo pipefail

HASURA_URL="${HASURA_URL:-http://127.0.0.1:8080}"
if [[ -z "${HASURA_GRAPHQL_ADMIN_SECRET:-}" ]]; then
  echo 'Error: HASURA_GRAPHQL_ADMIN_SECRET is required' >&2
  exit 1
fi

if ! response="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
  "${HASURA_URL%/}/v1/metadata" \
  -H "X-Hasura-Admin-Secret: $HASURA_GRAPHQL_ADMIN_SECRET" \
  -H 'Content-Type: application/json' \
  -d '{"type":"get_inconsistent_metadata","args":{}}')"; then
  echo 'Error: Hasura Metadata API request failed' >&2
  exit 1
fi

jq -ers '
  if length != 1 or (.[0] | type) != "object" then
    error("Expected one Hasura metadata response object")
  else .[0] end
  | if .is_consistent == true then
      "Hasura metadata is consistent: OK"
    elif .is_consistent == false and (.inconsistent_objects | type) == "array" then
      (["Error: Hasura metadata is inconsistent"]
       + [.inconsistent_objects[] | "\(.name): \(.reason)"]
       | join("\n") + "\n" | halt_error(1))
    else
      error("Invalid Hasura metadata consistency response")
    end
' <<<"$response"
