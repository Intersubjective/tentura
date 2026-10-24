#!/usr/bin/env bash
# A cleanup sweep must preserve the shell launching a wrapped tester, even
# when bash -c carries the tester's path in its command text.
# Does not start Flutter/Dart; only a short-lived executable stand-in.
set -euo pipefail
# Overlapping wrapped runs on purpose: stay outside the machine-wide test
# queue (run_with_test_cleanup_selftest.sh section 15 covers the queue).
export TENTURA_TEST_LOCK=off
unset TENTURA_TEST_LOCK_HELD

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"

# Python holds the launch command as data, so the regression cannot kill this
# test driver merely because its own argv contains the tester's name. Each
# launch gets a private TMPDIR and no outer wrapper tag, like the other cleanup
# self-tests, so peer detection cannot accidentally skip the offending sweep.
python3 - "$WRAP" <<'PY'
import os
import pathlib
import shlex
import signal
import subprocess
import sys
import tempfile
import time

wrapper = pathlib.Path(sys.argv[1])
passed = 0
failed = 0


def check(condition, description):
    global passed, failed
    if condition:
        passed += 1
        print(f"[selftest] PASS: {description}", flush=True)
    else:
        failed += 1
        print(f"[selftest] FAIL: {description}", flush=True)


for expected_status, behavior in (
    (0, "launching shell survives a successful wrapped tester"),
    (7, "launching shell preserves a wrapped tester's nonzero status"),
):
    with tempfile.TemporaryDirectory(prefix="tentura-launcher-selftest.") as tmp:
        scratch = pathlib.Path(tmp)
        tester = scratch / "bin" / "flutter_tester"
        tester.parent.mkdir()
        tester.write_text('#!/usr/bin/env bash\nprintf "started\\n" > "$1"\nexit "$2"\n')
        tester.chmod(0o755)
        started = scratch / "tester-started"
        completed = scratch / "launcher-completed"
        # The statements after the wrapper prevent bash's final-command exec
        # optimization: the launching shell stays alive during both sweeps.
        command = (
            f"{shlex.quote(str(wrapper))} --timeout 8s -- "
            f"{shlex.quote(str(tester))} {shlex.quote(str(started))} {expected_status}\n"
            "status=$?\n"
            f'printf "%s\\n" "$status" > {shlex.quote(str(completed))}\n'
            'exit "$status"\n'
        )
        env = os.environ.copy()
        env.pop("TENTURA_TEST_CLEANUP_RUN", None)
        env["TMPDIR"] = tmp
        launcher = subprocess.Popen(
            ["bash", "--noprofile", "--norc", "-c", command],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
        output = ""
        timed_out = False
        try:
            output, _ = launcher.communicate(timeout=25)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(launcher.pid, signal.SIGKILL)
            output, _ = launcher.communicate(timeout=10)
        finally:
            # Detached reapers can finish just after the shell. Keep their
            # scratch directory until they remove their own run markers.
            state = scratch / "tentura-test-cleanup"
            deadline = time.monotonic() + 5
            while state.exists() and any(state.iterdir()) and time.monotonic() < deadline:
                time.sleep(0.1)

        check(not timed_out, f"{behavior}: launch finishes within the time limit")
        check(
            "skipping orphan/tmpfs sweep" not in output,
            f"{behavior}: orphan sweep is exercised",
        )
        check(started.is_file(), f"{behavior}: tester reaches runtime")
        check(
            completed.is_file() and completed.read_text().strip() == str(expected_status),
            f"{behavior}: shell runs its completion statement",
        )
        check(
            launcher.returncode == expected_status,
            f"{behavior}: exit status is {expected_status}, got {launcher.returncode}",
        )
        if launcher.returncode != expected_status or timed_out:
            for line in output.splitlines():
                print(f"[selftest]   {line}", flush=True)

print(f"[selftest] passed={passed} failed={failed}", flush=True)
sys.exit(1 if failed else 0)
PY
