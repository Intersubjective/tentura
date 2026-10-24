#!/usr/bin/env python3
"""Per-file test durations from CI's JSON test reports: the weights that
`scripts/ci_select_tests.py --balance` packs shards with, and test counts.

Every client and pg test run in CI (pipeline.yml, test-shards) also writes a
`--file-reporter json:` report, `test-reports/<family>--<job>.json`, uploaded
as the artifact `test-reports-a<attempt>-<job>`. Families: `client` (the
client shards), `pg` (the pool-size-1 pg runs), `multi-connection` (the
`-j 1` multi-connection run on the last pg shard).

Refresh the committed durations file from a green run that ran everything
(push to main, or a PR with the `ci:full` label):

  scripts/ci_test_durations.py update --run <run-id> [--run <run-id> ...]

That downloads the run's report artifacts with `gh run download` (latest
attempt) and rewrites scripts/ci_test_durations.json. Several runs are
averaged per file. `update <dir>...` reads already-downloaded reports instead.

A stale file only costs balance, never correctness: shards are packed from
the files that exist now (new files weigh the family's median, deleted files'
entries are ignored), and scripts/test_ci_select_tests.py checks that the
shards always cover every file exactly once. Refresh it when the slowest and
fastest shard of a family drift more than ~25% apart.

  scripts/ci_test_durations.py counts --run <run-id> | <dir>... [--per-file]

prints how many tests each family ran (passed / skipped / failed, as the
`dart test` summary counts them), to check that a change to the shard layout
lost no tests; `--per-file` lists the count per test file, for a diff.

How a file's duration is measured: the report gives every test's start and
end. A standalone suite's duration is the sum of its tests', its loading
(compile) included; inside a bundle (scripts/gen_test_bundles.py) each test
belongs to the file named by its outermost group, and the bundle's own
loading is per-shard overhead, booked to no file. Runs at different
concurrency are made comparable by scaling each report so that the time it
booked, overhead included, sums to its wall time: a duration is then the
wall-clock seconds the file adds to its shard.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

DURATIONS = Path(__file__).resolve().parent / "ci_test_durations.json"
FAMILIES = ("client", "multi-connection", "pg")
TEST_PATH = re.compile(r"(?:^|/packages/[^/]+/)(test/\S+?_test\.dart)$")


def package_path(path: str) -> str:
    """`test/...` for a suite path, absolute or package-relative."""
    match = TEST_PATH.search(path)
    return match.group(1) if match else path


class Report:
    """One `dart test` / `flutter test` run's JSON report."""

    def __init__(self, path: Path) -> None:
        self.family = path.name.split("--", 1)[0]
        self.wall = 0.0
        self.overhead = 0.0
        self.seconds: dict[str, float] = defaultdict(float)
        self.counts: dict[str, dict[str, int]] = defaultdict(
            lambda: {"passed": 0, "skipped": 0, "failed": 0}
        )
        suites: dict[int, str] = {}
        groups: dict[int, str] = {}
        running: dict[int, tuple[float, str | None]] = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.startswith("{"):
                continue
            event = json.loads(line)
            now = event.get("time", 0) / 1000
            self.wall = max(self.wall, now)
            kind = event.get("type")
            if kind == "suite":
                suite = event["suite"]
                suites[suite["id"]] = suite.get("path") or ""
            elif kind == "group":
                group = event["group"]
                groups[group["id"]] = group.get("name") or ""
            elif kind == "testStart":
                test = event["test"]
                suite_path = suites.get(test["suiteID"], "")
                if "/_bundle/" in f"/{suite_path}":
                    # The bundle's `group('<file>', ...)` is the outermost
                    # named group; the bundle's own loading test has none.
                    names = [groups.get(g, "") for g in test.get("groupIDs", [])]
                    owner = next((n for n in names if n), None)
                    owner = package_path(owner.split(" ", 1)[0]) if owner else None
                else:
                    owner = package_path(suite_path)
                running[test["id"]] = (now, owner)
            elif kind == "testDone":
                start, owner = running.pop(event["testID"], (now, None))
                if owner is None:
                    self.overhead += now - start
                else:
                    self.seconds[owner] += now - start
                if not event.get("hidden") and owner is not None:
                    counts = self.counts[owner]
                    if event.get("skipped"):
                        counts["skipped"] += 1
                    elif event.get("result") == "success":
                        counts["passed"] += 1
                    else:
                        counts["failed"] += 1

    def scaled(self) -> dict[str, float]:
        """Seconds per file, scaled so the run's booked time is its wall."""
        booked = sum(self.seconds.values()) + self.overhead
        scale = self.wall / booked if booked > 0 else 0.0
        return {path: seconds * scale for path, seconds in self.seconds.items()}


def reports_in(sources: list[str], runs: list[str], workdir: Path) -> list[Report]:
    dirs = [Path(s) for s in sources]
    for run in runs:
        target = workdir / run
        subprocess.run(
            ["gh", "run", "download", run, "--pattern", "test-reports-*", "--dir", str(target)],
            check=True,
        )
        # Only the run's latest attempt: a rerun uploads under a new name.
        attempts: dict[int, list[Path]] = defaultdict(list)
        for artifact in target.iterdir():
            match = re.match(r"test-reports-a(\d+)-", artifact.name)
            if match and artifact.is_dir():
                attempts[int(match.group(1))].append(artifact)
        if not attempts:
            raise SystemExit(f"run {run}: no test-reports-a<attempt>-* artifacts")
        dirs += attempts[max(attempts)]
    reports = [Report(p) for d in dirs for p in sorted(d.rglob("*--*.json"))]
    unknown = sorted({r.family for r in reports} - set(FAMILIES))
    if unknown:
        raise SystemExit(f"unknown report families: {unknown}")
    if not reports:
        raise SystemExit("no reports found")
    return reports


def update(reports: list[Report], out: Path, runs: list[str]) -> None:
    samples: dict[str, dict[str, list[float]]] = {f: defaultdict(list) for f in FAMILIES}
    for report in reports:
        for path, seconds in report.scaled().items():
            samples[report.family][path].append(seconds)
    data: dict[str, object] = {
        "_about": "Per-file CI test durations (wall seconds) for "
        "scripts/ci_select_tests.py --balance. Regenerate with "
        "scripts/ci_test_durations.py update --run <run-id>; see its docstring.",
        "_runs": runs,
    }
    for family in FAMILIES:
        data[family] = {
            path: round(max(sum(v) / len(v), 0.01), 2)
            for path, v in sorted(samples[family].items())
        }
    out.write_text(json.dumps(data, indent=1, sort_keys=False) + "\n", encoding="utf-8")
    for family in FAMILIES:
        table = data[family]
        print(f"{family}: {len(table)} files, {sum(table.values()):.0f} s", file=sys.stderr)


def counts(reports: list[Report], per_file: bool) -> None:
    totals: dict[str, dict[str, int]] = {}
    files: dict[str, dict[str, int]] = {}
    for report in reports:
        total = totals.setdefault(report.family, {"passed": 0, "skipped": 0, "failed": 0})
        for path, c in report.counts.items():
            key = f"{report.family} {path}"
            entry = files.setdefault(key, {"passed": 0, "skipped": 0, "failed": 0})
            for k, v in c.items():
                total[k] += v
                entry[k] += v
    for family in sorted(totals):
        t = totals[family]
        print(f"{family}: {t['passed']} passed, {t['skipped']} skipped, {t['failed']} failed")
    if per_file:
        for key in sorted(files):
            c = files[key]
            print(f"{key} {c['passed']} {c['skipped']} {c['failed']}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", choices=("update", "counts"))
    parser.add_argument("dirs", nargs="*", help="directories holding *--*.json reports")
    parser.add_argument("--run", action="append", default=[], help="CI run id to download")
    parser.add_argument("--out", type=Path, default=DURATIONS)
    parser.add_argument("--per-file", action="store_true")
    args = parser.parse_intermixed_args(argv)
    if not args.dirs and not args.run:
        parser.error("give report directories or --run <run-id>")
    with tempfile.TemporaryDirectory() as tmp:
        reports = reports_in(args.dirs, args.run, Path(tmp))
        if args.command == "update":
            update(reports, args.out, args.run)
        else:
            counts(reports, args.per_file)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
