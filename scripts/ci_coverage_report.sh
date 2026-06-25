#!/usr/bin/env bash
# Filter lcov artifacts and emit hand-written coverage summary (CI or local).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

server_raw="packages/server/coverage/lcov.info"
client_raw="packages/client/coverage/lcov.info"
server_filtered="packages/server/coverage/lcov.handwritten.info"
client_filtered="packages/client/coverage/lcov.handwritten.info"
merged_filtered="coverage/lcov.handwritten.merged.info"

for raw in "$server_raw" "$client_raw"; do
  if [[ ! -f "$raw" ]]; then
    echo "ci_coverage_report: expected coverage output missing: $raw" >&2
    echo "Run tests with --coverage first (see docs/test-coverage-misses.md)." >&2
    exit 1
  fi
done

bash scripts/coverage_filter_lcov.sh "$server_raw" "$server_filtered"
bash scripts/coverage_filter_lcov.sh "$client_raw" "$client_filtered"

mkdir -p coverage
cat "$server_filtered" "$client_filtered" > "$merged_filtered"

{
  echo "Hand-written coverage (generated paths excluded):"
  echo ""
  while IFS=$'\t' read -r prefix pct hit total; do
    printf -- "- %s: %.1f%% (%s/%s lines)\n" "$prefix" "$pct" "$hit" "$total"
  done < <(bash scripts/coverage_handwritten_summary.sh "$merged_filtered")
  echo ""
  echo "Baseline reference (2026-06-25 audit): ~47% server domain, ~24% client features."
} | tee coverage/handwritten-summary.txt

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Test coverage (hand-written)"
    echo ""
    cat coverage/handwritten-summary.txt
    echo ""
    echo "Raw and filtered \`lcov.info\` files are attached as workflow artifacts."
  } >> "$GITHUB_STEP_SUMMARY"
fi
