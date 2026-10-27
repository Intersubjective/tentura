"""Behavioral checks for the test launcher's inactivity deadline.

Run from the repository root with:
    python3 -m unittest discover -s scripts -p test_test_cleanup_inactivity.py -v

Each test includes an enabled-watchdog case, so the positive controls cannot
hide a missing watchdog. Only real subprocesses and the public CLI are used.
"""

import fcntl
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest


WRAPPER = Path(__file__).resolve().with_name("run_with_test_cleanup.sh")


class TestCleanupInactivityTest(unittest.TestCase):
    def run_wrapper(self, source, *, inactivity=None, flags=(),
                    timeout="20s", extra_env=None, prepare=None):
        # Match the shell selftests: private tmp/state and no inherited run tag.
        # The lock remains enabled; an outer wrapped invocation can own it.
        with tempfile.TemporaryDirectory(prefix="inactivity-selftest-") as scratch:
            env = os.environ.copy()
            env.pop("TENTURA_TEST_CLEANUP_RUN", None)
            env["TMPDIR"] = scratch
            env["TENTURA_TEST_CLEANUP_SYSTEM_TMP"] = scratch
            env.pop("TEST_INACTIVITY_TIMEOUT", None)
            if inactivity is not None:
                env["TEST_INACTIVITY_TIMEOUT"] = inactivity
            if extra_env is not None:
                env.update(extra_env)
            if prepare is not None:
                prepare(Path(scratch))
            events = queue.Queue()
            process = subprocess.Popen(
                [str(WRAPPER), "--timeout", timeout, *flags, "--",
                 sys.executable, "-u", "-c", source],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )

            def read_stream(name, pipe):
                try:
                    for line in iter(pipe.readline, b""):
                        events.put((name, time.monotonic(), line))
                finally:
                    pipe.close()

            readers = [
                threading.Thread(target=read_stream, args=(name, pipe), daemon=True)
                for name, pipe in (("stdout", process.stdout),
                                   ("stderr", process.stderr))
            ]
            for reader in readers:
                reader.start()
            try:
                rc = process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                # TERM lets the wrapper's normal tagged-tree cleanup run.
                process.terminate()
                try:
                    process.wait(timeout=25)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
                self.fail(f"wrapper failed to respect even its {timeout} overall timeout")
            finally:
                for reader in readers:
                    reader.join(timeout=5)
            captured = []
            while not events.empty():
                captured.append(events.get_nowait())
            stdout = b"".join(line for stream, _, line in captured
                              if stream == "stdout")
            stderr = b"".join(line for stream, _, line in captured
                              if stream == "stderr")
            return rc, stdout, stderr, captured

    def assert_hang(self, result, last_line):
        rc, stdout, stderr, events = result
        transcript = (stdout + stderr).decode(errors="replace")
        self.assertEqual(rc, 125, f"expected inactivity exit 125; output:\n{transcript}")
        diagnostics = [
            (at, line) for stream, at, line in events
            if b"test-cleanup: no test output for " in line
        ]
        self.assertEqual(len(diagnostics), 1, transcript)
        at, line = diagnostics[0]
        self.assertEqual(
            line.rstrip(b"\r\n"),
            b"test-cleanup: no test output for 3s -- treating as a hang; last line: "
            + last_line,
        )
        output_at = next(at for stream, at, line in events
                         if line.rstrip(b"\r\n") == last_line)
        # Time from observed output to hang diagnostic excludes queue/startup
        # and the existing post-run sweep, while detecting buffered output.
        self.assertGreaterEqual(at - output_at, 2.8)
        self.assertLessEqual(at - output_at, 6.0)
        self.assertNotIn(b"finished sleeping", stdout)

    def test_cli_deadline_stops_a_silent_command_and_reports_last_line(self):
        result = self.run_wrapper(
            "import time; print('waiting for data'); time.sleep(8); "
            "print('finished sleeping')",
            flags=("--inactivity", "3s"),
        )
        self.assert_hang(result, b"waiting for data")
        self.assertEqual(result[1], b"waiting for data\n")

    def test_cli_deadline_overrides_disabled_environment_and_kills_descendants(self):
        # Keep the child alive well past the watchdog. The parent reaps it
        # on group TERM so successful cleanup leaves no zombie behind.
        result = self.run_wrapper(
            "import signal, subprocess, sys, time\n"
            "child = subprocess.Popen([sys.executable, '-c', "
            "'import time; time.sleep(120)'])\n"
            "def stop(signum, frame):\n"
            "    child.wait(timeout=2)\n"
            "    sys.exit(0)\n"
            "signal.signal(signal.SIGTERM, stop)\n"
            "print('child pid: ' + str(child.pid))\n"
            "time.sleep(8)\n"
            "child.terminate(); child.wait()\n"
            "print('finished sleeping')\n",
            inactivity="0", flags=("--inactivity", "3s"),
        )
        rc, stdout, stderr, _ = result
        self.assertEqual(rc, 125, (stdout + stderr).decode(errors="replace"))
        last_line = stdout.rstrip(b"\n")
        child_pid = int(last_line.removeprefix(b"child pid: "))
        try:
            self.assert_hang(result, last_line)
            # kill(pid, 0) works without /proc and still sees zombies. Give
            # the parent a short interval to reap; require actual disappearance.
            deadline = time.monotonic() + 2
            while True:
                try:
                    os.kill(child_pid, 0)
                except ProcessLookupError:
                    break
                if time.monotonic() >= deadline:
                    self.fail("watchdog left the child alive or unreaped")
                time.sleep(0.05)
        finally:
            # Do not leave the intentionally long-lived child after a failure.
            try:
                os.kill(child_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    def test_periodic_output_streams_unchanged_and_restarts_the_silence_deadline(self):
        periodic = (
            "import sys, time\n"
            "for i in range(5):\n"
            "    print('tick ' + str(i), flush=True)\n"
            "    print('error tick ' + str(i), file=sys.stderr, flush=True)\n"
            "    time.sleep(1)\n"
        )
        expected = b"".join(f"tick {i}\n".encode() for i in range(5))
        normal = self.run_wrapper(periodic, flags=("--inactivity", "3s"))
        self.assertEqual(normal[0], 0, normal[2])
        self.assertEqual(normal[1], expected)
        self.assertNotIn(b"treating as a hang", normal[2])
        for i in range(5):
            self.assertIn(f"error tick {i}\n".encode(), normal[2])
        ticks = [at for stream, at, line in normal[3]
                 if stream == "stdout" and line.startswith(b"tick ")]
        self.assertEqual(len(ticks), 5)
        self.assertGreater(ticks[-1] - ticks[0], 3.5,
                           "output was buffered until command exit")

        stopped = self.run_wrapper(
            periodic + "print('waiting again'); time.sleep(8); "
            "print('finished sleeping')\n",
            flags=("--inactivity", "3s"),
        )
        self.assert_hang(stopped, b"waiting again")
        self.assertEqual(stopped[1], expected + b"waiting again\n")

    def test_inactivity_deadline_preserves_overall_timeout_sweep_and_lock(self):
        # The overall deadline must still win when it is shorter than the
        # inactivity deadline, keeping GNU timeout's existing exit status.
        timed_out = self.run_wrapper(
            "import time; print('started'); time.sleep(8); print('completed')",
            inactivity="3s", timeout="1s",
        )
        self.assertEqual(timed_out[0], 124, timed_out[2])
        self.assertEqual(timed_out[1], b"started\n")
        self.assertNotIn(b"treating as a hang", timed_out[2])

        def stale_files(tmp):
            # Unique names must not appear in a live launcher argv: the
            # sweep intentionally preserves every referenced basename.
            with tempfile.NamedTemporaryFile(
                prefix="dart_test.kernel.", dir=tmp, delete=False
            ) as fixture:
                fixture.write(b"unused kernel")
                kernel = Path(fixture.name)
            tools = Path(tempfile.mkdtemp(prefix="flutter_tools.", dir=tmp))
            (tools / "unused").write_text("unused tools")
            self.assertTrue(kernel.is_file())
            self.assertTrue((tools / "unused").is_file())

        swept = self.run_wrapper(
            "import os, pathlib; tmp = pathlib.Path(os.environ['TMPDIR']); "
            "print('kernels:', len(list(tmp.glob('dart_test.kernel.*')))); "
            "print('tools:', len(list(tmp.glob('flutter_tools.*'))))",
            inactivity="3s", prepare=stale_files,
        )
        self.assertEqual(swept[0], 0, swept[2])
        self.assertEqual(swept[1], b"kernels: 0\ntools: 0\n")

        # Use a private real flock, so neither an inherited outer-wrapper
        # lock nor a user's queue settings can make this check vacuous.
        with tempfile.TemporaryDirectory(prefix="inactivity-lock-selftest-") as tmp:
            lock = Path(tmp) / "tests.lock"
            lock_env = {"TENTURA_TEST_LOCK": str(lock),
                        "TENTURA_TEST_LOCK_HELD": ""}
            with lock.open("a") as holder:
                fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
                blocked = self.run_wrapper(
                    "print('command ran')", inactivity="3s",
                    flags=("--lock-wait", "0s"), extra_env=lock_env,
                )
                self.assertEqual(blocked[0], 75, blocked[2])
                self.assertEqual(blocked[1], b"", "command bypassed the held lock")
                self.assertIn(b"queued behind another test run", blocked[2])
                self.assertIn(b"gave up waiting for the test lock", blocked[2])
            released = self.run_wrapper(
                "print('command ran')", inactivity="3s",
                flags=("--lock-wait", "0s"), extra_env=lock_env,
            )
            self.assertEqual(released[0], 0, released[2])
            self.assertEqual(released[1], b"command ran\n")

        # Positive compatibility checks above must accompany a working
        # inactivity deadline, rather than letting the old wrapper pass.
        silent = self.run_wrapper(
            "import time; print('waiting for data'); time.sleep(8); "
            "print('finished sleeping')", inactivity="3s",
        )
        self.assert_hang(silent, b"waiting for data")

    def test_zero_environment_timeout_allows_silence_that_enabled_watchdog_rejects(self):
        command = (
            "import time; print('waiting for data'); time.sleep(8); "
            "print('finished sleeping')"
        )
        disabled = self.run_wrapper(command, inactivity="0")
        self.assertEqual(disabled[0], 0, disabled[2])
        self.assertEqual(disabled[1], b"waiting for data\nfinished sleeping\n")
        self.assertNotIn(b"treating as a hang", disabled[2])
        enabled = self.run_wrapper(command, inactivity="3s")
        self.assert_hang(enabled, b"waiting for data")
        self.assertEqual(enabled[1], b"waiting for data\n")


if __name__ == "__main__":
    unittest.main()
