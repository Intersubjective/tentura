#!/usr/bin/env bash
# Disposable capacity stack for scripts/perf/db_capacity_tuning.sh
# (tentura-ev3z.13): capacity-pg + capacity-mr + capacity-hasura from the
# images compose.prod.yaml deploys, with production MeritRank/pgmer2 settings,
# every container confined to the same cpuset as the measured server so the
# whole stack shares one nominal 2-vCPU host.
#
#   scripts/perf/db_capacity_stack.sh up     # create, migrate, apply metadata
#   scripts/perf/db_capacity_stack.sh down   # remove containers and network
#
# Never point it at the development or production database: it creates its own
# PostgreSQL cluster on 127.0.0.1:${CAPACITY_PG_PORT:-55432}.
# Hasura pool settings come from HASURA_POOL_ENV (space-separated NAME=VALUE),
# default: the values compose.prod.yaml ships.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cmd="${1:?usage: db_capacity_stack.sh up|down}"

net=capacity-net
pg="${CAPACITY_PG_CONTAINER:-capacity-pg}"
mr="${CAPACITY_MR_CONTAINER:-capacity-mr}"
hasura="${CAPACITY_HASURA_CONTAINER:-capacity-hasura}"
pg_port="${CAPACITY_PG_PORT:-55432}"
hasura_port="${CAPACITY_HASURA_PORT:-58081}"
db="${CAPACITY_DB:-tentura_capacity}"
password="${CAPACITY_PG_PASSWORD:-capacity}"
api_port="${CAPACITY_API_PORT:-52080}"
cpus="${CAPACITY_SERVER_CPUS:-2,4}"

image_of() { # service -> image declared in compose.prod.yaml
  python3 - "$ROOT/compose.prod.yaml" "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'^  ' + sys.argv[2] + r':\n(?:(?!^  \S).)*?^    image:\s*(\S+)',
              text, re.M | re.S)
print(m.group(1).strip("'\""))
PY
}

prod_env() { # service -> its quoted NAME=VALUE environment entries
  python3 - "$ROOT/compose.prod.yaml" "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
block = re.search(r'^  ' + sys.argv[2] + r':\n((?:(?!^  \S).*\n)*)', text, re.M).group(1)
for m in re.finditer(r"^      - '([A-Z_]+=.*)'$", block, re.M):
    print(m.group(1))
PY
}

if [[ "$cmd" == down ]]; then
  docker rm -f -v "$hasura" "$pg" "$mr" 2>/dev/null || true
  docker network rm "$net" 2>/dev/null || true
  exit 0
fi
[[ "$cmd" == up ]] || { echo "usage: $0 up|down" >&2; exit 2; }

pg_image="$(image_of postgres)"
mr_image="$(image_of meritrank)"
hasura_image="$(image_of hasura)"
docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net" >/dev/null

mr_args=()
while IFS= read -r kv; do mr_args+=(-e "$kv"); done < <(prod_env meritrank)
docker run -d --init --name "$mr" --hostname "$mr" --network "$net" \
  --cpuset-cpus "$cpus" "${mr_args[@]}" "$mr_image" >/dev/null

recv_timeout="$(prod_env postgres | sed -n 's/^MERITRANK_RECV_TIMEOUT_MSEC=//p')"
# Production's observability flags (compose.prod.yaml `postgres.command`).
docker run -d --init --name "$pg" --hostname "$pg" --network "$net" \
  --cpuset-cpus "$cpus" -p "127.0.0.1:$pg_port:5432" \
  -e "POSTGRES_PASSWORD=$password" \
  -e "MERITRANK_SERVICE_URL=tcp://$mr:8080" \
  -e "MERITRANK_RECV_TIMEOUT_MSEC=$recv_timeout" \
  "$pg_image" postgres \
  -c shared_preload_libraries=pg_stat_statements,auto_explain \
  -c pg_stat_statements.track=all -c track_io_timing=on \
  -c log_min_duration_statement=1000 -c auto_explain.log_min_duration=2000 \
  -c auto_explain.log_analyze=on -c auto_explain.log_buffers=on >/dev/null
for _ in $(seq 60); do
  docker exec "$pg" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done
sleep 3
docker exec "$pg" pg_isready -U postgres >/dev/null
docker exec "$pg" psql -U postgres -qc "CREATE DATABASE $db" >/dev/null
# Production has pgmer2 in the application database before migrations run.
docker exec "$pg" psql -U postgres -d "$db" -qc "CREATE EXTENSION pgmer2" >/dev/null

(
  cd "$ROOT/packages/server"
  POSTGRES_HOST=127.0.0.1 POSTGRES_PORT="$pg_port" POSTGRES_DBNAME="$db" \
    POSTGRES_PASSWORD="$password" dart run bin/utils/run_migrations_once.dart
)

jwt_public="$(sed -n 's/^JWT_PUBLIC_PEM=//p' "$ROOT/.env")"
hasura_args=()
while IFS= read -r kv; do
  case "$kv" in
    HASURA_GRAPHQL_DATABASE_URL=*|HASURA_GRAPHQL_JWT_SECRET=*|TENTURA_GRAPHQL_URL=*) ;;
    HASURA_GRAPHQL_PG_*) [[ -n "${HASURA_POOL_ENV+x}" ]] || hasura_args+=(-e "$kv") ;;
    *) hasura_args+=(-e "$kv") ;;
  esac
done < <(prod_env hasura)
for kv in ${HASURA_POOL_ENV:-}; do hasura_args+=(-e "$kv"); done
# The URL's query string (statement_timeout, application_name) is the one
# compose.prod.yaml ships.
url_query="$(prod_env hasura | sed -n 's/^HASURA_GRAPHQL_DATABASE_URL=[^?]*//p')"
docker run -d --name "$hasura" --hostname "$hasura" --network "$net" \
  --cpuset-cpus "$cpus" -p "127.0.0.1:$hasura_port:8080" \
  "${hasura_args[@]}" \
  -e HASURA_GRAPHQL_ADMIN_SECRET=password \
  -e "HASURA_GRAPHQL_DATABASE_URL=postgres://postgres:$password@$pg:5432/$db$url_query" \
  -e "HASURA_GRAPHQL_JWT_SECRET={\"type\":\"Ed25519\", \"key\":\"$jwt_public\", \"claims_map\": {\"x-hasura-allowed-roles\": [\"user\", \"admin\"], \"x-hasura-default-role\": \"user\", \"x-hasura-user-id\": {\"path\": \"\$.sub\"}}}" \
  -e "TENTURA_GRAPHQL_URL=http://host.docker.internal:$api_port/api/v2/graphql" \
  --add-host host.docker.internal:host-gateway \
  "$hasura_image" >/dev/null
for _ in $(seq 90); do
  curl -fsS "http://127.0.0.1:$hasura_port/healthz" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:$hasura_port/healthz" >/dev/null
# The Tentura remote schema is not up yet; the harness reads tables only.
jq -n --argjson metadata "$(jq '.metadata' "$ROOT/hasura/metadata.json")" \
  '{type: "replace_metadata", version: 2,
    args: {allow_inconsistent_metadata: true, metadata: $metadata}}' |
  curl -fsS -o /dev/null "http://127.0.0.1:$hasura_port/v1/metadata" \
    -H 'X-Hasura-Admin-Secret: password' -H 'Content-Type: application/json' -d @-
echo "capacity stack up: pg 127.0.0.1:$pg_port/$db, hasura 127.0.0.1:$hasura_port, cpuset $cpus"
