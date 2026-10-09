#!/usr/bin/env bash
# The analyzer baseline gate must reject an analyzer plugin setup failure even
# when the analyzer exits successfully, prints a clean summary and the issue
# count is within the baseline (the custom-lint gate already does this).
# Run the real gate in a scratch checkout with a deterministic analyzer stub;
# no network, installed plugin cache, codegen, or local package changes are needed.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURE_FIXTURE="$REAL_ROOT/scripts/fixtures/analyzer_plugin_setup_failure/stderr.txt"
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

packages=(packages/client packages/server)
if (($#)); then
  if (($# != 1)) || [[ "$1" != packages/client && "$1" != packages/server ]]; then
    echo "usage: $0 [packages/client|packages/server]" >&2
    exit 2
  fi
  packages=("$1")
fi

failures=0
for package in "${packages[@]}"; do
  for scope in "" lib/features/beacon_view; do
    for baseline in 0 24; do
      case_dir="$TMP_BASE/${package##*/}-${scope//\//_}-$baseline"
      root="$case_dir/root"
      bin="$case_dir/bin"
      output="$case_dir/output.log"
      calls="$case_dir/calls.log"
      mkdir -p "$root/scripts" "$root/$package/${scope:-lib}" "$bin"
      cp "$REAL_ROOT/scripts/check-analyze-baseline.sh" "$root/scripts/"
      # Both at-baseline and below-baseline clean runs must remain successful.
      # A fix that simply rejects zero counts cannot satisfy these paired cases.
      printf 'packages/client %s\npackages/server %s\n%s:%s %s\n' \
        "$baseline" "$baseline" "$package" "${scope:-unused}" "$baseline" \
        >"$root/scripts/analyze-baseline.txt"

      # Pretend codegen is complete so the only tool operation is analysis.
      mkdir -p "$root/$package/lib/ui/l10n" "$root/$package/lib/app/router" \
        "$root/$package/lib/domain/entity" "$root/$package/lib/data/database"
      touch "$root/$package/lib/ui/l10n/l10n.dart" \
        "$root/$package/lib/app/router/root_router.gr.dart" \
        "$root/$package/lib/domain/entity/jwt_entity.freezed.dart" \
        "$root/$package/lib/data/database/tentura_db.g.dart"

      # Client uses `flutter analyze`, server `dart analyze`; one stub serves both.
      cat >"$bin/dart" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|cwd=%s|args=%s\n' "${0##*/}" "$PWD" "$*" >>"$CALL_LOG"
analyzing=0
for argument in "$@"; do
  [[ "$argument" != analyze ]] || analyzing=1
done
if [[ "$analyzing" == 0 ]]; then exit 0; fi
printf 'analyze|cwd=%s|exit=0\n' "$PWD" >>"$CALL_LOG"
printf 'Analyzing %s...\n' "${PWD##*/}"
if [[ "$PLUGIN_SETUP" == failed ]]; then
  # Captured from the real analyzer CLI. See the fixture README.
  cat "$ANALYZER_FAILURE_FIXTURE" >&2
fi
for ((index = 0; index < ISSUES; index++)); do
  printf '   info - lib/example.dart:%s:1 - Example. - example_rule\n' "$((index + 1))"
done
if ((ISSUES)); then
  printf '%s issues found.\n' "$ISSUES"
else
  echo 'No issues found!'
fi
exit 0
TOOL
      chmod +x "$bin/dart"
      cp "$bin/dart" "$bin/flutter"

      # Only the plugin setup failure changes between the healthy and failed
      # runs; clean runs before and after it distinguish it from unrelated gate
      # errors without requiring any particular diagnostic wording.
      for setup in healthy failed healthy over_baseline; do
        : >"$calls"
        status=0
        issues=0
        plugin_setup="$setup"
        if [[ "$setup" == over_baseline ]]; then
          issues=$((baseline + 1))
          plugin_setup=healthy
        fi
        label="$package${scope:+:$scope} (baseline=$baseline)"
        env PATH="$bin:$PATH" CALL_LOG="$calls" PLUGIN_SETUP="$plugin_setup" \
          ISSUES="$issues" ANALYZER_FAILURE_FIXTURE="$FAILURE_FIXTURE" \
          bash "$root/scripts/check-analyze-baseline.sh" "$package" ${scope:+"$scope"} \
          >"$output" 2>&1 || status=$?

        if ! grep -Fxq "analyze|cwd=$root/$package|exit=0" "$calls"; then
          echo "FAIL: analyzer fixture did not run successfully for $label" >&2
          cat "$output" >&2
          exit 1
        fi
        if [[ "$setup" == healthy ]]; then
          if [[ "$status" != 0 ]]; then
            echo "FAIL: $label must accept healthy plugin setup with zero issues (exit=$status)" >&2
            cat "$output" >&2
            failures=$((failures + 1))
          fi
          continue
        fi
        if [[ "$setup" == over_baseline ]]; then
          if [[ "$status" == 0 ]] || grep -Fq "check-analyze-baseline: $package${scope:+:$scope} OK" "$output"; then
            echo "FAIL: $label must reject $issues issues above the baseline" >&2
            cat "$output" >&2
            failures=$((failures + 1))
          fi
          continue
        fi
        if [[ "$status" == 0 ]]; then
          echo "FAIL: $label must reject plugin setup failure despite analyzer exit 0 and zero issues" >&2
          cat "$output" >&2
          failures=$((failures + 1))
        fi
        if grep -Fq "check-analyze-baseline: $package${scope:+:$scope} OK" "$output"; then
          echo "FAIL: $label must not report OK when analyzer plugins could not initialize" >&2
          failures=$((failures + 1))
        fi
      done
    done
  done
done

if ((failures)); then
  echo "Plugin initialization regression assertions failed: $failures" >&2
  exit 1
fi
echo 'OK: analyze baseline gate rejects plugin setup failures and excess issues while accepting healthy clean runs'
