#!/bin/bash
# Example deployment script for VPS server
# Place this at /opt/tentura/deploy.sh or ~/tentura/deploy.sh on your VPS
# Make it executable: chmod +x deploy.sh

set -e

# Configuration
DEPLOY_DIR="${DEPLOY_DIR:-/opt/tentura}"
COMPOSE_FILE="${COMPOSE_FILE:-compose.prod.yaml}"

# Change to deployment directory
cd "$DEPLOY_DIR" || { echo "Error: Cannot access deployment directory $DEPLOY_DIR"; exit 1; }

# Extract web archive if provided
if [ -f /tmp/web-*.tar.gz ]; then
    echo "Extracting web archive..."
    tar -xzf /tmp/web-*.tar.gz -C ./web/
    rm -f /tmp/web-*.tar.gz
    echo "Web archive extracted successfully"
fi

# Pull latest Docker images
echo "Pulling latest images..."
docker compose -f "$COMPOSE_FILE" pull

# Stop existing containers
echo "Stopping existing containers..."
docker compose -f "$COMPOSE_FILE" down

# Start containers
echo "Starting containers..."
docker compose -f "$COMPOSE_FILE" up -d

# Show status
echo "Deployment complete. Container status:"
docker compose -f "$COMPOSE_FILE" ps

