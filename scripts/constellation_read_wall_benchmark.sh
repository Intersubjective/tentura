#!/usr/bin/env bash
# GATE-14.1 disposable-database benchmark runner (UNIT 02).
# Never targets the shared postgres database — only tentura_test_constellation_perf_*.
set -euo pipefail
cd "$(dirname "$0")/../packages/server"
dart run tool/constellation_read_wall_benchmark.dart "$@"
