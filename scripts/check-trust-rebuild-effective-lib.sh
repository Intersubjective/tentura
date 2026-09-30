#!/usr/bin/env bash
# Naive repo-root grep for trust_rebuild_effective under packages/server/lib;
# allow only shipped immutable migrations (tentura-2vzj / A5 verify).
set -euo pipefail

ROOT="${TENTURA_TRUST_REBUILD_EFFECTIVE_GREP_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

NEEDLE='trust_rebuild_effective'
GREP_PATH='packages/server/lib'
ALLOW='packages/server/lib/data/database/migration/'

grep_out="$(grep -rn "$NEEDLE" "$GREP_PATH" 2>/dev/null || true)"
if [[ -z "$grep_out" ]]; then
  exit 0
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  path="${line%%:*}"
  if [[ "$path" != *"$ALLOW"* ]]; then
    echo "check-trust-rebuild-effective-lib: non-migration hit: $line" >&2
    exit 1
  fi
done <<<"$grep_out"

exit 0
