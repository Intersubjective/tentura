#!/usr/bin/env bash
# Run the server perf suites (issue #235 U41) one at a time through the test
# cleanup wrapper: the pg-only suites first, then the MeritRank ones, because
# every suite times against the one shared MeritRank service. Reports land in
# packages/server/build/perf/<fixture>.json.
#
# Usage:
#   scripts/perf/run_perf_suite.sh                    run everything, then check
#   scripts/perf/run_perf_suite.sh --print-plan       list the commands only
#   scripts/perf/run_perf_suite.sh --print-output-dir
#   scripts/perf/run_perf_suite.sh --check-reports <dir>
#                                     fail unless every matrix fixture has a
#                                     full report in <dir>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER="$ROOT/packages/server"
WRAPPER="$ROOT/scripts/run_with_test_cleanup.sh"
OUTPUT_DIR="build/perf"

# A perf suite declares `@Tags(['perf', ...])` as its first non-comment line;
# it needs MeritRank exactly when it creates the pgmer2 extension.
suites_of_phase() {
  local phase="$1" file name needs
  for file in "$SERVER"/test/perf/*_test.dart; do
    awk '/^\/\// { next } { exit !/^@Tags\(\[.*perf/ }' "$file" || continue
    needs=pg
    grep -q 'createPgmer2Extension: true' "$file" && needs=mr
    [[ "$needs" == "$phase" ]] || continue
    name="$(basename "$file")"
    echo "$name"
  done
}

command_for() {
  echo "$WRAPPER --timeout 3h -- dart test test/perf/$1 --tags perf -j 1"
}

print_plan() {
  local phase name
  for phase in pg mr; do
    while IFS= read -r name; do
      echo "$phase: $(command_for "$name")"
    done < <(suites_of_phase "$phase")
  done
}

check_reports() {
  local dir
  dir="$(realpath -m -- "$1")"
  cd "$SERVER"
  dart run test/perf/check_perf_reports.dart "$dir"
}

run_all() {
  local phase name failed=0
  cd "$SERVER"
  for phase in pg mr; do
    while IFS= read -r name; do
      echo "== $phase: $name" >&2
      # shellcheck disable=SC2046
      $(command_for "$name") || failed=1
    done < <(suites_of_phase "$phase")
  done
  check_reports "$OUTPUT_DIR" || failed=1
  return "$failed"
}

case "${1:-}" in
  --print-plan) print_plan ;;
  --print-output-dir) echo "$OUTPUT_DIR" ;;
  --check-reports)
    [[ $# -eq 2 ]] || { echo "usage: $0 --check-reports <dir>" >&2; exit 2; }
    check_reports "$2"
    ;;
  "") run_all ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac
