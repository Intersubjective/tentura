#!/usr/bin/env bash
# Shared URL validation helpers for deploy and local web config scripts.

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
  local host="${value#*://}"
  host="${host%%/*}"
  host="${host%%:*}"
  if [[ -z "$host" ]]; then
    echo "::error::${name} has no host (got: ${value})." >&2
    return 1
  fi
}
