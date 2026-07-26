#!/usr/bin/env bash
# Generate a fresh Ed25519 keypair for local dev and write it into repo-root .env
# (JWT_PUBLIC_PEM / JWT_PRIVATE_PEM).
#
# Why: the server refuses the .env.example placeholder keys under
# ENVIRONMENT=dev/prod (see Env._assertJwtKeys in packages/server/lib/env.dart),
# so a real keypair is required before ./scripts/run-server-local.sh will start.
#
# After running this, recreate Hasura so its HASURA_GRAPHQL_JWT_SECRET picks up
# the new public key (otherwise Hasura rejects tokens with invalid-jwt):
#   docker compose up -d --force-recreate hasura
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "error: openssl is required" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found — copy .env.example to .env first" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

openssl genpkey -algorithm ED25519 -out "$tmpdir/priv.pem" 2>/dev/null
openssl pkey -in "$tmpdir/priv.pem" -pubout -out "$tmpdir/pub.pem" 2>/dev/null

# Collapse each PEM to a single line with literal \n escapes (repo .env format).
PRIV=$(awk 'BEGIN{ORS="\\n"}{print}' "$tmpdir/priv.pem")
PUB=$(awk 'BEGIN{ORS="\\n"}{print}' "$tmpdir/pub.pem")

# Drop any existing keys, then append the fresh pair (printf %s leaves the
# literal backslash-n untouched).
grep -vE '^(JWT_PUBLIC_PEM|JWT_PRIVATE_PEM)=' "$ENV_FILE" > "$tmpdir/env.new"
printf 'JWT_PUBLIC_PEM=%s\n' "$PUB" >> "$tmpdir/env.new"
printf 'JWT_PRIVATE_PEM=%s\n' "$PRIV" >> "$tmpdir/env.new"
cp "$tmpdir/env.new" "$ENV_FILE"

echo "Wrote a fresh Ed25519 JWT keypair to $ENV_FILE"
echo "Next: recreate Hasura so it trusts the new public key:"
echo "  docker compose up -d --force-recreate hasura"
