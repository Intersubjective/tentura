#!/bin/bash
set -euo pipefail

# If vexp daemon is healthy, steer away from Grep/Glob to save tokens.
# Mirror behaviour of `.claude/hooks/vexp-guard.sh`, but do NOT hard-block:
# return "ask" so the user can still proceed intentionally.

input="$(cat)"

VEXP_DIR="$(pwd)/.vexp"
SOCK="$VEXP_DIR/daemon.sock"
HEALTHY="$VEXP_DIR/healthy"
PID_FILE="$VEXP_DIR/daemon.pid"

if [ -S "$SOCK" ] && [ -f "$HEALTHY" ] && [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  cat <<'JSON'
{
  "permission": "ask",
  "user_message": "vexp daemon is running for this repo. Prefer vexp CLI (e.g. `vexp capsule`, `vexp skeleton`, `vexp impact`) instead of Grep/Glob to minimize tokens."
}
JSON
  exit 0
fi

echo '{ "permission": "allow" }'
