#!/usr/bin/env bash
# Resolves and validates local web-stack URLs from repo-root .env.
#
# Required in .env: SERVER_NAME (public origin URL), IMAGE_SERVER
# Derived: APP_BASE (= SERVER_NAME + trailing /)
#
# Usage:
#   bash scripts/resolve_local_web_config.sh --check-only
#   bash scripts/resolve_local_web_config.sh --export   # print export statements
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/web_config_urls.sh
source "$ROOT/scripts/lib/web_config_urls.sh"

CHECK_ONLY=0
EXPORT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --export)
      EXPORT=1
      shift
      ;;
    -h | --help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *)
      echo "::error::Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$ROOT/.env" ]]; then
  echo "::error::Missing $ROOT/.env — copy .env.example to .env" >&2
  exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  export "$line"
done <"$ROOT/.env"

SERVER_NAME="${SERVER_NAME:-}"
IMAGE_SERVER="${IMAGE_SERVER:-}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-}"

require_absolute_url "SERVER_NAME" "$SERVER_NAME"
require_absolute_url "IMAGE_SERVER" "$IMAGE_SERVER"

if [[ -n "$GOOGLE_CLIENT_ID" && -z "${GOOGLE_CLIENT_SECRET// }" ]]; then
  echo "::error::GOOGLE_CLIENT_SECRET is required when GOOGLE_CLIENT_ID is set." >&2
  exit 1
fi

APP_BASE="$(derive_app_base "$SERVER_NAME")"

_log() {
  if [[ "$EXPORT" -eq 0 ]]; then
    echo "$@"
  fi
}

_log "resolve_local_web_config: SERVER_NAME=${SERVER_NAME}"
_log "resolve_local_web_config: IMAGE_SERVER=${IMAGE_SERVER}"
_log "resolve_local_web_config: APP_BASE=${APP_BASE}"

if [[ "$EXPORT" -eq 1 ]]; then
  cat <<EOF
export SERVER_NAME='${SERVER_NAME}'
export IMAGE_SERVER='${IMAGE_SERVER}'
export APP_BASE='${APP_BASE}'
export GOOGLE_CLIENT_ID='${GOOGLE_CLIENT_ID}'
EOF
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  echo "resolve_local_web_config: OK (check-only)"
fi
