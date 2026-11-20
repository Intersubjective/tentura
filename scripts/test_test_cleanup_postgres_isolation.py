"""The cleanup self-check keeps host databases outside its fixture sweep."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
CONTAINERS = ("postgres", "postgres-test")
DOCKER = """#!/usr/bin/env bash
set -eu
case "$1" in
  inspect) echo true ;;
  ps) printf '%s\\n' postgres postgres-test ;;
  exec)
    case "$2" in postgres|postgres-test) ;; *) exit 1 ;; esac
    [[ "$3" == psql ]] || exit 1
    printf '%s\\n' "$2" >> "$DOCKER_FIXTURE/psql.log"
    case "${*: -1}" in
      *pg_stat_activity*) cat "$DOCKER_FIXTURE/$2" ;;
      'DROP DATABASE IF EXISTS "tentura_test_stale_fixture"'*)
        : > "$DOCKER_FIXTURE/$2"
        ;;
    esac
    ;;
  *) exit 1 ;;
esac
"""


class CleanupPostgresIsolationTest(unittest.TestCase):
    def test_selfcheck_leaves_host_databases_intact_while_maintenance_can_drop_them(self):
        with tempfile.TemporaryDirectory(prefix="cleanup-postgres-") as scratch:
            root = Path(scratch)
            (root / "scripts").mkdir()
            for name in (
                "run_with_test_cleanup.sh",
                "run_with_test_cleanup_selftest.sh",
                "run_with_test_output_watchdog.py",
            ):
                shutil.copy2(SCRIPTS / name, root / "scripts" / name)

            for name in ("bin", "tmp", "system-tmp"):
                (root / name).mkdir()
            docker = root / "bin/docker"
            docker.write_text(DOCKER)
            docker.chmod(0o755)
            env = {
                "HOME": os.environ["HOME"],
                "PATH": f"{docker.parent}:{os.environ['PATH']}",
                "TMPDIR": str(root / "tmp"),
                "XDG_CACHE_HOME": str(root / "cache"),
                "TENTURA_TEST_CLEANUP_SYSTEM_TMP": str(root / "system-tmp"),
                "DOCKER_FIXTURE": str(root),
            }
            victim = "tentura_test_stale_fixture\n"
            for container in CONTAINERS:
                (root / container).write_text(victim)
            maintenance = subprocess.run(
                ["bash", "scripts/run_with_test_cleanup.sh", "--sweep-only"],
                cwd=root, env=env, text=True, capture_output=True, timeout=15,
            )
            self.assertEqual(maintenance.returncode, 0, maintenance.stderr)
            for container in CONTAINERS:
                self.assertIn(f"{container}: dropped 1 stale", maintenance.stderr)
                self.assertEqual((root / container).read_text(), "")
                (root / container).write_text(victim)

            calls = root / "psql.log"
            calls.write_text("")
            # Seed this after the maintenance control so only the canonical
            # self-check can demonstrate that the override survives re-exec.
            system_tmp_fixture = root / "system-tmp" / "dart_test.kernel.postgres-isolation"
            system_tmp_fixture.write_text("unreferenced kernel")
            selfcheck = subprocess.run(
                ["bash", "scripts/run_with_test_cleanup_selftest.sh"],
                cwd=root, env=env, text=True, capture_output=True, timeout=90,
            )
            transcript = selfcheck.stdout + selfcheck.stderr
            self.assertIn("PASS: unreferenced dart_test.kernel dir removed", transcript)
            self.assertIn("[selftest] done", transcript)
            self.assertFalse(
                system_tmp_fixture.exists(),
                f"Self-check left a fixture in the configured system tmp.\n{transcript}",
            )
            self.assertEqual(
                {container: (root / container).read_text() for container in CONTAINERS},
                dict.fromkeys(CONTAINERS, victim),
                transcript,
            )
            self.assertEqual(calls.read_text(), "", transcript)
            self.assertEqual(selfcheck.returncode, 0, transcript)


if __name__ == "__main__":
    unittest.main()
