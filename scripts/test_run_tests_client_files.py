"""Client profiles execute every selected test with its required input runner."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
NATIVE = "test/features/constellation/constellation_overlapping_dot_browser_touch_test.dart"
RUNNER = "test/support/browser/run_overlapping_dot_touch.mjs"
VM = "test/features/constellation/constellation_low_zoom_hit_target_test.dart"


class ClientRunnerRoutingTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="tentura-client-routing-")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name)
        (self.repo / "scripts").mkdir()
        (self.repo / "packages/client").mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/run_tests.sh", self.repo / "scripts/run_tests.sh")
        self.write("scripts/run_with_test_cleanup.sh", """#!/bin/bash
while [[ "$1" != -- ]]; do shift; done
shift
exec "$@"
""")
        for executable, variable in (("flutter", "VM_EXIT"), ("node", "BROWSER_EXIT")):
            self.write(f"bin/{executable}", f"""#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CALLS'], 'a') as stream:
    stream.write(json.dumps([{executable!r}, *sys.argv[1:]]) + '\\n')
raise SystemExit(int(os.environ.get({variable!r}, '0')))
""")
        # Simulate only the changed browser test; no disposable Git commits.
        self.write("bin/git", f"""#!/bin/sh
if [ "$1" = diff ]; then
  printf '%s\\n' 'packages/client/{NATIVE}'
fi
""")
        self.write(f"packages/client/{NATIVE}", "@TestOn('browser')\nlibrary;\n")
        self.calls_path = self.repo / "calls.jsonl"

    def write(self, path, contents):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents)
        target.chmod(0o755)

    def invoke(self, profile, *files, **environment):
        result = subprocess.run(
            ["bash", str(self.repo / "scripts/run_tests.sh"), profile, *files],
            cwd=self.repo,
            env={
                **os.environ,
                "PATH": f"{self.repo / 'bin'}:{os.environ['PATH']}",
                "CALLS": str(self.calls_path),
                **environment,
            },
            text=True, capture_output=True, timeout=15,
        )
        calls = [json.loads(line) for line in self.calls_path.read_text().splitlines()]
        return result, calls

    def test_affected_browser_test_executes_native_runner(self):
        result, calls = self.invoke("client-affected")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [["node", RUNNER]])

    def test_mixed_selection_executes_vm_and_native_tests(self):
        result, calls = self.invoke("client-files", VM, NATIVE)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2, calls)
        self.assertEqual(calls[0][0], "flutter")
        self.assertIn(VM, calls[0])
        self.assertNotIn(NATIVE, calls[0])
        self.assertEqual(calls[1], ["node", RUNNER])

    def test_vm_failure_does_not_omit_native_test_and_fails_profile(self):
        result, calls = self.invoke("client-files", VM, NATIVE, VM_EXIT="17")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call[0] for call in calls], ["flutter", "node"])

    def test_native_failure_fails_profile(self):
        result, calls = self.invoke("client-files", NATIVE, BROWSER_EXIT="23")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [["node", RUNNER]])

    def test_complete_client_profile_includes_native_test(self):
        result, calls = self.invoke("client-all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ["flutter", "node"])

    def test_directory_selection_includes_native_test(self):
        result, calls = self.invoke("client-files", "test/features/constellation")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ["flutter", "node"])


if __name__ == "__main__":
    unittest.main()
