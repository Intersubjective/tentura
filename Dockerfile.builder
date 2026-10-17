# Builder image for CI: Flutter + system deps (e.g. libsqlite3-dev for server tests).
# Built by .github/workflows/builder-image.yml and pushed to GHCR as tentura-builder:latest.
#
# Kept small on purpose: every CI job pulls it cold. It used to start from
# ghcr.io/cirruslabs/flutter:3.44.0 and swap in Flutter 3.47.0, which made it
# 5.7 GB: the cirruslabs Android SDK (1.3 GB) rode along unused, and deleting
# the old SDK in a later layer does not shrink the earlier one. (cirruslabs
# stopped publishing after 3.44.0; 3.47 / Dart 3.13 is needed for analyzer 13
# + flutter_test.) CI builds web and runs VM / flutter_tester tests only.
FROM debian:bookworm-slim

ARG FLUTTER_VERSION=3.47.0

ENV FLUTTER_HOME=/sdks/flutter
ENV PATH=/sdks/flutter/bin:/sdks/flutter/bin/cache/dart-sdk/bin:$PATH

# ripgrep is required, not optional: scripts/check-doc-drift.sh,
# check-user-facing-terminology.sh and the pipeline's `! rg ... lib/domain`
# architecture guards all invoke `rg`. Without it each one fails, the
# failure is swallowed by `2>/dev/null` or inverted by `!`, and the gate
# reports clean — which is what they had been doing here.
#
# gcc + libc6-dev: packages/server/test/architecture/
# run_with_test_cleanup_sweep_test.dart compiles a small LD_PRELOAD shim with
# `cc`.
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip jq python3 \
      libsqlite3-dev ripgrep gcc libc6-dev procps \
 && rm -rf /var/lib/apt/lists/*

# Mounted .pub-cache from the GitHub runner is owned by a non-root UID; Git 2.35+
# refuses that unless marked safe (breaks pub git deps like ferry).
RUN git config --global --add safe.directory '*'

RUN git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
 && flutter config --no-analytics --no-cli-animations \
      --no-enable-android --no-enable-ios --no-enable-macos-desktop \
      --no-enable-windows-desktop --no-enable-linux-desktop \
 && dart --disable-analytics \
 && flutter precache --web --universal \
 && rm -rf "$FLUTTER_HOME/.git/objects/pack"/*.pack.tmp* /root/.cache
