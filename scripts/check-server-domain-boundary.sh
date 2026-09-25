#!/usr/bin/env bash
# Fail when server domain imports concrete data/repository (CI: ! rg …).
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "check-server-domain-boundary: ripgrep (rg) is required and not installed" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/packages/server"

if rg "package:tentura_server/data/repository" lib/domain; then
  echo "check-server-domain-boundary: domain must not import data/repository" >&2
  exit 1
fi
