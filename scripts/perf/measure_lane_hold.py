#!/usr/bin/env python3
"""Measure frozen before/after server sources without changing git or HEAD."""

import argparse
import io
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "packages/server"
REPORT_PATH = "docs/performance/lane-hold-transactions.json"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True, help="Unmodified baseline commit")
    parser.add_argument("--pr-url", help="Existing PR receiving the generated table")
    args = parser.parse_args()
    if not os.environ.get("TENTURA_LANE_HOLD_PERF_DB"):
        parser.error("Set TENTURA_LANE_HOLD_PERF_DB to a dedicated tentura_test_* DB")
    baseline = git("rev-parse", "--verify", f"{args.before}^{{commit}}").decode().strip()
    dart = Path(shutil.which("dart") or "dart").resolve()
    sdk_dart = dart.parent / "cache/dart-sdk/bin/dart"
    if sdk_dart.is_file():
        dart = sdk_dart
    snapshots = Path(tempfile.mkdtemp(prefix="tentura-lane-hold-"))
    before = snapshots / "before/packages/server"
    after = snapshots / "after/packages/server"
    for source in (before, after):
        shutil.copytree(SERVER / "lib", source / "lib")
    # Generated files are ignored by git. Keep the identical generated outputs
    # in both snapshots, then restore all tracked baseline implementation files.
    with tarfile.open(fileobj=io.BytesIO(git("archive", baseline, "packages/server/lib"))) as archive:
        archive.extractall(snapshots / "before", filter="data")
    baseline_files = set(git("ls-tree", "-r", "--name-only", baseline,
                             "packages/server/lib").decode().splitlines())
    current_files = set(git("ls-files", "packages/server/lib").decode().splitlines())
    for path in current_files - baseline_files:
        (snapshots / "before" / path).unlink(missing_ok=True)
    config = json.loads((ROOT / ".dart_tool/package_config.json").read_text())
    # Resolve every untouched package against the original workspace config;
    # relocating package_config must not relocate relative package roots.
    from urllib.parse import urljoin
    config_uri = (ROOT / ".dart_tool/package_config.json").as_uri()
    for package in config["packages"]:
        package["rootUri"] = urljoin(config_uri, package["rootUri"])

    def run(config_path, *arguments):
        subprocess.run([
            str(ROOT / "scripts/run_with_test_cleanup.sh"), "--timeout", "20m", "--",
            str(dart), "--disable-dart-dev", f"--packages={config_path}",
            str(SERVER / "tool/lane_hold_benchmark.dart"), *map(str, arguments),
        ], cwd=SERVER, check=True)

    run(ROOT / ".dart_tool/package_config.json", "prepare")
    phases = {}
    for phase, source in (("before", before), ("after", after)):
        for package in config["packages"]:
            if package["name"] == "tentura_server":
                package["rootUri"] = source.as_uri() + "/"
        config_path = snapshots / f"{phase}-package-config.json"
        config_path.write_text(json.dumps(config))
        output = snapshots / f"{phase}.json"
        run(config_path, phase, source, output)
        phases[phase] = json.loads(output.read_text())
    if phases["before"]["database"] != phases["after"]["database"]:
        raise RuntimeError("Both phases must use the same perf database")
    if phases["before"]["beforeRevision"] == phases["after"]["afterRevision"]:
        raise RuntimeError("The source snapshots are identical")
    paths = phases["before"]["paths"]
    for path, updated in zip(paths, phases["after"]["paths"], strict=True):
        if (path["path"], path["rows"]) != (updated["path"], updated["rows"]):
            raise RuntimeError("Before/after workloads differ")
        path["after"] = updated["after"]
        if path["after"]["worstCaseLaneHoldMs"] >= path["before"]["worstCaseLaneHoldMs"]:
            raise RuntimeError(f"Worst lane hold did not improve: {path['path']}")
    report = {
        "environment": "perf", "metric": "db_lane_hold", "unit": "ms",
        "measurementBoundary": "transaction_begin_to_commit",
        "referenceMachine": f"{platform.node()} {platform.platform()}",
        "database": phases["after"]["database"],
        "beforeRevision": phases["before"]["beforeRevision"],
        "afterRevision": phases["after"]["afterRevision"],
        "revisionKind": "source_tree_sha1", "beforeBaseCommit": baseline,
        "sourceSnapshots": str(snapshots), "paths": paths,
    }
    destination = ROOT / REPORT_PATH
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + "\n")
    body = (f"Measured on perf DB `{report['database']['name']}`. "
            f"Samples: `{REPORT_PATH}`. Source SHA-1 before `{report['beforeRevision']}`, "
            f"after `{report['afterRevision']}` (frozen source trees, not new commits).\n\n"
            "| Path | Rows | Before worst lane hold (ms) | After worst lane hold (ms) |\n"
            "| --- | --- | --- | --- |\n")
    for path in paths:
        body += (f"| {path['path']} | {path['rows']} | "
                 f"{path['before']['worstCaseLaneHoldMs']} | "
                 f"{path['after']['worstCaseLaneHoldMs']} |\n")
    destination.with_name("lane-hold-transactions-pr.md").write_text(body)
    if args.pr_url:
        destination.with_name("lane-hold-transactions-pr.json").write_text(
            json.dumps({"html_url": args.pr_url, "body": body,
                        "status": "prepared_for_publishing"}, indent=2) + "\n")
    print(f"Retained source snapshots: {snapshots}")
    print(f"Measured report and PR table: {destination.parent}")


if __name__ == "__main__":
    main()
