#!/usr/bin/env python3
"""List the test files that can contain tests with a given tag, optionally
one shard of them.

`dart test --tags X` has to load every suite under test/ to find tests tagged
X inside groups, one at a time at `-j 1`: the multi-connection run spent 132 s
loading 618 files to run 26 s of tests. Passing only the files that mention
the tag skips that. Sharding splits the pg suite across runners (each with its
own Postgres) by file, so no runner loads another's suites.

A file qualifies when its source contains the tag as a quoted literal, the
only way this repo writes tags (`@Tags(['pg'])`, `tags: ['multi-connection']`).

Usage: scripts/ci_select_tests.py <test-dir> --tag TAG [--shard I/N]
  Prints matching `*_test.dart` paths (relative to the current directory),
  sorted; with --shard, every N-th of them starting at the I-th (1-based).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("test_dir", type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--shard", default="1/1")
    args = parser.parse_args(argv)

    index, count = (int(part) for part in args.shard.split("/"))
    if not 1 <= index <= count:
        parser.error(f"--shard {args.shard}: need 1 <= I <= N")

    literal = re.compile(r"""['"]""" + re.escape(args.tag) + r"""['"]""")
    files = sorted(
        path.as_posix()
        for path in args.test_dir.rglob("*_test.dart")
        if "_bundle" not in path.parts
        and literal.search(path.read_text(encoding="utf-8"))
    )
    print("\n".join(files[index - 1 :: count]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
