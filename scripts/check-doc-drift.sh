#!/usr/bin/env bash
# Flag legacy product/implementation terms in docs/ (post-cleanup drift guard).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PATTERNS=(
  'Registry tab'
  'Overview tab'
  'coordination_status column'
  'beacon\.state'
  'ChatNews'
  'beacon_blocker'
)

found=0
for pat in "${PATTERNS[@]}"; do
  if rg -n --glob 'docs/**' --glob '!docs/README.md' "$pat" docs/ 2>/dev/null; then
    found=1
  fi
done

if [[ $found -eq 0 ]]; then
  echo "check-doc-drift: no legacy terms in docs/"
  exit 0
fi
echo "check-doc-drift: legacy terms found (review or update docs)" >&2
exit 1
