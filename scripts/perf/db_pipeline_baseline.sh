#!/usr/bin/env bash
# DB-pipeline mixed-load baseline (tentura-ev3z.8): copies tentura_perfsynth
# into the throwaway tentura_ev3z8_baseline database, loads MeritRank for it,
# then runs packages/server/tool/db_pipeline_baseline.dart against it.
# Drops the copy afterwards. Run serially: it resets the shared MeritRank.
#
# Usage: scripts/perf/db_pipeline_baseline.sh [output.json]
#   BASELINE_SECONDS  seconds of load per configuration (default 90)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COPY=tentura_ev3z8_baseline
OUT="$(realpath -m -- "${1:-packages/server/build/perf/db_pipeline_baseline.json}")"
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  export "$line"
done < "$ROOT/.env"

psql_admin() { docker exec -i postgres psql -U postgres -v ON_ERROR_STOP=1 "$@"; }
trap 'psql_admin -d postgres -c "DROP DATABASE IF EXISTS $COPY WITH (FORCE)" >/dev/null' EXIT

psql_admin -d postgres -c "DROP DATABASE IF EXISTS $COPY WITH (FORCE)"
psql_admin -d postgres -c "CREATE DATABASE $COPY TEMPLATE tentura_perfsynth"
psql_admin -d "$COPY" -c 'SELECT mr_reset()' -c 'SELECT meritrank_init()' >/dev/null

export POSTGRES_DBNAME="$COPY"
cd "$ROOT/packages/server"
dart run tool/db_pipeline_baseline.dart "$OUT"
