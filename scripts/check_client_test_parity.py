#!/usr/bin/env python3
"""Compare the actual tests run by modified client test files against HEAD."""

import json
import shutil
import subprocess
import tarfile
import tempfile
from collections import Counter
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parent.parent
CLIENT = Path("packages/client")
TESTS = CLIENT / "test"
PACKAGE_CONFIG = Path(".dart_tool/package_config.json")


def git_output(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def prepare_baseline(revision, baseline):
    # An archive keeps the baseline independent without mutating the git index
    # or creating a registered worktree.
    with tempfile.TemporaryFile() as archive:
        subprocess.run(
            ["git", "archive", revision], cwd=ROOT, stdout=archive, check=True
        )
        archive.seek(0)
        with tarfile.open(fileobj=archive) as source:
            source.extractall(baseline, filter="data")

    config = ROOT / PACKAGE_CONFIG
    settings = json.loads(config.read_text())
    for package in settings["packages"]:
        uri = urlparse(urljoin(config.as_uri(), package["rootUri"]))
        if uri.scheme != "file":
            raise ValueError(f"Unsupported package root: {uri.geturl()}")
        path = Path(unquote(uri.path))
        if path.is_relative_to(ROOT):
            path = baseline / path.relative_to(ROOT)
        package["rootUri"] = path.as_uri() + "/"
    target = baseline / PACKAGE_CONFIG
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(settings))

    generated = git_output(
        "ls-files", "-z", "--others", "--ignored", "--exclude-standard",
        "--", str(CLIENT / "lib"), "packages/server/lib",
    )
    inputs = [Path(path.decode()) for path in generated.split(b"\0") if path.endswith(b".dart")]
    inputs += [Path(".dart_tool/package_graph.json"), CLIENT / "env/test.env"]
    for path in inputs:
        source, target = ROOT / path, baseline / path
        if source.is_file() and not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)


def run_report(tree, report, paths):
    subprocess.run(
        [
            str(tree / "scripts/run_with_test_cleanup.sh"), "--timeout", "12m", "--",
            "flutter", "test", "--no-pub", "--reporter=expanded",
            f"--file-reporter=json:{report}", "-j", "8", "--dart-define=ENV=test",
            "--dart-define-from-file=env/test.env", *map(str, paths),
        ],
        cwd=tree / CLIENT,
        check=True,
    )


def read_report(report, client, expected):
    suites, tests = {}, {}
    entries = Counter()
    with report.open() as lines:
        for line in lines:
            event = json.loads(line)
            if event["type"] == "suite":
                suite = event["suite"]
                suites[suite["id"]] = suite["path"]
            elif event["type"] == "testStart":
                test = event["test"]
                tests[test["id"]] = test
            elif event["type"] == "testDone" and not event["hidden"]:
                test = tests[event["testID"]]
                path = Path(suites[test["suiteID"]])
                if path.is_absolute():
                    path = path.relative_to(client)
                if path not in expected or event["result"] != "success":
                    raise SystemExit(f"{report.name}: unexpected result for {path}: {test['name']}")
                entries[path, test["name"], test["metadata"]["skip"], event["skipped"]] += 1

    missing = expected - {path for path, *_ in entries}
    if missing:
        raise SystemExit(f"{report.name}: no tests reported for {sorted(map(str, missing))}")
    return entries


def main():
    revision = git_output("rev-parse", "HEAD").decode().strip()
    modified = git_output(
        "diff", revision, "--name-only", "--diff-filter=M", "-z", "--",
        f"{TESTS}/*_test.dart",
    )
    paths = [Path(path.decode()).relative_to(CLIENT) for path in modified.split(b"\0") if path]
    if not paths:
        raise SystemExit("No modified existing client test files to compare")

    with tempfile.TemporaryDirectory(prefix="client-test-parity-") as directory:
        scratch = Path(directory)
        baseline = scratch / "baseline"
        prepare_baseline(revision, baseline)
        reports = []
        for side, tree in (("baseline", baseline), ("current", ROOT)):
            print(f"Running {side} tests", flush=True)
            report = scratch / f"{side}.jsonl"
            run_report(tree, report, paths)
            reports.append(read_report(report, tree / CLIENT, set(paths)))

    before, after = reports
    if before != after:
        for side, difference in (("baseline", before - after), ("current", after - before)):
            for entry, count in sorted(difference.items()):
                print(f"Only in {side} ({count}): {entry}")
        raise SystemExit(1)
    print(f"Both runs passed. {sum(after.values())} names and skip statuses match across {len(paths)} files.")


if __name__ == "__main__":
    main()
