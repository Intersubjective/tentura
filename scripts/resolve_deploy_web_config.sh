#!/usr/bin/env bash
# Resolves and validates dev web-build deploy variables before flutter build / landing package.
#
# Required env: CLIENT_SERVER_NAME, IMAGE_SERVER
# Optional env (derived when empty): INVITE_LINK_HOST, APP_BASE
#
# Usage:
#   bash scripts/resolve_deploy_web_config.sh
#   bash scripts/resolve_deploy_web_config.sh --github-output "$GITHUB_OUTPUT"
#   bash scripts/resolve_deploy_web_config.sh --check-only
set -euo pipefail

GITHUB_OUTPUT=""
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-output)
      GITHUB_OUTPUT="${2:?--github-output requires a file path}"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY=1
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

require_absolute_url() {
  local name="$1"
  local value="$2"
  if [[ -z "${value// }" ]]; then
    echo "::error::${name} is required (non-empty absolute http(s) URL)." >&2
    return 1
  fi
  if [[ ! "$value" =~ ^https?://[^/]+ ]]; then
    echo "::error::${name} must be an absolute URL with scheme and host (got: ${value})." >&2
    return 1
  fi
  # Reject authority-less or path-only mistakes.
  local host="${value#*://}"
  host="${host%%/*}"
  host="${host%%:*}"
  if [[ -z "$host" ]]; then
    echo "::error::${name} has no host (got: ${value})." >&2
    return 1
  fi
}

derive_invite_link_host() {
  local client_server_name="$1"
  printf '%s' "$client_server_name" | sed -E 's#(https?://)app\.#\1#'
}

derive_app_base() {
  local client_server_name="$1"
  if [[ "$client_server_name" == */ ]]; then
    printf '%s' "$client_server_name"
  else
    printf '%s/' "$client_server_name"
  fi
}

CLIENT_SERVER_NAME="${CLIENT_SERVER_NAME:-}"
IMAGE_SERVER="${IMAGE_SERVER:-}"
INVITE_LINK_HOST="${INVITE_LINK_HOST:-}"
APP_BASE="${APP_BASE:-}"

require_absolute_url "CLIENT_SERVER_NAME" "$CLIENT_SERVER_NAME"
require_absolute_url "IMAGE_SERVER" "$IMAGE_SERVER"

if [[ -n "$INVITE_LINK_HOST" ]]; then
  require_absolute_url "INVITE_LINK_HOST" "$INVITE_LINK_HOST"
else
  INVITE_LINK_HOST="$(derive_invite_link_host "$CLIENT_SERVER_NAME")"
  require_absolute_url "INVITE_LINK_HOST" "$INVITE_LINK_HOST"
fi

if [[ -n "$APP_BASE" ]]; then
  require_absolute_url "APP_BASE" "$APP_BASE"
  case "$APP_BASE" in
    */) ;;
    *)
      echo "::error::APP_BASE must end with / (got: ${APP_BASE})." >&2
      exit 1
      ;;
  esac
else
  APP_BASE="$(derive_app_base "$CLIENT_SERVER_NAME")"
fi

echo "resolve_deploy_web_config: CLIENT_SERVER_NAME=${CLIENT_SERVER_NAME}"
echo "resolve_deploy_web_config: IMAGE_SERVER=${IMAGE_SERVER}"
echo "resolve_deploy_web_config: INVITE_LINK_HOST=${INVITE_LINK_HOST}"
echo "resolve_deploy_web_config: APP_BASE=${APP_BASE}"

if [[ -n "$GITHUB_OUTPUT" ]]; then
  {
    echo "client_server_name=${CLIENT_SERVER_NAME}"
    echo "image_server=${IMAGE_SERVER}"
    echo "invite_link_host=${INVITE_LINK_HOST}"
    echo "app_base=${APP_BASE}"
  } >>"$GITHUB_OUTPUT"
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  echo "resolve_deploy_web_config: OK (check-only)"
fi
