#!/usr/bin/env bash
# Validates FB_* keys in a dart-define-from-file .env before flutter build web.
set -euo pipefail

ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "validate_client_firebase_env: skip (no $ENV_FILE)"
  exit 0
fi

fb_api_key="$(grep -E '^FB_API_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r' || true)"
fb_app_id="$(grep -E '^FB_APP_ID=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r' || true)"

if [[ -z "$fb_api_key" ]]; then
  echo "validate_client_firebase_env: skip (FB_API_KEY empty — FCM disabled)"
  exit 0
fi

if [[ -z "$fb_app_id" ]]; then
  echo "::error::FB_APP_ID is missing in $ENV_FILE (CLIENT_DART_DEFINES). Installations API will return 400."
  exit 1
fi

if [[ "$fb_app_id" == AIza* ]]; then
  echo "::error::FB_APP_ID must be the Firebase Web App ID (1:…:web:…), not the API key (AIza…)."
  exit 1
fi

if [[ "$fb_app_id" != 1:* ]]; then
  echo "::error::FB_APP_ID must start with 1: (got: ${fb_app_id:0:20}…)"
  exit 1
fi

if [[ "$fb_app_id" != *:web:* && "$fb_app_id" != *:android:* && "$fb_app_id" != *:ios:* ]]; then
  echo "::error::FB_APP_ID must contain :web:, :android:, or :ios: platform segment."
  exit 1
fi

echo "validate_client_firebase_env: OK (FB_APP_ID format)"
