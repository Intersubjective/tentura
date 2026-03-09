#!/usr/bin/env bash

set -euo pipefail

PUBSPEC_PATH="${1:-packages/client/pubspec.yaml}"

if [[ ! -f "$PUBSPEC_PATH" ]]; then
  echo "pubspec file not found: $PUBSPEC_PATH" >&2
  exit 1
fi

FLUTTER_VERSION=$(
  grep -E '^[[:space:]]*flutter:' "$PUBSPEC_PATH" \
    | head -n 1 \
    | sed -E 's/^[[:space:]]*flutter:[[:space:]]*\^?([0-9.]+).*$/\1/'
)

if [[ -z "$FLUTTER_VERSION" ]]; then
  echo "Unable to determine Flutter version from $PUBSPEC_PATH" >&2
  exit 1
fi

echo "$FLUTTER_VERSION"

