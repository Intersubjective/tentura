# Builder image for CI: Flutter + system deps (e.g. libsqlite3-dev for server tests).
# Built by .github/workflows/builder-image.yml and pushed to GHCR as tentura-builder:latest.
#
# cirruslabs stopped publishing after Flutter 3.44.0 (May 2026). :stable is Dart 3.12
# / test_api 0.7.11 and cannot solve analyzer 13 + flutter_test (needs 3.47 / Dart 3.13).
FROM ghcr.io/cirruslabs/flutter:3.44.0

ARG FLUTTER_VERSION=3.47.0

# Mounted .pub-cache from the GitHub runner is owned by a non-root UID; Git 2.35+
# refuses that unless marked safe (breaks pub git deps like ferry).
RUN git config --global --add safe.directory '*'

# Replace the stale SDK in-place so PATH / FLUTTER_HOME stay valid.
RUN rm -rf "$FLUTTER_HOME" \
 && git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
 && flutter config --no-analytics \
 && flutter precache --web

RUN apt-get update -qq && apt-get install -y -qq libsqlite3-dev && rm -rf /var/lib/apt/lists/*
