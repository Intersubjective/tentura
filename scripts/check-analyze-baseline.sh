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

set -euo pipefail

PKG="${1:?usage: check-analyze-baseline.sh <package-dir> [<scoped-path>]}"
SCOPE="${2:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_FILE="$REPO_ROOT/scripts/analyze-baseline.txt"

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

# Package-level runs target the package root so plugin diagnostics surface.
target="${SCOPE:-.}"
set +e
"$tool" analyze "$target" >"$out" 2>&1
set -e

cat "$out"

# Count unique diagnostics: the analyzer sometimes reports the same issue
# twice (seen for hook/build and tool/ files in CI), which made the gate
# flaky (2122 vs 2126 for identical sources).
errors="$(grep -E '^[[:space:]]*error (•|-) ' "$out" | sort -u | wc -l || true)"
total="$(grep -E '^[[:space:]]*(error|warning|info) (•|-) ' "$out" | sort -u | wc -l || true)"

if [[ "$errors" -gt 0 ]]; then
  echo "check-analyze-baseline: $errors analyzer error(s) in $KEY" >&2
  exit 1
fi
if [[ "$total" -gt "$baseline" ]]; then
  echo "check-analyze-baseline: $KEY has $total issues, baseline is $baseline." >&2
  exit 1
fi
if [[ "$total" -lt "$baseline" ]]; then
  echo "check-analyze-baseline: $KEY improved ($total < $baseline); lower its baseline in $BASELINE_FILE."
fi
echo "check-analyze-baseline: $KEY OK ($total <= $baseline)"
