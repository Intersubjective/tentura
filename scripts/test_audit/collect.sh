#!/usr/bin/env bash
# One full-suite run per package that leaves *per-test-file* coverage + per-test timings.
#   scripts/test_audit/collect.sh server [extra dart-test args]   # excludes -t pg by default
#   scripts/test_audit/collect.sh client [extra flutter-test args]
# Output: build/test_audit/raw/<pkg>/{run.jsonl, cov/...}
# Then:   python3 scripts/test_audit/ingest.py --pkg <pkg>
#
# server: `dart test --coverage=DIR` already writes one <test-file>.vm.json per file.
#         needs `dart pub global activate coverage` once.
# client: stock `flutter test --coverage` only emits ONE merged lcov. This needs a tiny
#         local patch to the (throw-away) Flutter SDK: see scripts/test_audit/flutter_sdk_patch.md.
#         The patch writes $TA_COV_DIR/<test-file>.json when that env var is set.
# Wrap in scripts/run_with_test_cleanup.sh per AGENTS.md.
set -euo pipefail
pkg="${1:?server|client}"; shift || true
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/build/test_audit/raw/$pkg"; rm -rf "$out"; mkdir -p "$out/cov"
cd "$root/packages/$pkg"
case "$pkg" in
  server) dart test --exclude-tags pg --coverage "$out/cov" -r json -j "${JOBS:-4}" "$@" > "$out/run.jsonl" || true ;;
  client) TA_COV_DIR="$out/cov" flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env \
            --coverage --coverage-path="$out/merged.lcov" --concurrency="${JOBS:-4}" -r json "$@" > "$out/run.jsonl" || true ;;
esac
