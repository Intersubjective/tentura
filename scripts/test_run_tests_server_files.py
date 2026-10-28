import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NORMAL = "test/domain/people_tags_exception_codes_test.dart"
MR = "test/trust_untrust_graph_readers_pg_test.dart"
ISOLATED = "test/data/database/main_db_scope_admission_pg_test.dart"


def dry_run(*files):
    out = subprocess.run(
        ["bash", str(ROOT / "scripts/run_tests.sh"), "--dry-run", "server-files", *files],
        capture_output=True, text=True, check=True, cwd=ROOT,
    ).stderr
    return [l for l in out.splitlines() if "dart test" in l]


class ServerFilesDryRunTest(unittest.TestCase):
    def test_groups_run_separately(self):
        normal2 = "test/domain/util/attachment_filename_test.dart"
        cmds = dry_run(NORMAL, MR, ISOLATED, normal2)
        self.assertEqual(len(cmds), 3, cmds)
        shared, mr, iso = cmds
        self.assertIn(NORMAL, shared)
        self.assertNotIn(MR, shared)
        self.assertNotIn(ISOLATED, shared)
        self.assertIn("-j 1 " + MR, mr)
        self.assertIn("-j 1 " + ISOLATED, iso)
        self.assertNotIn(NORMAL, iso)

    def test_each_isolated_file_alone(self):
        other = "test/data/database/main_db_scope_admission_pg_test.dart"
        cmds = dry_run(ISOLATED, NORMAL)
        self.assertEqual(len(cmds), 2, cmds)
        self.assertTrue(cmds[1].split(" (timeout")[0].endswith("-j 1 " + other))


if __name__ == "__main__":
    unittest.main()
