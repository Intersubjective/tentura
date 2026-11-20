import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import check_client_test_parity as parity


class ClientTestParityTest(unittest.TestCase):
    def test_explicit_baseline_compares_committed_changes_using_json_events(self):
        paths = [Path("test/first_test.dart"), Path("test/second_test.dart")]

        def run_report(tree, report, selected):
            self.assertEqual(selected, paths)
            events = []
            for index, path in enumerate(paths):
                suite_path = path if tree == root else tree / parity.CLIENT / path
                events.append({"type": "suite", "suite": {"id": index, "path": str(suite_path)}})
                events.append({
                    "type": "testStart",
                    "test": {"id": index, "suiteID": index, "name": "example",
                             "metadata": {"skip": bool(index)}},
                })
            for index in reversed(range(len(paths))):
                events.append({"type": "testDone", "testID": index, "hidden": False,
                               "result": "success", "skipped": bool(index)})
            report.write_text("".join(json.dumps(event) + "\n" for event in events))

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root).decode().strip()

            git("init", "--quiet")
            git("config", "user.name", "Parity Test")
            git("config", "user.email", "parity@example.invalid")
            for content in ("before", "after"):
                for path in paths:
                    file = root / parity.CLIENT / path
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_text(content)
                git("add", ".")
                git("commit", "--quiet", "-m", content)
            baseline = git("rev-parse", "HEAD^")
            output = io.StringIO()
            with (
                patch.object(parity, "ROOT", root),
                patch.object(parity, "prepare_baseline") as prepare,
                patch.object(parity, "run_report", side_effect=run_report) as run,
                patch.object(sys, "argv", ["check_client_test_parity.py", "--baseline", baseline]),
                contextlib.redirect_stdout(output),
            ):
                parity.main()
            self.assertEqual(prepare.call_args.args[0], baseline)
            self.assertEqual(run.call_count, 2)
            self.assertIn("2 names and skip statuses match across 2 files.", output.getvalue())


if __name__ == "__main__":
    unittest.main()
