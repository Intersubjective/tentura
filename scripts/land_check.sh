#!/usr/bin/env bash
# Check the final tree for packages touched since a base (default origin/main).
# Each profile runs independently so failures never suppress later checks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
exec python3 - "$@" <<'PY'
import argparse
import re
import shlex
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path('scripts').resolve()))
from ci_select_tests import select

parser = argparse.ArgumentParser(description='Run landing checks against the final tree')
parser.add_argument('base', nargs='?', default='origin/main')
parser.add_argument('--dry-run', action='store_true')
args = parser.parse_args()


def git_paths(*options):
    result = subprocess.run(
        ['git', *options], check=True, stdout=subprocess.PIPE,
    )
    return set(result.stdout.decode().rstrip('\0').split('\0')) - {''}


# Disable rename folding to retain both the old and new package paths.
# Keep range and working-tree differences separate: even a reverted change
# must still select its package, while tests are discovered in the final tree.
changed = (
    git_paths('diff', '--name-only', '--no-renames', '-z', f'{args.base}..HEAD')
    | git_paths('diff', '--name-only', '--no-renames', '-z', 'HEAD')
    | git_paths('ls-files', '--others', '--exclude-standard', '-z')
)


def affected_tests(package, package_name):
    prefix = f'packages/{package}/'
    files = {path[len(prefix):] for path in changed if path.startswith(prefix)}
    root = Path(prefix)
    tests = select(root / 'test', 'pg' if package == 'server' else None)
    imports = {
        f'package:{package_name}/{path[4:]}'
        for path in files if path.startswith('lib/') and path.endswith('.dart')
    }
    selected = []
    for test in tests:
        relative = Path(test).relative_to(root).as_posix()
        source = Path(test).read_text(encoding='utf-8')
        if relative in files or any(
            re.search(r"['\"]" + re.escape(uri) + r"['\"]", source)
            for uri in imports
        ):
            selected.append(relative)
    return selected


steps = []
for package, name in (('server', 'tentura_server'), ('client', 'tentura')):
    if not any(path.startswith(f'packages/{package}/') for path in changed):
        continue
    steps.append((f'{package}-gates', ['./scripts/run_tests.sh', f'{package}-gates']))
    if package == 'server':
        steps.append(('server-unit', ['./scripts/run_tests.sh', 'server-unit']))
    tests = affected_tests(package, name)
    if tests:
        profile = f'{package}-files'
        steps.append((profile, ['./scripts/run_tests.sh', profile, *tests]))
steps.append(('check_repo_files_tags', ['python3', 'scripts/check_repo_files_tags.py']))

results = []
for label, command in steps:
    print(shlex.join(command), flush=True)
    if args.dry_run:
        results.append((label, 'DRY RUN'))
        continue
    code = subprocess.run(command).returncode
    results.append((label, 'PASS' if code == 0 else f'FAIL ({code})'))

print('\nSummary')
print(f'{"Step":<28} | Result')
print(f'{"-" * 28}-+-------------')
for label, status in results:
    print(f'{label:<28} | {status}')
sys.exit(int(any(status.startswith('FAIL') for _, status in results)))
PY
