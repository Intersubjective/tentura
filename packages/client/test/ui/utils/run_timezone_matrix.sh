#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
for tz in UTC Europe/Amsterdam Pacific/Kiritimati; do
  echo "=== TZ=$tz ==="
  TZ="$tz" flutter test test/ui/utils/timezone_conversion_matrix_test.dart
done
