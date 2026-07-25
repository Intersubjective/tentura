#!/usr/bin/env bash
#
# Runs `dart analyze` for a package and enforces the tentura_lints custom rules.
#
# Why this exists instead of a plain `flutter analyze` / `dart analyze` step:
#
#   1. `flutter analyze` does not load analyzer plugins at all, so it never
#      reports a single tentura_lints diagnostic. Only `dart analyze` does.
#   2. Plugin diagnostics appear only when the analysis target is the package
#      root (`dart analyze` with no argument) or a single file. Passing a
#      subdirectory (`dart analyze lib`) silently drops them.
#   3. Most custom rules report at `info` severity, which `dart analyze` never
#      treats as fatal, so they cannot gate CI on their own. Plugin diagnostics
#      also honour neither `analyzer: errors:` severity overrides nor
#      `// ignore:` comments, so severity cannot be raised in config either.
#
# Hence: run the analyzer correctly, then ratchet the custom-rule count against
# a checked-in baseline. New violations fail; fixing violations below the
# baseline asks you to lower it.
#
# Usage: scripts/check-custom-lints.sh <package-dir>
#        (baselines live in scripts/custom-lint-baseline.txt)

set -euo pipefail

PKG="${1:?usage: check-custom-lints.sh <package-dir>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_FILE="$REPO_ROOT/scripts/custom-lint-baseline.txt"

CUSTOM_RULES='no_domain_to_data_or_ui_import|no_cubit_to_data_service_import|no_map_dynamic_in_use_case_api|no_raw_graphql_in_dart|no_inline_font_size|cubit_requires_use_case_for_multi_repos|no_operational_raw_color|no_operational_raw_text_style|no_operational_pill_widgets_in_beacon_view|no_raw_edge_insets|no_raw_border_radius|no_request_domain_entity|use_tentura_top_bar'

baseline="$(awk -v p="$PKG" '$1 == p { print $2 }' "$BASELINE_FILE")"
if [[ -z "$baseline" ]]; then
  echo "check-custom-lints: no baseline for '$PKG' in $BASELINE_FILE" >&2
  exit 2
fi

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

cd "$REPO_ROOT/$PKG"

# No target argument on purpose: see note (2) above.
set +e
dart analyze --no-fatal-warnings >"$out" 2>&1
analyze_status=$?
set -e

cat "$out"

if [[ $analyze_status -ne 0 ]]; then
  echo "check-custom-lints: dart analyze failed for $PKG (errors present)" >&2
  exit "$analyze_status"
fi

# `dart analyze` can emit the same diagnostic more than once for a file that is
# reachable through several analysis roots; dedupe on rule + file:line:col.
# `grep` exits 1 on a clean package, which `set -o pipefail` would turn into a
# script failure — hence the explicit `|| true`.
hits="$(mktemp)"
trap 'rm -f "$out" "$hits"' EXIT
{ grep -E "^[[:space:]]+(info|warning|error) - .* - ($CUSTOM_RULES)\$" "$out" \
    | sed -E 's/^[[:space:]]+[a-z]+ - ([^ ]+) - .* - ([a-z_]+)$/\2 \1/' \
    | sort -u; } >"$hits" || true

count="$(wc -l <"$hits" | tr -d ' ')"

echo
echo "── tentura_lints: $PKG ──"
if [[ "$count" -gt 0 ]]; then
  awk '{ print $1 }' "$hits" | sort | uniq -c | sort -rn
fi
echo "total: $count (baseline: $baseline)"

if [[ "$count" -gt "$baseline" ]]; then
  echo >&2
  echo "check-custom-lints: $PKG has $count custom-rule violations, baseline is $baseline." >&2
  echo "Fix the new violations — do not raise the baseline." >&2
  exit 1
fi

if [[ "$count" -lt "$baseline" ]]; then
  echo
  echo "check-custom-lints: $PKG is down to $count (baseline $baseline)."
  echo "Lower the baseline in $BASELINE_FILE to lock the improvement in."
fi

echo "check-custom-lints: $PKG OK"
