"""Check that the optional budding documentation suite travels with its docs."""

import ast
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SUITE = Path("docs/tests/test_post_bud_visibility.py")
MATRIX = Path("docs/beacon-visibility-matrix.md")
UNRELATED_DART = Path("packages/client/lib/app/sentry/sentry_benign_filter.dart")
PUBSPEC = Path("packages/client/pubspec.yaml")
ENV = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}


def git(root, *arguments):
    return subprocess.run(
        ["git", *arguments],
        cwd=root,
        env=ENV,
        check=True,
        capture_output=True,
        text=True,
        timeout=15,
    ).stdout.strip()


class BuddingDocumentationIndependenceTest(unittest.TestCase):
    def test_optional_suite_uses_the_published_visibility_rules(self):
        source = ROOT / SUITE
        if not source.is_file():
            return

        syntax = ast.parse(source.read_text(encoding="utf-8"))
        release_dependencies = {
            node.id
            for node in ast.walk(syntax)
            if isinstance(node, ast.Name) and node.id == "RELEASE_START"
        }
        release_dependencies.update(
            node.name
            for node in ast.walk(syntax)
            if isinstance(node, ast.FunctionDef)
            and node.name == "test_release_changes_only_documentation_and_the_client_patch_version"
        )
        release_dependencies.update(
            alias.name
            for node in ast.walk(syntax)
            if isinstance(node, (ast.Import, ast.ImportFrom))
            for alias in node.names
            if alias.name == "subprocess" or getattr(node, "module", None) == "subprocess"
        )
        release_dependencies.update(
            node.value
            for node in ast.walk(syntax)
            if isinstance(node, ast.Constant)
            and isinstance(node.value, str)
            and (
                node.value == "git"
                or re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", node.value)
                or node.value == "packages/client/pubspec.yaml"
                or "kDefaultMinClientVersion" in node.value
            )
        )
        self.assertFalse(
            release_dependencies,
            "Visibility documentation checks depend on release inputs: "
            f"{sorted(release_dependencies)}",
        )

        with tempfile.TemporaryDirectory() as directory:
            snapshot = Path(directory)
            for path in (
                source,
                ROOT / MATRIX,
                *(ROOT / "docs/adr").glob("0008-*.md"),
                *(ROOT / "docs/plans").glob("post-request-budding-*.md"),
            ):
                copy = snapshot / path.relative_to(ROOT)
                copy.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, copy)

            def run_suite():
                return subprocess.run(
                    [sys.executable, "-m", "unittest", str(SUITE)],
                    cwd=snapshot,
                    env=ENV,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )

            def expect_green():
                result = run_suite()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            with self.subTest("published docs without repository metadata"):
                expect_green()

            with self.subTest("untracked Dart source"):
                unrelated = snapshot / "packages/client/lib/zz_tmp.dart"
                unrelated.parent.mkdir(parents=True)
                unrelated.write_text("const unrelated = true;\n", encoding="utf-8")
                expect_green()
            unrelated.unlink()

            with self.subTest("unrelated Dart change already committed"):
                # Replay a real historical change. The isolated checkout only
                # needs the changed source file and the current documents.
                revision = git(ROOT, "log", "-1", "--format=%H", "--", str(UNRELATED_DART))
                self.assertTrue(revision, f"No tracked history for {UNRELATED_DART}")
                fixture = snapshot / "repository"
                git(
                    snapshot, "clone", "--quiet", "--shared", "--no-checkout",
                    str(ROOT), str(fixture),
                )
                shutil.move(fixture / ".git", snapshot / ".git")

                def restore_dart_at(ref):
                    git(snapshot, "reset", "--quiet", "--mixed", ref)
                    git(snapshot, "restore", "--worktree", "--", str(UNRELATED_DART))
                    self.assertEqual(
                        git(snapshot, "status", "--porcelain", "--", str(UNRELATED_DART)), ""
                    )
                    return (snapshot / UNRELATED_DART).read_bytes()

                before = restore_dart_at(f"{revision}^")
                expect_green()
                after = restore_dart_at(revision)
                self.assertNotEqual(after, before)
                expect_green()

            with self.subTest("client version bump"):
                pubspec = snapshot / PUBSPEC
                shutil.copyfile(ROOT / PUBSPEC, pubspec)
                bumped, changes = re.subn(
                    r"(?m)^(version: [0-9]+\.[0-9]+\.)([0-9]+)",
                    lambda match: f"{match[1]}{int(match[2]) + 1}",
                    pubspec.read_text(encoding="utf-8"),
                )
                self.assertEqual(changes, 1)
                pubspec.write_text(bumped, encoding="utf-8")
                expect_green()

            matrix = snapshot / MATRIX
            document = matrix.read_text(encoding="utf-8")
            no_denial_row, rows_removed = re.subn(
                r"(?m)^\| \*\*Post member\*\*[^\n]*"
                r"no independent access to the bud[^\n]*\| ❌ \|\n",
                "",
                document,
            )
            self.assertEqual(rows_removed, 1, "Expected one Post-only reader denial row")
            no_context_rows = "".join(
                line for line in document.splitlines(keepends=True)
                if not (line.lstrip().startswith("|") and "contextChild" in line)
            )
            mutations = {
                "matrix_gives_buds_the_normal_request_audience": (matrix, no_denial_row),
                "matrix_grants_context_through_request_parents_only": (matrix, no_context_rows),
                "adr_retires_post_parent_context_and_keeps_request_context": (
                    next(snapshot.glob("docs/adr/0008-*.md")), "",
                ),
                **{
                    rule: (snapshot / f"docs/plans/post-request-budding-{plan}.md", "")
                    for rule, plan in (
                        ("architecture_replaces_the_post_observer_rule", "architecture"),
                        ("implementation_plan_marks_observer_access_as_historical", "implementation-plan"),
                        ("design_marks_observer_access_as_historical", "design"),
                    )
                },
            }
            methods = {
                node.name for node in ast.walk(syntax)
                if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")
            }
            failed_rules = set()
            for rule, (path, mutated) in mutations.items():
                with self.subTest(rule):
                    original = path.read_text(encoding="utf-8")
                    self.assertNotEqual(original, mutated)
                    try:
                        path.write_text(mutated, encoding="utf-8")
                        result = run_suite()
                    finally:
                        path.write_text(original, encoding="utf-8")
                    output = result.stdout + result.stderr
                    failures = set(re.findall(r"(?m)^FAIL: (test_\w+) \(", output))
                    self.assertNotIn("ERROR:", output)
                    if f"test_{rule}" in methods:
                        self.assertIn(f"test_{rule}", failures, output)
                    elif rule == "matrix_gives_buds_the_normal_request_audience":
                        self.assertTrue(failures & methods, output)
                    failed_rules.update(failures)

            self.assertFalse(
                methods - failed_rules,
                "Removing documented rules must trigger every retained rule test",
            )
