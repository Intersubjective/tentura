#!/usr/bin/env bash
# Apply hasura/metadata.json to a running Hasura Metadata API (local dev compose).
#
# Defaults match compose.dev.yaml: host Hasura on port 8080, admin secret "password".
#
# Usage:
#   ./scripts/hasura_apply_metadata.sh
#   HASURA_URL=http://127.0.0.1:8080 HASURA_GRAPHQL_ADMIN_SECRET=secret ./scripts/hasura_apply_metadata.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
METADATA_FILE="${METADATA_FILE:-$ROOT/hasura/metadata.json}"
HASURA_URL="${HASURA_URL:-http://127.0.0.1:8080}"
ADMIN_SECRET="${HASURA_GRAPHQL_ADMIN_SECRET:-password}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "error: metadata file not found: $METADATA_FILE" >&2
  exit 1
fi

payload="$(jq -n --argjson metadata "$(jq '.metadata' "$METADATA_FILE")" \
  '{type: "replace_metadata", args: {metadata: $metadata}}')"

# Refresh remote schema introspection before replace. If the Tentura API
# changes scalars (e.g. image.created_at), Hasura can stay inconsistent until
# reload; replace_metadata then fails with errors like "Could not find type
# timestamptz" even when the live remote already exposes Date.
curl -sS -o /dev/null -X POST "${HASURA_URL%/}/v1/metadata" \
  -H "X-Hasura-Admin-Secret: ${ADMIN_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{"type":"reload_remote_schema","args":{"name":"tentura"}}' || true

resp="$(curl -sS -w '\n%{http_code}' "${HASURA_URL%/}/v1/metadata" \
  -H "X-Hasura-Admin-Secret: ${ADMIN_SECRET}" \
  -H "Content-Type: application/json" \
  -d "$payload")"

body="$(echo "$resp" | head -n -1)"
code="$(echo "$resp" | tail -n 1)"

if [[ "$code" != "200" ]]; then
  echo "error: Hasura returned HTTP $code" >&2
  echo "$body" >&2
  exit 1
fi

if echo "$body" | jq -e '.error' >/dev/null 2>&1; then
  echo "error: Hasura metadata API reported failure:" >&2
  echo "$body" | jq . >&2
  exit 1
fi

if echo "$body" | jq -e '.is_consistent == false' >/dev/null 2>&1; then
  echo "error: Hasura metadata is inconsistent:" >&2
  echo "$body" | jq . >&2
  exit 1
fi

echo "Hasura metadata applied OK (${HASURA_URL})"
echo "$body" | jq . 2>/dev/null || echo "$body"
