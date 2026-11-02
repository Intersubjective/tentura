#!/usr/bin/env bash
# #746 / #916: Dockerfile.builder (the image the dev/prod web build runs in)
# patches Flutter with scripts/flutter_patches/flutter-195316-flush-semantics.patch,
# the fix from flutter/flutter#192724 (unmerged when this was pinned) for
# flutter/flutter#195316: a null check in PipelineOwner.flushSemantics while a
# page is blocked by a new route (Sentry TENTURA-CLIENT-4J/4V/5P). This check
# warns when Flutter has moved past the version the patch was made for, or
# when the upstream fix has merged, so the next Flutter upgrade re-checks it.
#
# Never fails the build: it prints a warning (a GitHub annotation in CI). The
# builder image build itself fails when the patch no longer applies.
# To re-check: if the new Flutter contains the upstream fix, drop the patch and
# its apply step in Dockerfile.builder and remove this check; else make sure
# the patch still applies, bump PINNED_FLUTTER. Either way, after deploy-dev run
# scripts/e2e_focus/semantics_push_null_check.mjs: expect 0 null-check hits.
set -uo pipefail

PINNED_FLUTTER=3.47.0
UPSTREAM_PR=flutter/flutter/pulls/192724
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/scripts/flutter_patches/flutter-195316-flush-semantics.patch"

warn() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning title=Flutter patch flutter#195316 (#746)::$1"
  else
    echo "WARNING (Flutter patch flutter#195316, #746): $1" >&2
  fi
}

if [[ ! -f "$PATCH" ]]; then
  echo "check_flutter_semantics_patch: no Flutter patch carried; nothing to check"
  exit 0
fi

v=$(sed -nE 's/^ARG FLUTTER_VERSION=([0-9.]+).*/\1/p' "$ROOT/Dockerfile.builder" 2>/dev/null | head -n1)
moved=0
if [[ -n "$v" && "$v" != "$PINNED_FLUTTER" ]]; then
  moved=1
  warn "Flutter is $v (Dockerfile.builder); the flutter#195316 patch was made for $PINNED_FLUTTER. Re-check whether flutter/flutter#192724 landed and drop the patch if so: see scripts/flutter_patches/README.md."
fi

if command -v gh >/dev/null 2>&1; then
  merged=$(gh api "repos/$UPSTREAM_PR" --jq '.merged' 2>/dev/null || true)
  if [[ "$merged" == "true" ]]; then
    warn "upstream fix https://github.com/$UPSTREAM_PR is merged. Once Flutter includes it, drop the patch from Dockerfile.builder (scripts/flutter_patches/README.md)."
  fi
fi

if [[ "$moved" == 0 ]]; then
  echo "check_flutter_semantics_patch: Flutter $PINNED_FLUTTER as pinned; the flutter#195316 patch stays (#746)"
fi
exit 0
