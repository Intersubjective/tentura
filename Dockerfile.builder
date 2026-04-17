# Builder image for CI: Flutter + system deps (e.g. libsqlite3-dev for server tests).
# Built by .github/workflows/builder-image.yml and pushed to GHCR as tentura-builder:latest.
FROM ghcr.io/cirruslabs/flutter:stable
# Mounted .pub-cache from the GitHub runner is owned by a non-root UID; Git 2.35+
# refuses that unless marked safe (breaks pub git deps like ferry).
RUN git config --global --add safe.directory '*'
RUN apt-get update -qq && apt-get install -y -qq libsqlite3-dev && rm -rf /var/lib/apt/lists/*
