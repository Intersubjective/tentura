#!/bin/bash
# Deployment script for VPS server
# Usage: ./deploy.sh [archive-path]
#   archive-path: Path to web archive (default: /tmp/web-*.tar.gz)
#
# Environment variables:
#   DEPLOY_DIR      - deployment directory (default: /srv/tentura_server)
#   COMPOSE_FILE    - primary compose file (default: compose.prod.yaml)
#   OVERRIDE_FILE   - override compose file; auto-detected if not set
#                     (non-secret per-host deltas only — secrets go in .env)
#   WEB_DIR         - web assets directory (default: ./web)
#   LANDING_DIR     - static landing directory (default: ./landing)
#   LANDING_ARCHIVE - explicit path to landing tarball (CI sets this; avoids
#                     picking a stale /tmp/landing-*.tar.gz from manual uploads)
#
# Deploy order: extract web + landing archives BEFORE docker compose up -d so
# Caddy never serves an empty {$LANDING_ROOT} or stale assets at cutover.

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

# Configuration
DEPLOY_DIR="${DEPLOY_DIR:-/srv/tentura_server}"
COMPOSE_FILE="${COMPOSE_FILE:-compose.prod.yaml}"
OVERRIDE_FILE="${OVERRIDE_FILE:-compose.override.yaml}"
WEB_DIR="${WEB_DIR:-./web}"
LANDING_DIR="${LANDING_DIR:-./landing}"

# Change to deployment directory
cd "$DEPLOY_DIR" || { 
  echo "Error: Cannot access deployment directory $DEPLOY_DIR" >&2
  exit 1
}

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

# Start containers
echo "Starting containers..."
docker compose "${COMPOSE_ARGS[@]}" up -d

# Show status
echo ""
echo "Deployment complete. Container status:"
docker compose "${COMPOSE_ARGS[@]}" ps

