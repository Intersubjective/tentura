#!/usr/bin/env bash
# Fail-fast validation for local server startup (repo-root .env).
set -euo pipefail
exec bash "$(cd "$(dirname "$0")/.." && pwd)/scripts/resolve_local_web_config.sh" --check-only
