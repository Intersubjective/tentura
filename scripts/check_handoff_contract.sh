#!/usr/bin/env bash
# Pins the landing<->app session-handoff key/field names across both sides so a
# rename on one side can never silently break the handoff (see Risk #6 and
# docs/handoff-contract.md). Both source files carry a sentinel line:
#   key=th v userId seed displayName
# This asserts that line matches the canonical set verbatim in each file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CANONICAL='key=th v userId seed displayName'

LANDING="$ROOT/packages/landing/handoff.js"
CLIENT="$ROOT/packages/client/lib/features/auth/data/service/handoff_codec.dart"
CONTRACT="$ROOT/docs/handoff-contract.md"

fail=0

check() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "::error::check_handoff_contract: missing $file"
    fail=1
    return
  fi
  # Take the part after "key=", collapse whitespace, strip trailing comment cruft.
  local line
  line="$(grep -oE 'key=th[ a-zA-Z]*' "$file" | head -n1 | tr -s ' ' | sed 's/ *$//' || true)"
  if [[ "$line" != "$CANONICAL" ]]; then
    echo "::error::check_handoff_contract: handoff field names in $file"
    echo "  expected: $CANONICAL"
    echo "  found:    ${line:-<none>}"
    fail=1
  fi
}

check "$LANDING"
check "$CLIENT"
check "$CONTRACT"

if [[ "$fail" -ne 0 ]]; then
  echo "::error::Handoff key/field names diverged. Keep packages/landing/handoff.js,"
  echo "         web_handoff_web.dart, and docs/handoff-contract.md in sync."
  exit 1
fi

echo "check_handoff_contract: OK ($CANONICAL)"
