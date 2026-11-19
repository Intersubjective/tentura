#!/usr/bin/env bash
#
# Ratcheting gate for plain `dart analyze` / `flutter analyze`.
#
# Pre-existing analyzer debt must not block every task, but must not grow:
# any analyzer error fails; otherwise the total issue count may not exceed the
# checked-in baseline in scripts/analyze-baseline.txt. Lower the baseline when
# you fix issues. (Custom tentura_lints rules are gated by check-custom-lints.sh.)
#
# Usage: scripts/check-analyze-baseline.sh <package-dir> [<scoped-path>]
#   packages/client uses `flutter analyze`, packages/server `dart analyze`.
#   A scoped path is keyed as "<package-dir>:<scoped-path>" in the baseline.
#   Failed analysis retains its complete output at the printed report path.
#   analyze-baseline-inventory.tsv records existing diagnostics as key<TAB>line
#   (sorted unique lines per key, including both CLI formats for the client).
#   TENTURA_ANALYZER_CAPTURE writes validated rows for the debt generator.
#   TENTURA_ANALYZER_DEBT_DIR selects the debt files for the live inventory test.

set -euo pipefail

PKG="${1:?usage: check-analyze-baseline.sh <package-dir> [<scoped-path>]}"
SCOPE="${2:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBT_DIR="${TENTURA_ANALYZER_DEBT_DIR:-$REPO_ROOT/scripts}"
[[ "$DEBT_DIR" = /* ]] || DEBT_DIR="$PWD/$DEBT_DIR"
BASELINE_FILE="$DEBT_DIR/analyze-baseline.txt"
INVENTORY_FILE="$DEBT_DIR/analyze-baseline-inventory.tsv"

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "check-analyze-baseline: missing baseline file $BASELINE_FILE" >&2
  exit 2
fi

# Validate the baseline: 2 fields, nonnegative integer, no duplicate keys,
# and a row for each package.
if ! awk '
  /^[[:space:]]*(#|$)/ { next }
  {
    if (NF != 2 || $2 !~ /^[0-9]+$/ || ($1 in seen)) { bad = 1 }
    seen[$1] = 1
  }
  END {
    if (!("packages/client" in seen) || !("packages/server" in seen)) bad = 1
    exit bad
  }' "$BASELINE_FILE"; then
  echo "check-analyze-baseline: invalid baseline file $BASELINE_FILE" >&2
  exit 2
fi

KEY="$PKG"
[[ -n "$SCOPE" ]] && KEY="$PKG:$SCOPE"
baseline="$(awk -v k="$KEY" '$1 == k { print $2 }' "$BASELINE_FILE")"
if [[ -z "$baseline" ]]; then
  echo "check-analyze-baseline: no baseline for '$KEY' in $BASELINE_FILE" >&2
  exit 2
fi

case "$PKG" in
  packages/client) tool=flutter ;;
  packages/server) tool=dart ;;
  *)
    echo "check-analyze-baseline: no baseline for unknown package '$PKG'" >&2
    exit 2
    ;;
esac

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

cd "$REPO_ROOT/$PKG"

# Generated sources are gitignored; bootstrap when absent (as check-custom-lints.sh).
if [[ "$PKG" == "packages/client" ]]; then
  if [[ ! -f lib/ui/l10n/l10n.dart || ! -f lib/app/router/root_router.gr.dart ]]; then
    echo "check-analyze-baseline: bootstrapping packages/client codegen..."
    flutter gen-l10n
    dart run build_runner build -d
  fi
elif [[ ! -f lib/domain/entity/jwt_entity.freezed.dart \
     || ! -f lib/data/database/tentura_db.g.dart ]]; then
  echo "check-analyze-baseline: bootstrapping packages/server codegen..."
  dart run build_runner build -d
fi

# CI shares one analyzer run with check-custom-lints.sh. Client Flutter
# analysis can also emit plugin hits, so use the same rule list in both paths.
custom_rules=
if [[ -n "${TENTURA_ANALYZER_OUTPUT:-}" ]]; then
  if [[ -n "$SCOPE" ]]; then
    echo "check-analyze-baseline: a shared analyzer output cannot serve a scoped run" >&2
    exit 2
  fi
  custom_rules="${TENTURA_CUSTOM_LINT_RULES:?TENTURA_CUSTOM_LINT_RULES must accompany TENTURA_ANALYZER_OUTPUT}"
  cp -- "$TENTURA_ANALYZER_OUTPUT" "$out"
  analyze_status="${TENTURA_ANALYZER_STATUS:?TENTURA_ANALYZER_STATUS must accompany TENTURA_ANALYZER_OUTPUT}"
else
  if [[ "$PKG" == "packages/client" ]]; then
    custom_rules="$(bash "$REPO_ROOT/scripts/check-custom-lints.sh" --print-rules)"
  fi
  # Package-level runs target the package root so plugin diagnostics surface.
  target="${SCOPE:-.}"
  set +e
  "$tool" analyze "$target" >"$out" 2>&1
  analyze_status=$?
  set -e
fi

# A shared output was already printed by check-custom-lints.sh.
[[ -n "${TENTURA_ANALYZER_OUTPUT:-}" ]] || cat "$out"

# Count unique diagnostics: the analyzer sometimes reports the same issue
# twice (seen for hook/build and tool/ files in CI), which made the gate
# flaky (2122 vs 2126 for identical sources).
raw_diagnostics="$(grep -E '^[[:space:]]*(error|warning|info) (•|-) ' "$out" | LC_ALL=C sort -u || true)"
errors="$(printf '%s\n' "$raw_diagnostics" | grep -cE '^[[:space:]]*error ' || true)"
diagnostics="$raw_diagnostics"
if [[ -n "$custom_rules" ]]; then
  diagnostics="$(printf '%s\n' "$raw_diagnostics" | grep -Ev " (•|-) (tentura_lints/)?($custom_rules)\$" || true)"
fi
total="$(printf '%s\n' "$diagnostics" | grep -c . || true)"

fail_analysis() {
  echo "check-analyze-baseline: $1" >&2
  if [[ -n "${2:-}" ]]; then
    printf '%s\n' "$2" >&2
  fi
  # Keep our own output, including when the CI driver removes its shared log.
  # Reuse the uniquely allocated file so concurrent runs cannot overwrite it.
  trap - EXIT
  echo "check-analyze-baseline: full analyzer report: $out" >&2
  exit 1
}

# Exit 0-3 are the analyzer's own verdicts (clean / info / warning / error; the
# diagnostics are gated below). Anything else (crash 255, usage error 64) or an
# unhandled exception / SDK write failure on stderr means it did not complete,
# even if it still printed a summary line. A plugin setup failure can be
# reported on a successful run too, which means plugin diagnostics never ran
# (as check-custom-lints.sh).
if [[ "$analyze_status" -gt 3 ]] \
  || [[ "$analyze_status" -ne 0 && -z "$raw_diagnostics" ]] \
  || grep -Eq '^(Unhandled exception:|[A-Za-z]*FileSystemException)' "$out" \
  || grep -Eq 'An error occurred while (executing an analyzer plugin|setting up the analyzer plugin)' "$out" \
  || ! grep -Eq '^[[:space:]]*([0-9]+ issues? found\.|No issues found!)' "$out"; then
  fail_analysis "analyzer did not complete for $KEY (exit $analyze_status)"
fi

if [[ "$errors" -gt 0 ]]; then
  fail_analysis "$errors analyzer error(s) in $KEY"
fi
if [[ "$total" -gt "$baseline" ]]; then
  if [[ -f "$INVENTORY_FILE" ]]; then
    # Compare exact diagnostic lines, using the same extraction and uniqueness
    # as the count above. Use one locale for both sides of the set difference.
    new_diagnostics="$(comm -23 \
      <(printf '%s\n' "$diagnostics" | sed '/^$/d') \
      <(awk -F '\t' -v k="$KEY" '$1 == k { sub(/^[^\t]*\t/, ""); print }' "$INVENTORY_FILE" | LC_ALL=C sort -u))"
  else
    new_diagnostics="check-analyze-baseline: missing diagnostic inventory $INVENTORY_FILE; cannot identify new issues."
  fi
  fail_analysis "$KEY has $total issues, baseline is $baseline." "$new_diagnostics"
fi
if [[ -n "${TENTURA_ANALYZER_CAPTURE:-}" ]]; then
  # Reuse the gate's exact extraction, validation and ratchet in the generator.
  # A clean analyzer has no rows (not a single blank row).
  printf '%s\n' "$diagnostics" | sed '/^$/d' >"$TENTURA_ANALYZER_CAPTURE"
fi
if [[ "$total" -lt "$baseline" ]]; then
  echo "check-analyze-baseline: $KEY improved ($total < $baseline); run \`python3 scripts/generate_analyze_baseline.py\` to refresh both debt files."
fi
echo "check-analyze-baseline: $KEY OK ($total <= $baseline)"
