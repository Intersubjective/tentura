#!/usr/bin/env bash
# #808: the web build forces single-threaded skwasm
# (kForceSingleThreadedSkwasm in packages/client/hook/build/versioned_web_assets.dart)
# because multi-threaded skwasm on Flutter 3.47.0 races FreeType between the
# main thread and the raster worker (flutter/flutter#193439; fix PR
# flutter/flutter#193801). This check warns when Flutter has moved past the
# version that decision was made on, or when the upstream fix has merged, so
# the next Flutter upgrade re-evaluates going back to multi-threaded skwasm.
#
# Never fails the build: it prints a warning (a GitHub annotation in CI).
# To re-evaluate: set kForceSingleThreadedSkwasm = false, build with --wasm,
# rerun the #808 fast-zoom repro on a large Field and the Field perf bench;
# if both hold, keep it off and remove this check, else bump PINNED_FLUTTER.
set -uo pipefail

PINNED_FLUTTER=3.47.0
UPSTREAM_PR=flutter/flutter/pulls/193801
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/packages/client/hook/build/versioned_web_assets.dart"

warn() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning title=skwasm single-thread (#808)::$1"
  else
    echo "WARNING (skwasm single-thread, #808): $1" >&2
  fi
}

if ! grep -q 'const kForceSingleThreadedSkwasm = true;' "$HOOK"; then
  echo "check_skwasm_single_thread: multi-threaded skwasm is enabled; nothing to check"
  exit 0
fi

versions=()
for f in Dockerfile.builder Dockerfile.server packages/server/Dockerfile_build; do
  v=$(sed -nE 's/^ARG FLUTTER_VERSION=([0-9.]+).*/\1/p' "$ROOT/$f" 2>/dev/null | head -n1)
  [[ -n "$v" ]] && versions+=("$f=$v")
done
if command -v flutter >/dev/null 2>&1; then
  v=$(flutter --version --machine 2>/dev/null | sed -nE 's/.*"frameworkVersion": *"([^"]+)".*/\1/p' | head -n1)
  [[ -n "$v" ]] && versions+=("local SDK=$v")
fi

moved=0
for entry in "${versions[@]}"; do
  if [[ "${entry#*=}" != "$PINNED_FLUTTER" ]]; then
    moved=1
    warn "Flutter is ${entry#*=} (${entry%%=*}); single-threaded skwasm was pinned on $PINNED_FLUTTER. Re-evaluate multi-threaded skwasm: see the comment on kForceSingleThreadedSkwasm in packages/client/hook/build/versioned_web_assets.dart."
  fi
done

if command -v gh >/dev/null 2>&1; then
  merged=$(gh api "repos/$UPSTREAM_PR" --jq '.merged' 2>/dev/null || true)
  if [[ "$merged" == "true" ]]; then
    warn "upstream fix https://github.com/$UPSTREAM_PR is merged. Once Flutter includes it, try multi-threaded skwasm again (kForceSingleThreadedSkwasm = false)."
  fi
fi

if [[ "$moved" == 0 ]]; then
  echo "check_skwasm_single_thread: Flutter $PINNED_FLUTTER as pinned; single-threaded skwasm stays (#808)"
fi
exit 0
