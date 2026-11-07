#!/usr/bin/env bash
# Load repo-root .env and run the Tentura API on the host.
#
# Runs in the FOREGROUND: Ctrl+C or closing the terminal stops the server.
# Do not background this script (no &, no disown) during normal dev/debug.
#
# Optional: pass dart flags, e.g. VM service for debugging:
#   ./scripts/run-server-local.sh --enable-vm-service
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/packages/server"

if [[ ! -f "$ROOT/.env" ]]; then
  echo "Missing $ROOT/.env — copy .env.example to .env" >&2
  exit 1
fi

# Snapshot exported names before .env so caller/runner overrides are not overwritten
# by the same keys in .env. Unset keys still pick up .env; duplicate keys in .env
# still apply last-wins (not in the snapshot until exported from an earlier .env line).
declare -A __run_server_local_env_prekeys=()
while IFS= read -r __n; do
  __run_server_local_env_prekeys["$__n"]=1
done < <(compgen -e)

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  key="${line%%=*}"
  if [[ "$key" != "$line" ]] && [[ -n "${__run_server_local_env_prekeys[$key]+x}" ]]; then
    continue
  fi
  export "$line"
done < "$ROOT/.env"
unset __run_server_local_env_prekeys

bash "$ROOT/scripts/validate_local_server_env.sh"

PORT="${PORT:-2080}"
if command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -qE "[.:]${PORT} "; then
  echo "Port ${PORT} is already in use. Stop the other process first, e.g.:" >&2
  echo "  fuser -k ${PORT}/tcp   # or: pkill -f 'bin/tentura\\.dart'" >&2
  exit 1
fi

# Keep the launcher alive so callers can stop the API by its script name/PID.
# A separate process group lets shutdown also stop Dart's child processes.
setsid dart run bin/tentura.dart "$@" &
server_pid=$!
trap 'kill -- "-$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
wait "$server_pid"
