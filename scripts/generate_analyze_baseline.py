#!/usr/bin/env python3
"""Refresh analyzer counts and exact diagnostic inventory in one invocation.

The existing gate validates completion, extracts unique diagnostics and enforces
the ratchet. Stage every key and both client formats before publishing either
file. On interruption, rerunning completes the same refresh without raising debt.
"""

import fcntl
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"


def run(command, *, cwd=ROOT, env=None):
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True,
                            text=True, timeout=600)
    if result.returncode:
        raise ValueError(result.stdout + result.stderr)
    return result.stdout


def refresh(debt_dir):
    baseline = debt_dir / "analyze-baseline.txt"
    inventory = debt_dir / "analyze-baseline-inventory.tsv"
    original = baseline.read_text()
    totals = {}
    for line in original.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 2 or not fields[1].isdigit() or fields[0] in totals:
            raise ValueError(f"invalid baseline row: {line}")
        totals[fields[0]] = int(fields[1])
    headers = inventory.read_text().splitlines(keepends=True)[:7]
    if len(headers) != 7 or not all(line.startswith("#") for line in headers):
        raise ValueError("inventory must start with its seven header lines")
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("TENTURA_ANALYZER_") and key != "TENTURA_CUSTOM_LINT_RULES"}
    env["TENTURA_ANALYZER_DEBT_DIR"] = str(debt_dir)
    rules = run(["bash", str(SCRIPTS / "check-custom-lints.sh"), "--print-rules"], env=env).strip()
    rows = {}
    with tempfile.TemporaryDirectory() as scratch:
        captured = Path(scratch) / "diagnostics"
        shared = Path(scratch) / "shared-output"

        def gate(package, scope="", shared_status=None):
            gate_env = dict(env, TENTURA_ANALYZER_CAPTURE=str(captured))
            if shared_status is not None:
                gate_env.update(TENTURA_ANALYZER_OUTPUT=str(shared),
                                TENTURA_ANALYZER_STATUS=str(shared_status),
                                TENTURA_CUSTOM_LINT_RULES=rules)
            command = ["bash", str(SCRIPTS / "check-analyze-baseline.sh"), package]
            if scope:
                command.append(scope)
            run(command, env=gate_env)
            return captured.read_text().splitlines()

        for key in totals:
            package, _, scope = key.partition(":")
            diagnostics = gate(package, scope)
            count = len(diagnostics)
            if package == "packages/client" and not scope:
                # The shared gate uses a plugin-loading Dart run. Pass that
                # output through the SAME baseline gate, including its custom
                # rule filtering and incomplete-analysis checks.
                result = subprocess.run(["dart", "analyze", "--no-fatal-warnings"],
                                        cwd=ROOT / package, env=env,
                                        capture_output=True, text=True, timeout=600)
                shared.write_text(result.stdout + result.stderr)
                status = result.returncode if result.returncode >= 0 else 128 - result.returncode
                shared_rows = gate(package, shared_status=status)
                if len(shared_rows) != count:
                    raise ValueError(f"{key}: standalone total {count} differs from "
                                     f"shared total {len(shared_rows)}")
                diagnostics += shared_rows
            rows[key] = sorted(set(diagnostics), key=lambda line: line.encode())
            totals[key] = count

    updated = re.sub(r"^(\S+)([ \t]+)(\d+)([ \t]*)$",
                     lambda match: f"{match[1]}{match[2]}{totals.get(match[1], match[3])}{match[4]}",
                     original, flags=re.MULTILINE)
    contents = "".join(headers) + "".join(
        f"{key}\t{line}\n" for key, diagnostics in rows.items() for line in diagnostics)
    # Same-filesystem temporary files make each replacement atomic. Publish
    # inventory first: a crash can leave an older, higher count, never an
    # inventory that omits debt accepted by a newly lowered count. A rerun
    # repairs an interrupted pair using fresh completed analyzer output.
    with tempfile.TemporaryDirectory(dir=debt_dir, prefix=".analyze-refresh-") as staging:
        staged_inventory = Path(staging) / inventory.name
        staged_baseline = Path(staging) / baseline.name
        staged_inventory.write_text(contents)
        staged_baseline.write_text(updated)
        os.replace(staged_inventory, inventory)
        os.replace(staged_baseline, baseline)
    for key, count in totals.items():
        print(f"{key} refreshed ({count})")


def main():
    # One publisher owns both files. Unlike locking a replaced baseline inode,
    # this stable lock also serializes a writer that starts during publication.
    debt_dir = Path(os.environ.get("TENTURA_ANALYZER_DEBT_DIR") or SCRIPTS).resolve()
    lock_dir = debt_dir
    if debt_dir == SCRIPTS:
        lock_dir = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tentura"
        lock_dir.mkdir(parents=True, exist_ok=True)
    with (lock_dir / "analyze-baseline-refresh.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        refresh(debt_dir)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(f"generate-analyze-baseline: {error}", file=sys.stderr)
        sys.exit(1)
