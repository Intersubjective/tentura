#!/usr/bin/env bash
set -euo pipefail

# Runs the tentura-lvsg required verification check (MeritRank constellation-field pg suites).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${ROOT}/scripts/alloy-required-verification-checks.json"
KEY="tentura-lvsg"

mapfile -t _lines < <(
  python3 - "${REGISTRY}" "${KEY}" <<'PY'
import json
import sys

registry_path, key = sys.argv[1], sys.argv[2]
with open(registry_path, encoding="utf-8") as f:
    entry = json.load(f)[key]
print(entry["cwd"])
for arg in entry["argv"]:
    print(arg)
PY
)

CWD_REL="${_lines[0]}"
ARGV=("${_lines[@]:1}")

cd "${ROOT}/${CWD_REL}"
exec dart "${ARGV[@]}"
