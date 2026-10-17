#!/usr/bin/env python3
"""Every test that reads files outside its own package carries `repo-files`.

The Pipeline skips a package's tests when a push does not touch the package,
except for the tests tagged `repo-files`: those read docs/contracts, scripts,
workflows, hasura metadata or the other package, so a change there can break
them (scripts/ci_changes.py). An untagged one would silently stop running on
exactly the pushes that can break it.

A test "reads outside" when, outside imports and comments, it or a test-side
support file it imports (transitively, relative imports only) contains:
  * a string literal starting with `../` (tests run from the package root),
  * a repository-root helper (`repoRoot`, `_repositoryRoot`, `.parent.parent`,
    `Directory.current.parent`),
  * a repo-level path literal (`docs/`, `hasura/`, `.github/`,
    `packages/<name>/`).
False positives only cost a few extra tests on such pushes; tag them anyway.

Usage: scripts/check_repo_files_tags.py [--list]   (from anywhere)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PACKAGES = ("packages/server", "packages/client")
TAG = "repo-files"

OUTSIDE = re.compile(
    r"""['"]\.\./"""
    r"|\b_?[Rr]epo(sitory)?Root\b|\brepoRoot|\b_?repositoryRoot"
    r"|\.parent\.parent|Directory\.current\.parent"
    r"""|['"/](docs|hasura|\.github)/"""
    r"""|['"]packages/\w+/"""
)
IMPORT = re.compile(r"""^\s*(import|export|part)\s+['"]([^'"]+)['"]""")
FILE_TAGS = re.compile(r"^@Tags\(\s*(?:<String>)?\[([^\]]*)\]", re.MULTILINE)


def code_lines(source: str) -> list[str]:
    lines = []
    for line in source.splitlines():
        stripped = line.strip()
        if stripped.startswith("//") or IMPORT.match(line):
            continue
        lines.append(line)
    return lines


def reads_outside(path: Path, test_root: Path, seen: set[Path]) -> bool:
    if path in seen or not path.is_file():
        return False
    seen.add(path)
    source = path.read_text(encoding="utf-8")
    if any(OUTSIDE.search(line) for line in code_lines(source)):
        return True
    for line in source.splitlines():
        match = IMPORT.match(line)
        if not match or ":" in match.group(2):
            continue  # package: and dart: imports are not test-side helpers
        target = (path.parent / match.group(2)).resolve()
        if test_root in target.parents and reads_outside(target, test_root, seen):
            return True
    return False


def file_tags(source: str) -> set[str]:
    match = FILE_TAGS.search(source)
    if not match:
        return set()
    return {t.strip().strip("'\"") for t in match.group(1).split(",") if t.strip()}


def main(argv: list[str]) -> int:
    missing, tagged = [], []
    for package in PACKAGES:
        test_root = (REPO_ROOT / package / "test").resolve()
        for test in sorted(test_root.rglob("*_test.dart")):
            if "_bundle" in test.parts:
                continue
            if not reads_outside(test.resolve(), test_root, set()):
                continue
            rel = test.relative_to(REPO_ROOT).as_posix()
            tagged.append(rel)
            if TAG not in file_tags(test.read_text(encoding="utf-8")):
                missing.append(rel)
    if "--list" in argv:
        print("\n".join(tagged))
        return 0
    if missing:
        print(
            f"check_repo_files_tags: {len(missing)} test(s) read files outside "
            f"their package but lack @Tags(['{TAG}']):",
            file=sys.stderr,
        )
        for rel in missing:
            print(f"  {rel}", file=sys.stderr)
        return 1
    print(f"check_repo_files_tags: {len(tagged)} repo-files tests, all tagged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
