#!/usr/bin/env bash
# One-shot local dev bootstrap: make .env bootable, bring up infra, and apply
# Hasura metadata — the setup steps that otherwise fail silently. It does NOT
# start the foreground processes (API server, Flutter web, Caddy); it prints the
# commands to run for those, since each wants its own terminal.
#
# Idempotent: safe to re-run. Reuses an existing .env and never regenerates keys
# that are already non-placeholder.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ENV_FILE="$ROOT/.env"

# 1. Ensure .env exists.
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT/.env.example" "$ENV_FILE"
  echo "Created .env from .env.example"
fi

# 2. Replace the .env.example placeholder JWT keys with a real keypair (the
#    server rejects the placeholders under ENVIRONMENT=dev/prod).
regen_keys=0
example_pub="$(grep -E '^JWT_PUBLIC_PEM=' "$ROOT/.env.example" || true)"
current_pub="$(grep -E '^JWT_PUBLIC_PEM=' "$ENV_FILE" || true)"
if [[ -z "$current_pub" || "$current_pub" == "$example_pub" ]]; then
  bash "$ROOT/scripts/gen-dev-jwt.sh"
  regen_keys=1
fi

# 3. Ensure the dev-only knobs QA login + the app depend on are present.
ensure_kv() {
  grep -qE "^$1=" "$ENV_FILE" || printf '%s=%s\n' "$1" "$2" >> "$ENV_FILE"
}
ensure_kv ENVIRONMENT dev
ensure_kv QA_AUTH_ENABLED true
ensure_kv QA_AUTH_TOKEN local-dev-qa-token
ensure_kv QA_EMAIL_DOMAINS test.tentura.local,qa.tentura.local,example.test
ensure_kv QA_SIMPLE_LOGIN_MODE true

# 4. Start infra. Recreate Hasura if we just rotated the JWT public key.
docker compose up -d
if [[ "$regen_keys" == "1" ]]; then
  docker compose up -d --force-recreate hasura
fi

# 5. Wait for Postgres (healthcheck) and Hasura (healthz) before applying metadata.
echo "Waiting for Postgres to become healthy..."
for _ in $(seq 1 60); do
  [[ "$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || true)" == "healthy" ]] && break
  sleep 2
done
echo "Waiting for Hasura..."
for _ in $(seq 1 60); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/healthz || true)" == "200" ]] && break
  sleep 2
done

# 6. Apply Hasura metadata (else the app shows "field 'beacon' not found ...").
bash "$ROOT/scripts/hasura_apply_metadata.sh"

cat <<'EOF'

Infra is up and Hasura metadata is applied. Start the three foreground
processes, each in its own terminal:

  ./scripts/run-server-local.sh          # Tentura API  -> :2080
  ./scripts/run-flutter-web-local.sh     # Flutter web  -> :8888
  caddy run --config Caddyfile.local     # HTTPS proxy  -> https://dev.lvh.me:9443

Then open https://dev.lvh.me:9443/ (QA "Test login" needs landing
config.local.js qaTestLogin:true — see DEVELOPMENT.md).
EOF
