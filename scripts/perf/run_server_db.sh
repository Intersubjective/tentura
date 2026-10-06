#!/usr/bin/env bash
# Start the local server against another database (e.g. tentura_devcopy, tentura_perfsynth).
# Usage: scripts/perf/run_server_db.sh <dbname>
set -euo pipefail
ROOT=/home/vader/MY_SRC/tentura
cd "$ROOT/packages/server"
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  export "$line"
done < "$ROOT/.env"
export POSTGRES_DBNAME="$1"
exec dart run bin/tentura.dart
