#!/bin/bash
# Deployment script for VPS server
# Usage: ./deploy.sh [archive-path]
#   archive-path: Path to web archive (default: /tmp/web-*.tar.gz)
#
# Environment variables:
#   DEPLOY_DIR      - deployment directory (default: /opt/tentura)
#   COMPOSE_FILE    - primary compose file (default: compose.prod.yaml)
#   OVERRIDE_FILE   - override compose file; auto-detected if not set
#                     (non-secret per-host deltas only — secrets go in .env)
#   WEB_DIR         - web assets directory (default: ./web)
#   LANDING_DIR     - static landing directory (default: ./landing)
#   LANDING_ARCHIVE - explicit path to landing tarball (CI sets this; avoids
#                     picking a stale /tmp/landing-*.tar.gz from manual uploads)
#   HASURA_APPLY_IMAGE - image with bash+curl+jq for metadata apply
#                        (default: badouralix/curl-jq:ubuntu)
#
# Deploy order: extract web + landing archives BEFORE docker compose up -d so
# Caddy never serves an empty {$LANDING_ROOT} or stale assets at cutover.
# After compose is healthy, applies hasura/metadata.json via the internal network.

set -euo pipefail

# Best-effort /tmp cleanup — never fail deploy if another user's file is left behind.
cleanup_tmp_archive() {
  local path="$1"
  if [[ "$path" != /tmp/* ]]; then
    return 0
  fi
  if rm -f "$path" 2>/dev/null; then
    echo "Cleaned up archive from /tmp: $path"
  else
    echo "Warning: could not remove $path (non-fatal; check permissions)" >&2
  fi
}

read_hasura_admin_secret() {
  local line
  line="$(grep -E '^HASURA_GRAPHQL_ADMIN_SECRET=' .env 2>/dev/null | head -1 || true)"
  if [[ -z "$line" ]]; then
    echo "Error: HASURA_GRAPHQL_ADMIN_SECRET not found in .env" >&2
    exit 1
  fi
  HASURA_GRAPHQL_ADMIN_SECRET="${line#HASURA_GRAPHQL_ADMIN_SECRET=}"
  HASURA_GRAPHQL_ADMIN_SECRET="${HASURA_GRAPHQL_ADMIN_SECRET#\"}"
  HASURA_GRAPHQL_ADMIN_SECRET="${HASURA_GRAPHQL_ADMIN_SECRET%\"}"
  HASURA_GRAPHQL_ADMIN_SECRET="${HASURA_GRAPHQL_ADMIN_SECRET#\'}"
  HASURA_GRAPHQL_ADMIN_SECRET="${HASURA_GRAPHQL_ADMIN_SECRET%\'}"
}

resolve_backend_network() {
  local cid network
  cid="$(docker compose "${COMPOSE_ARGS[@]}" ps -q hasura 2>/dev/null | head -1 || true)"
  if [[ -z "$cid" ]]; then
    cid="$(docker compose "${COMPOSE_ARGS[@]}" ps -q tentura 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "$cid" ]]; then
    echo "Error: could not resolve backend network (no running hasura/tentura container)" >&2
    exit 1
  fi
  network="$(docker inspect "$cid" -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' \
    | grep backend | head -1 || true)"
  if [[ -z "$network" ]]; then
    echo "Error: could not find *backend* network on container $cid" >&2
    exit 1
  fi
  BACKEND_NETWORK="$network"
}

apply_hasura_metadata() {
  local metadata_file="$PWD/hasura/metadata.json"
  local apply_script="$PWD/scripts/hasura_apply_metadata.sh"
  local apply_image="${HASURA_APPLY_IMAGE:-badouralix/curl-jq:ubuntu}"
  local attempt output exit_code

  mkdir -p hasura scripts

  if [[ ! -f "$metadata_file" ]]; then
    echo "Error: Hasura metadata file not found: $metadata_file" >&2
    echo "CI should scp hasura/metadata.json before deploy, or copy it during bootstrap." >&2
    exit 1
  fi
  if [[ ! -f "$apply_script" ]]; then
    echo "Error: Hasura apply script not found: $apply_script" >&2
    exit 1
  fi

  read_hasura_admin_secret
  resolve_backend_network

  echo "Pulling Hasura metadata apply image ($apply_image)..."
  docker pull "$apply_image"

  echo "Applying Hasura metadata via network $BACKEND_NETWORK..."
  for attempt in 1 2 3; do
    set +e
    output="$(docker run --rm \
      --network "$BACKEND_NETWORK" \
      -v "$metadata_file:/data/metadata.json:ro" \
      -v "$apply_script:/apply.sh:ro" \
      -e "HASURA_URL=http://hasura:8080" \
      -e "HASURA_GRAPHQL_ADMIN_SECRET=${HASURA_GRAPHQL_ADMIN_SECRET}" \
      -e "METADATA_FILE=/data/metadata.json" \
      "$apply_image" \
      bash /apply.sh 2>&1)"
    exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]]; then
      echo "$output"
      echo "Hasura metadata apply succeeded."
      return 0
    fi

    echo "$output" >&2

    if echo "$output" | grep -qiE 'is_consistent|metadata API reported failure|metadata is inconsistent'; then
      echo "Error: Hasura metadata apply failed with a consistency/API error (not retrying)." >&2
      exit 1
    fi

    if [[ "$attempt" -lt 3 ]]; then
      echo "Hasura metadata apply attempt $attempt failed (transport); retrying in 5s..." >&2
      sleep 5
    fi
  done

  echo "Error: Hasura metadata apply failed after 3 attempts." >&2
  exit 1
}

# Configuration
DEPLOY_DIR="${DEPLOY_DIR:-/opt/tentura}"
COMPOSE_FILE="${COMPOSE_FILE:-compose.prod.yaml}"
OVERRIDE_FILE="${OVERRIDE_FILE:-compose.override.yaml}"
WEB_DIR="${WEB_DIR:-./web}"
LANDING_DIR="${LANDING_DIR:-./landing}"

# Change to deployment directory
cd "$DEPLOY_DIR" || {
  echo "Error: Cannot access deployment directory $DEPLOY_DIR" >&2
  exit 1
}

# Serialize concurrent deploys (CI + manual).
exec 9>"$DEPLOY_DIR/.deploy.lock"
if ! flock -w 1800 9; then
  echo "Error: timed out waiting for deploy lock ($DEPLOY_DIR/.deploy.lock)" >&2
  exit 1
fi

# Determine archive path
if [ $# -ge 1 ]; then
  ARCHIVE_PATH="$1"
elif [ -n "$(ls /tmp/web-*.tar.gz 2>/dev/null | head -1)" ]; then
  ARCHIVE_PATH="$(ls /tmp/web-*.tar.gz | head -1)"
else
  echo "Error: No web archive found. Please provide archive path or place it in /tmp/web-*.tar.gz" >&2
  exit 1
fi

# Verify archive exists
if [ ! -f "$ARCHIVE_PATH" ]; then
  echo "Error: Archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

echo "Deploying from archive: $ARCHIVE_PATH"

# Ensure web directory exists
mkdir -p "$WEB_DIR"

# Extract web archive to web directory
echo "Extracting web archive to $WEB_DIR..."
tar -xzf "$ARCHIVE_PATH" -C "$WEB_DIR/"
echo "Web archive extracted successfully"

# Extract landing archive (optional) — static landing served at {$LANDING_ROOT}.
# Prefer LANDING_ARCHIVE from CI; fallback only when unset (e.g. manual deploy).
if [ -z "${LANDING_ARCHIVE:-}" ]; then
  LANDING_ARCHIVE="$(ls /tmp/landing-dev.tar.gz /tmp/landing-*.tar.gz 2>/dev/null | head -1 || true)"
fi
if [ -n "$LANDING_ARCHIVE" ] && [ -f "$LANDING_ARCHIVE" ]; then
  echo "Extracting landing archive to $LANDING_DIR from $LANDING_ARCHIVE..."
  mkdir -p "$LANDING_DIR"
  tar -xzf "$LANDING_ARCHIVE" -C "$LANDING_DIR/"
  echo "Landing archive extracted successfully"
  cleanup_tmp_archive "$LANDING_ARCHIVE"
else
  echo "No landing archive found; skipping landing extraction"
fi

# Never serve an empty landing root (Risk #4 — bare 404 on dev.tentura.io).
mkdir -p "$LANDING_DIR"
if [ -z "$(find "$LANDING_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ]; then
  echo "Landing dir empty; writing placeholder index.html"
  cat > "$LANDING_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><title>Tentura</title></head>
<body><p>Landing is being deployed. Please try again shortly.</p></body></html>
EOF
fi

# --- Assets ready; restart stack (pull/down/up) -------------------------------
cleanup_tmp_archive "$ARCHIVE_PATH"

# Build compose arguments (append override file if it exists)
COMPOSE_ARGS=(-f "$COMPOSE_FILE")
if [ -f "$OVERRIDE_FILE" ]; then
  echo "Using override file: $OVERRIDE_FILE"
  COMPOSE_ARGS+=(-f "$OVERRIDE_FILE")
fi

# Pull latest Docker images
echo "Pulling latest images..."
docker compose "${COMPOSE_ARGS[@]}" pull

# Stop existing containers
echo "Stopping existing containers..."
docker compose "${COMPOSE_ARGS[@]}" down

# Start containers and wait for healthchecks
echo "Starting containers (waiting for healthchecks)..."
docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300

apply_hasura_metadata

# Show status
echo ""
echo "Deployment complete. Container status:"
docker compose "${COMPOSE_ARGS[@]}" ps
