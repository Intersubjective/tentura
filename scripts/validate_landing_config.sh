#!/usr/bin/env bash
# Validates landing appBase in config.js (CI) or config.js + config.local.js (--local).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANDING_DIR="$ROOT/packages/landing"
LOCAL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      LOCAL=1
      shift
      ;;
    -h | --help)
      sed -n '1,8p' "$0"
      exit 0
      ;;
    *)
      echo "::error::Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

extract_app_base() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  grep -E "appBase:" "$file" | head -1 | sed -E "s/.*appBase:[[:space:]]*'([^']*)'.*/\1/"
}

CONFIG_JS="$LANDING_DIR/config.js"
LOCAL_JS="$LANDING_DIR/config.local.js"

if [[ ! -f "$CONFIG_JS" ]]; then
  echo "::error::Missing $CONFIG_JS" >&2
  exit 1
fi

if [[ "$LOCAL" -eq 1 && ! -f "$LOCAL_JS" ]]; then
  echo "::error::Missing $LOCAL_JS — run ./scripts/sync-landing-local-config.sh" >&2
  exit 1
fi

app_base="$(extract_app_base "$CONFIG_JS")"
if [[ "$LOCAL" -eq 1 ]]; then
  local_base="$(extract_app_base "$LOCAL_JS")"
  if [[ -n "$local_base" ]]; then
    app_base="$local_base"
  fi
fi

if [[ -z "${app_base// }" ]]; then
  echo "::error::landing appBase is empty (config.js${LOCAL:+, config.local.js})" >&2
  exit 1
fi

if [[ ! "$app_base" =~ ^https?://[^/]+ ]]; then
  echo "::error::landing appBase must be an absolute http(s) URL (got: ${app_base})" >&2
  exit 1
fi

echo "validate_landing_config: OK appBase=${app_base}"
