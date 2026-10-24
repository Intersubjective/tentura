#!/usr/bin/env python3
"""List the test files that can contain tests with a given tag, optionally
one shard of them.

`dart test --tags X` has to load every suite under test/ to find tests tagged
X inside groups, one at a time at `-j 1`: the multi-connection run spent 132 s
loading 618 files to run 26 s of tests. Passing only the files that mention
the tag skips that. Sharding splits a suite across runners (each pg shard
with its own Postgres) by file, so no runner loads another's suites.

A file qualifies when its source contains the tag as a quoted literal, the
only way this repo writes tags (`@Tags(['pg'])`, `tags: ['multi-connection']`).
Without --tag every `*_test.dart` file qualifies.

Usage: scripts/ci_select_tests.py <test-dir> [--tag TAG] [--shard I/N]
                                  [--balance FAMILY [--reserve-last TAG]]
  Prints matching `*_test.dart` paths (relative to the current directory),
  sorted; with --shard, every N-th of them starting at the I-th (1-based).

  --balance FAMILY packs the N shards by measured duration instead, from
  FAMILY's entries in scripts/ci_test_durations.json (--durations to read
  another file; keys are paths relative to the package, `test/...`): longest
  first, each file onto the shard with the least time so far. A file without
  an entry weighs the family's median, so a new test file still lands on
  exactly one shard; a stale file only costs balance (refresh it with
  scripts/ci_test_durations.py). The shard's files are printed longest
  first, so `dart test` starts the long suites first instead of ending on
  one. --reserve-last TAG books TAG's run on the last shard before packing:
  CI runs that selection there too (the `-j 1` multi-connection run on the
  last pg shard). A summary of the packing goes to stderr.

  Durations are slot-seconds: how long a file occupies one of the runner's
  concurrent test slots (its loading included). A run's wall time is about
  its slot-seconds over the family's measured parallelism (the `_parallelism`
  entry), which is also how a reserved run at another concurrency is booked.
"""

from __future__ import annotations

import argparse
import functools
import json
import re
import statistics
import sys
from pathlib import Path

DURATIONS = Path(__file__).resolve().parent / "ci_test_durations.json"


def select(test_dir: Path, tag: str | None) -> list[str]:
    """Sorted `*_test.dart` paths under [test_dir] that mention [tag]."""
    literal = re.compile(r"""['"]""" + re.escape(tag) + r"""['"]""") if tag else None
    return sorted(
        path.as_posix()
        for path in test_dir.rglob("*_test.dart")
        if "_bundle" not in path.parts
        and (literal is None or literal.search(path.read_text(encoding="utf-8")))
    )


@functools.lru_cache(maxsize=None)
def package_root(directory: Path) -> Path | None:
    """The nearest directory at or above [directory] with a pubspec.yaml."""
    if (directory / "pubspec.yaml").is_file():
        return directory
    return None if directory.parent == directory else package_root(directory.parent)


def package_key(path: str) -> str:
    """The durations file's key for a test file: its path relative to its
    package, `test/...`."""
    resolved = Path(path).resolve()
    root = package_root(resolved.parent)
    return resolved.relative_to(root).as_posix() if root else Path(path).as_posix()


def weights(files: list[str], table: dict[str, float]) -> dict[str, float]:
    """Seconds per file; a file the table does not know weighs the median
    of the files that took any time (0 marks one the run never loaded)."""
    timed = [v for v in table.values() if v > 0]
    median = statistics.median(timed) if timed else 1.0
    return {f: float(table.get(package_key(f), median)) for f in files}


def pack(weight: dict[str, float], count: int, preload_last: float = 0.0):
    """Longest-processing-time packing: heaviest first, onto the lightest
    shard (lowest index on ties). Deterministic for a given input. Each
    shard lists its items heaviest first."""
    loads = [0.0] * count
    loads[-1] += preload_last
    shards: list[list[str]] = [[] for _ in range(count)]
    for f in sorted(weight, key=lambda f: (-weight[f], f)):
        i = min(range(count), key=lambda i: (loads[i], i))
        shards[i].append(f)
        loads[i] += weight[f]
    return shards, loads


class Durations:
    """scripts/ci_test_durations.json: slot-seconds per file per family."""

    def __init__(self, path: Path = DURATIONS) -> None:
        self.path = path
        self.data = json.loads(path.read_text(encoding="utf-8"))

    def table(self, family: str) -> dict[str, float]:
        table = self.data.get(family)
        if not isinstance(table, dict):
            raise SystemExit(f"ci_select_tests: no '{family}' durations in {self.path}")
        return table

    def parallelism(self, family: str) -> float:
        """Slot-seconds per wall second in the family's CI runs."""
        return float(self.data.get("_parallelism", {}).get(family, 1.0))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("test_dir", type=Path)
    parser.add_argument("--tag")
    parser.add_argument("--shard", default="1/1")
    parser.add_argument("--balance", metavar="FAMILY")
    parser.add_argument("--durations", type=Path, default=DURATIONS)
    parser.add_argument("--reserve-last", metavar="TAG")
    args = parser.parse_args(argv)

    index, count = (int(part) for part in args.shard.split("/"))
    if not 1 <= index <= count:
        parser.error(f"--shard {args.shard}: need 1 <= I <= N")
    if args.reserve_last and not args.balance:
        parser.error("--reserve-last needs --balance")

    files = select(args.test_dir, args.tag)
    if not args.balance:
        print("\n".join(files[index - 1 :: count]))
        return 0

    durations = Durations(args.durations)
    weight = weights(files, durations.table(args.balance))
    parallel = durations.parallelism(args.balance)
    reserved = 0.0
    if args.reserve_last and count > 1:
        # The reserved run's wall time, as slot-seconds of this family.
        extra = select(args.test_dir, args.reserve_last)
        busy = sum(weights(extra, durations.table(args.reserve_last)).values())
        reserved = busy / durations.parallelism(args.reserve_last) * parallel
    shards, loads = pack(weight, count, reserved)
    print(
        f"ci_select_tests: shard {index}/{count}: {len(shards[index - 1])} of "
        f"{len(files)} files, ~{loads[index - 1] / parallel:.0f} s by "
        f"{args.durations.name} (all shards: "
        f"{', '.join(f'{load / parallel:.0f}' for load in loads)} s"
        + (f"; {reserved / parallel:.0f} s of {args.reserve_last} on the last" if reserved else "")
        + ")",
        file=sys.stderr,
    )
    print("\n".join(shards[index - 1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
