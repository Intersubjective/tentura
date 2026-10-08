#!/usr/bin/env bash
# The custom-lint gate must reject an analyzer plugin setup failure even when
# dart analyze exits successfully and reports no custom-rule violations.
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
  for baseline in 0 24; do
    case_dir="$TMP_BASE/${package##*/}"
    root="$case_dir/root"
    bin="$case_dir/bin"
    output="$case_dir/output.log"
    calls="$case_dir/calls.log"
    mkdir -p "$root/scripts" "$root/$package" "$bin"
    cp "$REAL_ROOT/scripts/check-custom-lints.sh" "$root/scripts/"
    # Both at-baseline and below-baseline clean runs must remain successful.
    # A fix that simply rejects zero counts cannot satisfy these paired cases.
    printf 'packages/client %s\npackages/server %s\n' "$baseline" "$baseline" \
      >"$root/scripts/custom-lint-baseline.txt"

    # Pretend codegen is complete so the only Dart operation is analysis.
    mkdir -p "$root/$package/lib/ui/l10n" "$root/$package/lib/app/router" \
      "$root/$package/lib/domain/entity" "$root/$package/lib/data/database"
    touch "$root/$package/lib/ui/l10n/l10n.dart" \
      "$root/$package/lib/app/router/root_router.gr.dart" \
      "$root/$package/lib/domain/entity/jwt_entity.freezed.dart" \
      "$root/$package/lib/data/database/tentura_db.g.dart"

    cat >"$bin/dart" <<'DART'
#!/usr/bin/env bash
set -euo pipefail
printf 'dart|cwd=%s|args=%s\n' "$PWD" "$*" >>"$CALL_LOG"
# Allow additional analyzer flags and preliminary Dart commands. Only analysis
# emits the simulated result; no assertion pins the gate's analyzer arguments.
analyzing=0
for argument in "$@"; do
  [[ "$argument" != analyze ]] || analyzing=1
done
if [[ "$analyzing" == 0 ]]; then exit 0; fi
printf 'analyze|cwd=%s|exit=0\n' "$PWD" >>"$CALL_LOG"
printf 'Analyzing %s...\n' "${PWD##*/}"
if [[ "$PLUGIN_SETUP" == failed ]]; then
  # Captured from the real analyzer CLI, including its server.pluginError
  # routing and the failed pub.dev dependency fetch. See the fixture README.
  cat "$ANALYZER_FAILURE_FIXTURE" >&2
fi
for ((index = 0; index < CUSTOM_VIOLATIONS; index++)); do
  printf '   info - lib/example.dart:%s:1 - Use a generated GraphQL document. - no_raw_graphql_in_dart\n' "$((index + 1))"
done
if ((CUSTOM_VIOLATIONS)); then
  printf '%s issues found.\n' "$CUSTOM_VIOLATIONS"
else
  echo 'No issues found!'
fi
exit 0
DART
    chmod +x "$bin/dart"

    # The analyzer exit, summary, diagnostics count, baseline and filesystem are
    # identical in the two runs. Only the plugin setup failure changes. Clean
    # runs before and after the failure distinguish it from unrelated gate errors
    # without requiring the implementation to echo any particular diagnostic.
    for setup in healthy failed healthy violations; do
      : >"$calls"
      status=0
      violations=0
      plugin_setup="$setup"
      if [[ "$setup" == violations ]]; then
        violations=$((baseline + 1))
        plugin_setup=healthy
      fi
      env PATH="$bin:$PATH" CALL_LOG="$calls" PLUGIN_SETUP="$plugin_setup" \
        CUSTOM_VIOLATIONS="$violations" \
        ANALYZER_FAILURE_FIXTURE="$FAILURE_FIXTURE" \
        bash "$root/scripts/check-custom-lints.sh" "$package" >"$output" 2>&1 \
        || status=$?

      # Guard against a red result caused by a broken fixture or unrelated failure.
      if [[ ! -f "$calls" ]] || \
        ! grep -Fxq "analyze|cwd=$root/$package|exit=0" "$calls"; then
        echo "FAIL: analyzer fixture did not run successfully at the package root" >&2
        cat "$output" >&2
        exit 1
      fi
      if [[ "$setup" == healthy ]]; then
        if [[ "$status" != 0 ]]; then
          echo "FAIL: $package must accept healthy plugin setup with zero violations (baseline=$baseline, exit=$status)" >&2
          cat "$output" >&2
          failures=$((failures + 1))
        fi
        continue
      fi
      if [[ "$setup" == violations ]]; then
        if [[ "$status" == 0 ]] || grep -Fq "check-custom-lints: $package OK" "$output"; then
          echo "FAIL: $package must reject $violations custom violations from a healthy plugin (baseline=$baseline)" >&2
          cat "$output" >&2
          failures=$((failures + 1))
        fi
        continue
      fi
      if [[ "$status" == 0 ]]; then
        echo "FAIL: $package must reject plugin setup failure despite analyzer exit 0 and zero custom violations (baseline=$baseline)" >&2
        cat "$output" >&2
        failures=$((failures + 1))
      fi
      if grep -Fq "check-custom-lints: $package OK" "$output"; then
        echo "FAIL: $package must not report OK when custom rules could not initialize" >&2
        failures=$((failures + 1))
      fi
    done
  done
done

if ((failures)); then
  echo "Plugin initialization regression assertions failed: $failures" >&2
  exit 1
fi
echo 'OK: custom-lint gate rejects plugin setup failures and excessive custom violations while accepting healthy zero-count runs'
