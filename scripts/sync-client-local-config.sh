#!/usr/bin/env bash
# Writes packages/client/env/local-web.env from repo-root .env.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/packages/client/env/local-web.env"
mkdir -p "$(dirname "$OUT")"

eval "$(bash "$ROOT/scripts/resolve_local_web_config.sh" --export)"

cat >"$OUT" <<EOF
SERVER_NAME=${CLIENT_SERVER_NAME}
WS_SERVER_NAME=${WS_SERVER_NAME}
INVITE_LINK_HOST=${INVITE_LINK_HOST}
IMAGE_SERVER=${IMAGE_SERVER}
EOF

echo "Wrote $OUT"
