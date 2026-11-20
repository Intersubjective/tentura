"""The cleanup self-test targets the session it launched."""

import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest


SELFTEST = Path(__file__).resolve().with_name("run_with_test_cleanup_selftest.sh")
WRAPPER = SELFTEST.with_name("run_with_test_cleanup.sh")

# Keep real process matching, but put the older peer first when it matches.
# Observe the first session signal at the Bash builtin boundary. Stop there
# so neither that signal nor the EXIT trap can kill a process selected by
# an unrestricted process-table search.
SHELL_PROBE = r"""
if [[ ${0##*/} == run_with_test_cleanup_selftest.sh ]]; then
  pgrep() {
    local matches pid
    matches=$(command pgrep "$@") || return
    if [[ $'\n'"$matches"$'\n' == *$'\n'"$SESSION_PROBE_PEER"$'\n'* ]]; then
      printf '%s\n' "$SESSION_PROBE_PEER"
    fi
    while read -r pid; do
      if [[ $pid != "$SESSION_PROBE_PEER" ]]; then printf '%s\n' "$pid"; fi
    done <<< "$matches"
  }

  kill() {
    local target="${@: -1}"
    if [[ $1 == -0 ]]; then
      builtin kill "$@"
      return
    fi
    if [[ $target =~ ^-[0-9]+$ ]]; then
      command pgrep -f 'run_with_test_cleanup.sh --timeout 60s' > "$SESSION_PROBE_MATCHES" || true
      printf '%s %s\n' "${target#-}" "$$" > "$SESSION_PROBE_SIGNAL"
      trap - EXIT
      exit 0
    fi
    if [[ $target =~ ^[1-9][0-9]*$ ]] &&
      grep -zFxq "SESSION_PROBE_TOKEN=$SESSION_PROBE_TOKEN" "/proc/$target/environ"; then
      builtin kill "$@"
    else
      return 1
    fi
  }
fi
"""

# Expose only fixture processes to the wrapper's Python sweep helpers. The
# self-test can exercise real orphan cleanup without sweeping host processes.
PROC_SCOPE = """
import os
from pathlib import Path

_iterdir = Path.iterdir
_tag = b'SESSION_PROBE_TOKEN=' + os.fsencode(os.environ['SESSION_PROBE_TOKEN'])

def fixture_iterdir(path):
    if path != Path('/proc'):
        yield from _iterdir(path)
        return
    for entry in _iterdir(path):
        if entry.name.isdecimal():
            try:
                if _tag in (entry / 'environ').read_bytes().split(b'\\0'):
                    yield entry
            except OSError:
                continue

Path.iterdir = fixture_iterdir
"""

# Reap the fixture's detached children even when the host's PID 1 does not
# reap zombies. The shell's liveness checks still use the real kill builtin.
REAP_DETACHED = """
import ctypes
import os
import subprocess
import sys

libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(36, 1, 0, 0, 0):  # PR_SET_CHILD_SUBREAPER
    raise OSError(ctypes.get_errno(), 'cannot adopt detached fixture processes')
child = subprocess.Popen(['bash', sys.argv[1]], start_new_session=True)
while True:
    pid, status = os.wait()
    if pid == child.pid:
        child.returncode = os.waitstatus_to_exitcode(status)
        sys.exit(child.returncode)
"""


def fixture_processes(token):
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            environment = (process / "environ").read_bytes().split(b"\0")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if f"SESSION_PROBE_TOKEN={token}".encode() in environment:
            yield process


class CleanupSelftestSessionTest(unittest.TestCase):
    def test_group_signal_targets_the_selftests_wrapper_among_matching_runs(self):
        with tempfile.TemporaryDirectory(prefix="cleanup-session-") as scratch:
            root = Path(scratch)
            tmpdir = root / "tentura-selftest.probe"
            tmpdir.mkdir()
            # The temporary script tree keeps build-cache sweeps away from the checkout.
            scripts = root / "scripts"
            scripts.mkdir()
            selftest = scripts / SELFTEST.name
            wrapper = scripts / WRAPPER.name
            shutil.copy2(SELFTEST, selftest)
            shutil.copy2(WRAPPER, wrapper)
            shutil.copy2(WRAPPER.with_name("run_with_test_output_watchdog.py"), scripts)
            probe = root / "probe.bash"
            probe.write_text(SHELL_PROBE)
            (root / "sitecustomize.py").write_text(PROC_SCOPE)
            target_file = root / "signal-target"
            matches_file = root / "matches"

            env = os.environ.copy()
            env.pop("TENTURA_TEST_CLEANUP_RUN", None)
            env.pop("TENTURA_TEST_LOCK_HELD", None)
            env.update(
                BASH_ENV=str(probe),
                PYTHONPATH=str(root),
                PYTHONDONTWRITEBYTECODE="1",
                SELFTEST_ISOLATED="1",
                SESSION_PROBE_TOKEN=scratch,
                SESSION_PROBE_SIGNAL=str(target_file),
                SESSION_PROBE_MATCHES=str(matches_file),
                TENTURA_TEST_CLEANUP_SYSTEM_TMP=str(tmpdir),
                TENTURA_TEST_LOCK="off",
                TMPDIR=str(tmpdir),
            )
            peer = subprocess.Popen(
                [
                    sys.executable, "-c", "import time; time.sleep(90)",
                    str(wrapper), "--timeout", "60s",
                ],
                env=env,
                start_new_session=True,
            )
            try:
                env["SESSION_PROBE_PEER"] = str(peer.pid)
                with (root / "output").open("w+") as output:
                    result = subprocess.run(
                        [sys.executable, "-c", REAP_DETACHED, str(selftest)], env=env, stdout=output,
                        stderr=subprocess.STDOUT, start_new_session=True, timeout=50,
                    )
                    output.seek(0)
                    diagnostics = output.read()
                self.assertEqual(result.returncode, 0, diagnostics)
                self.assertNotIn("[selftest] FAIL:", diagnostics)
                self.assertTrue(
                    target_file.is_file(), f"No session signal observed\n{diagnostics}"
                )
                target, selftest_group = map(int, target_file.read_text().split())
                matches = {int(pid) for pid in matches_file.read_text().split()}
                self.assertIn(peer.pid, matches, "The live peer did not match the wrapper search")
                wrapper_groups = {}
                for process in fixture_processes(scratch):
                    try:
                        argv = (process / "cmdline").read_bytes().split(b"\0")
                        if os.fsencode(wrapper) in argv[:2]:
                            pid = int(process.name)
                            group = os.getpgid(pid)
                            if group != selftest_group:
                                wrapper_groups[pid] = group
                    except (FileNotFoundError, ProcessLookupError):
                        continue
                self.assertTrue(
                    matches.intersection(wrapper_groups),
                    "The wrapper launched by the self-test did not match the wrapper search",
                )
                self.assertNotEqual(
                    target, peer.pid,
                    f"The self-test selected the unrelated wrapper's group {peer.pid}",
                )
                self.assertNotEqual(target, selftest_group, "The self-test selected its own group")
                self.assertIn(target, wrapper_groups.values())
            finally:
                for process in fixture_processes(scratch):
                    try:
                        os.kill(int(process.name), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                peer.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
