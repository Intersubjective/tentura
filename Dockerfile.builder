# Builder image for CI: Flutter + system deps (e.g. libsqlite3-dev for server tests).
# Built by .github/workflows/builder-image.yml and pushed to GHCR as tentura-builder:latest.
FROM ghcr.io/cirruslabs/flutter:stable
RUN apt-get update -qq && apt-get install -y -qq libsqlite3-dev && rm -rf /var/lib/apt/lists/*
