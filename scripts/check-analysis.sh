#!/usr/bin/env bash
#
# Both analyzer gates for a package from ONE analyzer run.
#
# check-custom-lints.sh and check-analyze-baseline.sh each run the analyzer
# when called on their own (that is what local runs and AGENTS.md use). In CI
# that analysed every package twice. This runs the plugin-loading
# `dart analyze` once and hands its output to both gates:
#   * check-custom-lints.sh ratchets the tentura_lints rule hits;
#   * check-analyze-baseline.sh ratchets everything else — the same
#     diagnostics `flutter analyze` reports (verified identical on
#     packages/client: 1926 = 1926 once the custom-rule hits are removed).
#
# Usage: scripts/check-analysis.sh <package-dir>

set -euo pipefail

PKG="${1:?usage: check-analysis.sh <package-dir>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

# The gates bootstrap codegen when it is missing; do it before analysing.
(
  cd "$REPO_ROOT/$PKG"
  if [[ "$PKG" == "packages/client" ]]; then
    if [[ ! -f lib/ui/l10n/l10n.dart || ! -f lib/app/router/root_router.gr.dart ]]; then
      echo "check-analysis: bootstrapping packages/client codegen..."
      flutter gen-l10n
      dart run build_runner build -d
    fi
  elif [[ ! -f lib/domain/entity/jwt_entity.freezed.dart \
       || ! -f lib/data/database/tentura_db.g.dart ]]; then
    echo "check-analysis: bootstrapping $PKG codegen..."
    dart run build_runner build -d
  fi
)

set +e
(cd "$REPO_ROOT/$PKG" && dart analyze --no-fatal-warnings) >"$out" 2>&1
status=$?
set -e

export TENTURA_ANALYZER_OUTPUT="$out"
export TENTURA_ANALYZER_STATUS="$status"
TENTURA_CUSTOM_LINT_RULES="$(bash "$REPO_ROOT/scripts/check-custom-lints.sh" --print-rules)"
export TENTURA_CUSTOM_LINT_RULES

lints=0
bash "$REPO_ROOT/scripts/check-custom-lints.sh" "$PKG" || lints=$?
baseline=0
bash "$REPO_ROOT/scripts/check-analyze-baseline.sh" "$PKG" || baseline=$?
if [[ $lints -ne 0 || $baseline -ne 0 ]]; then
  exit 1
fi
