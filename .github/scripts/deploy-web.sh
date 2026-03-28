#!/bin/bash
set -euo pipefail

# Deploy web archive to VPS
# Usage: deploy-web.sh <archive-name> <environment>
# Example: deploy-web.sh web-abc123.tar.gz dev

ARCHIVE_NAME="$1"
ENVIRONMENT="$2"
VPS_HOST="${VPS_HOST:-}"

if [ -z "$VPS_HOST" ]; then
  echo "Error: VPS_HOST environment variable is not set"
  exit 1
fi

# Mask VPS host to prevent logging
echo "::add-mask::$VPS_HOST"

# Validate archive exists
if [ ! -f "$ARCHIVE_NAME" ]; then
  echo "Error: Archive file $ARCHIVE_NAME not found" >&2
  exit 1
fi

# Copy archive to VPS (SSH agent handles authentication)
scp -o StrictHostKeyChecking=accept-new "$ARCHIVE_NAME" deploy@"$VPS_HOST":/tmp/

# Deploy via SSH (SSH agent handles authentication)
ARCHIVE_FILENAME=$(basename "$ARCHIVE_NAME")
ssh -o StrictHostKeyChecking=accept-new deploy@"$VPS_HOST" \
    "chmod +x /srv/tentura_server/deploy.sh && /srv/tentura_server/deploy.sh /tmp/$ARCHIVE_FILENAME $ENVIRONMENT"

# Clean up archive from /tmp after successful deployment
ssh -o StrictHostKeyChecking=accept-new deploy@"$VPS_HOST" \
    "rm -f /tmp/$ARCHIVE_FILENAME"

