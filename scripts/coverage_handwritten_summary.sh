#!/usr/bin/env bash
# Print hand-written line-coverage percentages for key paths from filtered lcov.
set -euo pipefail

lcov_file="${1:?usage: coverage_handwritten_summary.sh LCOV [PATH_PREFIX...]}"

if [[ ! -f "$lcov_file" ]]; then
  echo "coverage_handwritten_summary: missing lcov: $lcov_file" >&2
  exit 1
fi

if (($# < 2)); then
  set -- "$lcov_file" \
    "packages/server/lib/domain" \
    "packages/client/lib/features"
fi

shift

awk -v targets="${*}" '
BEGIN {
  n = split(targets, t, " ")
  for (i = 1; i <= n; i++) {
    prefix[i] = t[i]
    hit[i] = 0
    total[i] = 0
  }
}
function match_target(path,    i) {
  for (i = 1; i <= n; i++) {
    if (index(path, prefix[i]) > 0) return i
  }
  return 0
}
/^SF:/ {
  current = match_target(substr($0, 4))
}
current && /^DA:/ {
  split(substr($0, 4), da, ",")
  line = da[1] + 0
  hits = da[2] + 0
  if (line > 0) {
    total[current]++
    if (hits > 0) hit[current]++
  }
}
END {
  for (i = 1; i <= n; i++) {
    pct = (total[i] > 0) ? (100.0 * hit[i] / total[i]) : 0
    printf "%s\t%.1f\t%d\t%d\n", prefix[i], pct, hit[i], total[i]
  }
}
' "$lcov_file"
