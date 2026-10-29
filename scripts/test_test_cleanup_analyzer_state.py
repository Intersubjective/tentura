"""The test launcher supplies writable analyzer state without changing HOME."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


WRAPPER = Path(__file__).resolve().with_name("run_with_test_cleanup.sh")
CHILD = """
import json, os
from pathlib import Path
location = os.environ.get('ANALYZER_STATE_LOCATION_OVERRIDE')
if location is not None:
    state = Path(location)
    state.mkdir(parents=True, exist_ok=True)
    (state / 'plugin-state').write_text('initialized')
print(json.dumps({'location': location}))
"""


class AnalyzerStateEnvironmentTest(unittest.TestCase):
    def run_child(self, root, override=None):
        env = os.environ.copy()
        env.pop("ANALYZER_STATE_LOCATION_OVERRIDE", None)
        env.pop("TENTURA_TEST_CLEANUP_RUN", None)
        env["XDG_CACHE_HOME"] = str(root / "cache")
        env["TMPDIR"] = str(root / "tmp")
        env["TENTURA_TEST_CLEANUP_SYSTEM_TMP"] = env["TMPDIR"]
        (root / "tmp").mkdir()
        if override is not None:
            env["ANALYZER_STATE_LOCATION_OVERRIDE"] = str(override)
        result = subprocess.run(
            [str(WRAPPER), "--timeout", "10s", "--",
             sys.executable, "-c", CHILD],
            env=env, capture_output=True, text=True, timeout=25,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_default_analyzer_state_can_be_written_in_the_configured_cache(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            snapshot = self.run_child(root)
            state = root / "cache" / "tentura" / "analyzer"
            self.assertEqual(snapshot["location"], str(state))
            self.assertEqual((state / "plugin-state").read_text(), "initialized")

    def test_explicit_analyzer_state_location_is_preserved(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            state = root / "explicit-analyzer-state"
            snapshot = self.run_child(root, override=state)
            self.assertEqual(snapshot["location"], str(state))
            self.assertEqual((state / "plugin-state").read_text(), "initialized")
            self.assertFalse((root / "cache" / "tentura" / "analyzer").exists())


if __name__ == "__main__":
    unittest.main()
