#!/usr/bin/env bash
# Resolves and validates local web-stack URLs from repo-root .env.
#
# Required in .env: APP_ORIGIN, LANDING_ORIGIN, IMAGE_SERVER, SERVER_NAME
# Derived: WS_SERVER_NAME (= APP_ORIGIN), APP_BASE (= APP_ORIGIN + /)
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

APP_ORIGIN="${APP_ORIGIN:-}"
LANDING_ORIGIN="${LANDING_ORIGIN:-}"
IMAGE_SERVER="${IMAGE_SERVER:-}"
SERVER_NAME="${SERVER_NAME:-}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-}"

require_absolute_url "APP_ORIGIN" "$APP_ORIGIN"
require_absolute_url "LANDING_ORIGIN" "$LANDING_ORIGIN"
require_absolute_url "IMAGE_SERVER" "$IMAGE_SERVER"
require_absolute_url "SERVER_NAME" "$SERVER_NAME"

if [[ "$APP_ORIGIN" != "$LANDING_ORIGIN" ]]; then
  echo "::error::APP_ORIGIN and LANDING_ORIGIN must match (single-host); got APP_ORIGIN=${APP_ORIGIN} LANDING_ORIGIN=${LANDING_ORIGIN}" >&2
  exit 1
fi

if [[ -n "$GOOGLE_CLIENT_ID" && -z "${GOOGLE_CLIENT_SECRET// }" ]]; then
  echo "::error::GOOGLE_CLIENT_SECRET is required when GOOGLE_CLIENT_ID is set." >&2
  exit 1
fi

WS_SERVER_NAME="${WS_SERVER_NAME:-$APP_ORIGIN}"
require_absolute_url "WS_SERVER_NAME" "$WS_SERVER_NAME"

APP_BASE="$(derive_app_base "$APP_ORIGIN")"
CLIENT_SERVER_NAME="$APP_ORIGIN"
INVITE_LINK_HOST="$LANDING_ORIGIN"

_log() {
  if [[ "$EXPORT" -eq 0 ]]; then
    echo "$@"
  fi
}

_log "resolve_local_web_config: SERVER_NAME=${SERVER_NAME}"
_log "resolve_local_web_config: APP_ORIGIN=${APP_ORIGIN}"
_log "resolve_local_web_config: LANDING_ORIGIN=${LANDING_ORIGIN}"
_log "resolve_local_web_config: IMAGE_SERVER=${IMAGE_SERVER}"
_log "resolve_local_web_config: WS_SERVER_NAME=${WS_SERVER_NAME}"
_log "resolve_local_web_config: APP_BASE=${APP_BASE}"

if [[ "$EXPORT" -eq 1 ]]; then
  cat <<EOF
export SERVER_NAME='${SERVER_NAME}'
export APP_ORIGIN='${APP_ORIGIN}'
export LANDING_ORIGIN='${LANDING_ORIGIN}'
export IMAGE_SERVER='${IMAGE_SERVER}'
export WS_SERVER_NAME='${WS_SERVER_NAME}'
export APP_BASE='${APP_BASE}'
export CLIENT_SERVER_NAME='${CLIENT_SERVER_NAME}'
export INVITE_LINK_HOST='${INVITE_LINK_HOST}'
export GOOGLE_CLIENT_ID='${GOOGLE_CLIENT_ID}'
EOF
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  echo "resolve_local_web_config: OK (check-only)"
fi