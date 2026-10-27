#!/usr/bin/env bash
# Usage: scripts/bump_client_version.sh [--minor | --set X.Y.Z]
# Requires Python 3. Only the pubspec and web bootstrap cache-buster are changed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 - "$ROOT" "$@" <<'PY'
import pathlib
import re
import sys


def fail(message):
    sys.exit(f'bump_client_version: {message}')


root = pathlib.Path(sys.argv[1])
args = sys.argv[2:]
semver = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
if args not in ([], ['--minor']):
    if len(args) != 2 or args[0] != '--set' or not re.fullmatch(semver, args[1]):
        fail('usage: bump_client_version.sh [--minor | --set X.Y.Z]')

pubspec = root / 'packages/client/pubspec.yaml'
index = root / 'packages/client/web/index.html'
try:
    pubspec_text = pubspec.read_bytes().decode('utf-8')
    index_text = index.read_bytes().decode('utf-8')
except (OSError, UnicodeError) as error:
    fail(str(error))

versions = list(re.finditer(
    rf'^version:[ \t]*(?P<version>{semver})(?:\+[0-9A-Za-z.-]+)?(?=[ \t]*(?:#.*)?\r?$)',
    pubspec_text, re.MULTILINE))
bootstraps = list(re.finditer(r'flutter_bootstrap\.js\?v=([^\s\x22\x27<>]+)', index_text))
if len(versions) != 1 or len(bootstraps) != 1:
    fail('expected exactly one valid pubspec version and one bootstrap version')
version_match = versions[0]
bootstrap_match = bootstraps[0]
old = version_match['version']
if bootstrap_match[1] != old:
    fail(f'version mismatch: pubspec={old}, index.html={bootstrap_match[1]}')

major, minor, patch = map(int, old.split('.'))
if not args:
    new = f'{major}.{minor}.{patch + 1}'
elif args == ['--minor']:
    new = f'{major}.{minor + 1}.0'
else:
    new = args[1]

# Replace the version value, dropping any build suffix and preserving comments.
value_end = version_match.end('version')
if pubspec_text[value_end:value_end + 1] == '+':
    value_end = re.match(r'\+[0-9A-Za-z.-]+', pubspec_text[value_end:]).end() + value_end
updated_pubspec = pubspec_text[:version_match.start('version')] + new + pubspec_text[value_end:]
updated_index = index_text[:bootstrap_match.start(1)] + new + index_text[bootstrap_match.end(1):]
pubspec.write_bytes(updated_pubspec.encode('utf-8'))
index.write_bytes(updated_index.encode('utf-8'))
print(f'{old} -> {new}')
PY
