#!/usr/bin/env bash
# Remove generated Dart sources from lcov.info for hand-written coverage metrics.
set -euo pipefail

input="${1:?usage: coverage_filter_lcov.sh INPUT [OUTPUT]}"
output="${2:-${input%.info}.handwritten.info}"

if [[ ! -f "$input" ]]; then
  echo "coverage_filter_lcov: missing input: $input" >&2
  exit 1
fi

if command -v lcov >/dev/null 2>&1; then
  lcov --remove "$input" \
    '**/*.g.dart' \
    '**/*.freezed.dart' \
    '**/*.gr.dart' \
    '**/*.config.dart' \
    '**/*/_g/*' \
    '**/*.mocks.dart' \
    --output-file "$output" \
    --ignore-errors unused,empty,format \
    --rc lcov_branch_coverage=0
  exit 0
fi

awk '
function is_generated(path,    n) {
  n = split(path, parts, "/")
  file = parts[n]
  if (file ~ /\.g\.dart$/) return 1
  if (file ~ /\.freezed\.dart$/) return 1
  if (file ~ /\.gr\.dart$/) return 1
  if (file ~ /\.config\.dart$/) return 1
  if (file ~ /\.mocks\.dart$/) return 1
  if (path ~ /\/_g\//) return 1
  return 0
}
/^SF:/ {
  path = substr($0, 4)
  drop = is_generated(path)
}
{
  if (!drop) print
}
/^end_of_record$/ {
  drop = 0
}
' "$input" > "$output"
