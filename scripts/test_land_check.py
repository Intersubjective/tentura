"""Operator-facing landing checks, exercised in disposable Git repositories.

The real entry point is copied with its script helpers. Only suite execution
and the repository-tag check are replaced, so these tests never run real gates.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROFILES = {"client-gates", "client-files", "server-gates", "server-unit", "server-files"}


class LandingChecksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tentura-land-check-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        shutil.copytree(ROOT / "scripts", self.repo / "scripts")
        self.log = Path(self.temp.name) / "calls.jsonl"
        self.env = {
            **os.environ,
            "LAND_CHECK_CALLS": str(self.log),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_AUTHOR_NAME": "Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
        }
        self.write("scripts/run_tests.sh", '''#!/usr/bin/env bash
exec python3 - "$@" <<'STUB'
import json, os, sys
with open(os.environ['LAND_CHECK_CALLS'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
sys.exit(17 if os.environ.get('LAND_CHECK_FAIL_PROFILE') in sys.argv[1:] else 0)
STUB
''')
        (self.repo / "scripts/run_tests.sh").chmod(0o755)
        self.write("scripts/check_repo_files_tags.py", '''import json, os
with open(os.environ['LAND_CHECK_CALLS'], 'a') as log:
    log.write(json.dumps(['repo-check']) + '\\n')
raise SystemExit(int(os.environ.get('LAND_CHECK_REPO_EXIT', '0')))
''')
        for package, name in (("client", "tentura"), ("server", "tentura_server")):
            self.write(f"packages/{package}/pubspec.yaml", f"name: {name}\n")
            self.write(f"packages/{package}/lib/value.dart", "const value = 1;\n")
            tags = "@Tags(['pg'])\nlibrary;\n" if package == "server" else ""
            self.write(
                f"packages/{package}/test/value_test.dart",
                tags + f"import 'package:{name}/value.dart';\nvoid main() {{}}\n",
            )
            self.write(f"packages/{package}/test/unrelated_test.dart", "void main() {}\n")
        self.write("packages/client/test/staged_test.dart", "void main() {}\n")
        self.git("init", "-q")
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.commit_fixture()
        self.base = self.git("rev-parse", "HEAD").strip()
        self.git("update-ref", "refs/remotes/origin/main", self.base)

    def write(self, path, contents):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents)

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.repo, env=self.env, text=True,
            capture_output=True, check=True,
        ).stdout

    def commit_fixture(self):
        # Commits belong only to this disposable fixture, never the checkout.
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture tree")

    def touch_package(self, package):
        self.write(f"packages/{package}/lib/value.dart", "const value = 2;\n")

    def invoke(self, *args, **env):
        entry = self.repo / "scripts/land_check.sh"
        self.assertTrue(
            entry.is_file(),
            "Missing landing-check behavior: scripts/land_check.sh must provide "
            "package selection, gate execution, and an operator summary",
        )
        return subprocess.run(
            ["bash", str(entry), *args], cwd=self.repo,
            env={**self.env, **env}, text=True, capture_output=True, timeout=20,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def dry_run(self, expected, *args):
        result = self.invoke("--dry-run", *args)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        found = set(re.findall(r"\b(?:client|server)-(?:gates|files|unit)\b", output))
        self.assertEqual(found, expected, output)
        self.assertRegex(output, r"python3\s+\S*scripts/check_repo_files_tags\.py")
        self.assertEqual(self.calls(), [], "Dry-run must not execute gates or repository checks")
        return output

    def test_client_range_prints_only_client_gates_and_affected_tests(self):
        self.touch_package("client")
        self.commit_fixture()
        output = self.dry_run({"client-gates", "client-files"}, self.base)
        self.assertIn("test/value_test.dart", output)
        self.assertNotIn("unrelated_test.dart", output)

    def test_server_range_prints_server_gates_unit_and_affected_pg_tests(self):
        self.touch_package("server")
        self.write(
            "packages/server/test/value_unit_test.dart",
            "import 'package:tentura_server/value.dart';\nvoid main() {}\n",
        )
        self.commit_fixture()
        output = self.dry_run({"server-gates", "server-unit", "server-files"}, self.base)
        self.assertIn("test/value_test.dart", output)
        self.assertNotIn("unrelated_test.dart", output)
        self.assertNotIn("value_unit_test.dart", output)

    def test_server_files_receives_only_changed_or_affected_pg_tests(self):
        # Seed an unchanged unit importer, then change its library and add
        # both PG and non-PG tests. Neither source of unit tests belongs in
        # server-files; server-unit already covers them.
        self.write(
            "packages/server/test/value_unit_test.dart",
            "import 'package:tentura_server/value.dart';\nvoid main() {}\n",
        )
        self.write(
            "packages/server/test/unrelated_pg_test.dart",
            "@Tags(['pg'])\nlibrary;\nvoid main() {}\n",
        )
        self.commit_fixture()
        base = self.git("rev-parse", "HEAD").strip()
        self.touch_package("server")
        self.write("packages/server/test/changed_unit_test.dart", "void main() {}\n")
        self.write(
            "packages/server/test/changed_pg_test.dart",
            "@Tags(['pg'])\nlibrary;\nvoid main() {}\n",
        )
        self.commit_fixture()
        result = self.invoke(base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertIn(["server-unit"], calls)
        selected = [call for call in calls if "server-files" in call]
        self.assertEqual(len(selected), 1, calls)
        self.assertEqual(
            set(selected[0]),
            {"server-files", "test/changed_pg_test.dart", "test/value_test.dart"},
            "Only changed PG tests and PG importers belong in server-files",
        )

    def assert_deleted_test_selects_gates_without_running_missing_file(self, package, committed):
        path = f"packages/{package}/test/value_test.dart"
        (self.repo / path).unlink()
        if committed:
            self.commit_fixture()
        result = self.invoke(self.base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertIn([f"{package}-gates"], calls)
        if package == "server":
            self.assertIn(["server-unit"], calls)
        other = "client" if package == "server" else "server"
        self.assertFalse(any(arg.startswith(f"{other}-") for call in calls for arg in call), calls)
        self.assertFalse(any(arg.endswith("test/value_test.dart") for call in calls for arg in call), calls)
        self.assertIn(["repo-check"], calls)

    def test_deleted_test_in_commit_range_selects_its_package_without_running_deleted_file(self):
        self.assert_deleted_test_selects_gates_without_running_missing_file("client", True)

    def test_deleted_test_in_working_tree_selects_its_package_without_running_deleted_file(self):
        self.assert_deleted_test_selects_gates_without_running_missing_file("server", False)

    def assert_renamed_test_runs_at_final_path(self, package, committed):
        source = f"packages/{package}/test/value_test.dart"
        target = f"packages/{package}/test/renamed_value_test.dart"
        if committed:
            self.git("mv", source, target)
            self.commit_fixture()
            self.assertIn("R100", self.git("diff", "--name-status", "-M", f"{self.base}..HEAD"))
        else:
            (self.repo / source).rename(self.repo / target)
        result = self.invoke(self.base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertIn([f"{package}-gates"], calls)
        selected = [call for call in calls if f"{package}-files" in call]
        self.assertEqual(len(selected), 1, calls)
        self.assertIn("test/renamed_value_test.dart", selected[0])
        self.assertNotIn("test/value_test.dart", selected[0])
        self.assertIn(["repo-check"], calls)

    def test_renamed_pg_test_in_commit_range_runs_at_its_final_path(self):
        self.assert_renamed_test_runs_at_final_path("server", True)

    def test_renamed_client_test_in_working_tree_runs_at_its_final_path(self):
        self.assert_renamed_test_runs_at_final_path("client", False)

    def test_range_touching_both_packages_prints_both_packages_steps(self):
        self.touch_package("client")
        self.touch_package("server")
        self.commit_fixture()
        self.dry_run(PROFILES, self.base)

    def test_docs_only_range_prints_only_repository_check(self):
        self.write("docs/landing.md", "Updated documentation\n")
        self.commit_fixture()
        self.dry_run(set(), self.base)

    def test_default_origin_main_base_includes_committed_client_changes(self):
        self.touch_package("client")
        self.commit_fixture()
        # Keep the remote-tracking base fixed while landing on local main.
        self.assertEqual(self.git("symbolic-ref", "--short", "HEAD").strip(), "main")
        self.assertEqual(self.git("rev-parse", "origin/main").strip(), self.base)
        self.assertNotEqual(self.git("rev-parse", "HEAD").strip(), self.base)
        self.assertEqual(self.git("diff", "--name-only", "main"), "")
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual(
            self.git("diff", "--name-only", "origin/main..HEAD").splitlines(),
            ["packages/client/lib/value.dart"],
        )
        output = self.dry_run({"client-gates", "client-files"})
        self.assertIn("test/value_test.dart", output)
        self.assertNotIn("unrelated_test.dart", output)

    def test_final_tree_selection_combines_range_staged_unstaged_and_untracked_changes(self):
        self.touch_package("client")
        self.commit_fixture()
        self.write("packages/server/test/changed_pg_test.dart", "@Tags(['pg'])\nlibrary;\nvoid main() {}\n")
        self.git("add", "packages/server/test/changed_pg_test.dart")
        self.write("packages/client/test/staged_test.dart", "void main() { /* updated */ }\n")
        self.git("add", "packages/client/test/staged_test.dart")
        self.assertIn(
            "packages/client/test/staged_test.dart",
            self.git("diff", "--cached", "--name-only", "--diff-filter=M").splitlines(),
        )
        self.touch_package("server")
        self.write("packages/client/test/new_test.dart", "void main() {}\n")
        output = self.dry_run(PROFILES, self.base)
        for path in ("test/value_test.dart", "test/changed_pg_test.dart", "test/new_test.dart", "test/staged_test.dart"):
            self.assertIn(path, output)
        self.assertNotIn("unrelated_test.dart", output)

    def test_staged_tracked_library_change_selects_package_and_importing_tests(self):
        self.touch_package("server")
        self.git("add", "packages/server/lib/value.dart")
        self.assertEqual(self.git("diff", "--name-only"), "")
        self.assertEqual(
            self.git("diff", "--cached", "--name-only", "--diff-filter=M").splitlines(),
            ["packages/server/lib/value.dart"],
        )
        output = self.dry_run({"server-gates", "server-unit", "server-files"}, self.base)
        self.assertIn("test/value_test.dart", output)
        self.assertNotIn("unrelated_test.dart", output)

    def test_changed_tests_and_importers_are_passed_to_separate_suite_invocations(self):
        self.touch_package("client")
        self.touch_package("server")
        self.write("packages/client/test/changed_test.dart", "void main() {}\n")
        self.write("packages/server/test/changed_pg_test.dart", "@Tags(['pg'])\nlibrary;\nvoid main() {}\n")
        self.commit_fixture()
        result = self.invoke(self.base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        for profile in PROFILES:
            matching = [call for call in calls if profile in call]
            self.assertEqual(len(matching), 1, calls)
            self.assertEqual(set(matching[0]) & PROFILES, {profile}, calls)
        for profile, changed in (("client-files", "test/changed_test.dart"), ("server-files", "test/changed_pg_test.dart")):
            call = next(call for call in calls if profile in call)
            self.assertIn("test/value_test.dart", call)
            self.assertIn(changed, call)
            self.assertFalse(any("unrelated_test.dart" in arg for arg in call), calls)
        self.assertEqual(calls.count(["repo-check"]), 1, calls)

    def test_failed_suite_still_runs_remaining_steps_and_reports_all_results(self):
        self.touch_package("client")
        self.touch_package("server")
        self.commit_fixture()
        result = self.invoke(self.base, LAND_CHECK_FAIL_PROFILE="server-gates")
        calls = self.calls()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        for profile in PROFILES:
            self.assertTrue(any(profile in call for call in calls), (profile, calls))
        self.assertIn(["repo-check"], calls)
        output = result.stdout + result.stderr
        self.assertRegex(output.lower(), r"summary")
        for profile in PROFILES:
            self.assertIn(profile, output)
        self.assertRegex(output.lower(), r"(?:fail|failed|17)")
        self.assertRegex(output.lower(), r"(?:pass|passed|success|ok)")

    def test_failed_repository_check_makes_docs_only_landing_fail_with_summary(self):
        self.write("docs/landing.md", "Updated documentation\n")
        self.commit_fixture()
        result = self.invoke(self.base, LAND_CHECK_REPO_EXIT="23")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [["repo-check"]])
        output = result.stdout + result.stderr
        self.assertRegex(output.lower(), r"summary")
        self.assertIn("check_repo_files_tags", output)
        self.assertRegex(output.lower(), r"(?:fail|failed|23)")


if __name__ == "__main__":
    unittest.main()
