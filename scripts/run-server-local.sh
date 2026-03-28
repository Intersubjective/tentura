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

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  export "$line"
done < "$ROOT/.env"

PORT="${PORT:-2080}"
if command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -qE "[.:]${PORT} "; then
  echo "Port ${PORT} is already in use. Stop the other process first, e.g.:" >&2
  echo "  fuser -k ${PORT}/tcp   # or: pkill -f 'bin/tentura\\.dart'" >&2
  exit 1
fi

exec dart run bin/tentura.dart "$@"
