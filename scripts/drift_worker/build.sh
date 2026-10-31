#!/usr/bin/env bash
# Usage: scripts/drift_worker/build.sh
#
# Rebuilds packages/client/web/assets/packages/drift_worker.js from the drift
# version the workspace resolved, compiled against a copy of the resolved
# sqlite3 with sqlite3-wasm-lock-level.patch applied (#853). Upstream's OPFS
# WasmFile never lowers its lock level on xUnlock: after the first transaction
# the tab stops taking the file lock explicitly, and xCheckReservedLock always
# reports a reserved lock, so a journal left by a closed tab is never rolled
# back. The app's own sqlite3 dependency stays unpatched; only the worker uses
# the copy.
#
# Run `dart pub get` first. Rerun after upgrading drift or sqlite3; the patch
# fails to apply when upstream changed that code, which is the cue to check
# whether it is still needed. Requires Python 3 and patch(1).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/scripts/drift_worker"
OUT="$ROOT/packages/client/web/assets/packages/drift_worker.js"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Copies the resolved sqlite3 into $WORK/sqlite3, writes a package config that
# points sqlite3 there, and prints drift's worker entry point.
ENTRY="$(python3 - "$ROOT/.dart_tool/package_config.json" "$WORK" <<'PY'
import json
import pathlib
import shutil
import sys
from urllib.parse import urlparse

config_path = pathlib.Path(sys.argv[1])
work = pathlib.Path(sys.argv[2])
config = json.loads(config_path.read_text())
roots = {}
for package in config['packages']:
    uri = urlparse(package['rootUri'])
    if uri.scheme == 'file':
        roots[package['name']] = pathlib.Path(uri.path)
    else:
        roots[package['name']] = (config_path.parent / uri.path).resolve()
        package['rootUri'] = roots[package['name']].as_uri()
for name in ('drift', 'sqlite3'):
    if name not in roots:
        sys.exit(f'build.sh: {name} is not in {config_path}; run dart pub get')

patched = work / 'sqlite3'
shutil.copytree(roots['sqlite3'], patched)
for path in patched.rglob('*'):
    path.chmod(path.stat().st_mode | 0o200)
for package in config['packages']:
    if package['name'] == 'sqlite3':
        package['rootUri'] = patched.as_uri()
(work / 'package_config.json').write_text(json.dumps(config))
print(roots['drift'] / 'web' / 'drift_worker.dart')
PY
)"

patch --quiet --forward -p1 -d "$WORK/sqlite3" < "$HERE/sqlite3-wasm-lock-level.patch"

dart compile js -O4 --no-source-maps \
  --packages="$WORK/package_config.json" \
  -o "$WORK/drift_worker.js" "$ENTRY"
cp "$WORK/drift_worker.js" "$OUT"
echo "build.sh: wrote $OUT"
