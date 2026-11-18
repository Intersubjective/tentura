"""Analyzer debt can be refreshed atomically without increasing its ratchet.

Run with python3 scripts/test_analyze_baseline_generation.py. Tool fixtures
exercise the public shell gates, not a replacement parser. The inventory drift
test also works without Dart or Flutter and checks the actual checkout.
"""

import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
CLIENT = "packages/client"
SERVER = "packages/server"
SCOPED = CLIENT + ":lib/features/beacon_view"
KEYS = (CLIENT, SERVER, SCOPED)
BASELINE = "analyze-baseline.txt"
INVENTORY = "analyze-baseline-inventory.tsv"
HEADERS = "\n".join((SCRIPTS / INVENTORY).read_text().splitlines()[:7]) + "\n"
DIAGNOSTIC = re.compile(r"^\s*(?:error|warning|info) (?:•|-) ")


def read_baselines(path):
    return dict((key, int(count)) for key, count in
                (line.split() for line in path.read_text().splitlines()
                 if line.strip() and not line.startswith("#")))


def documented_refresh_command(test, output, root):
    """Follow the gate's operator guidance without guessing a script name."""
    test.assertIn("improved", output, output[-2000:])
    guidance = output.split("improved", 1)[1]
    # Backticks preserve optional CLI arguments; plain prose also supports a
    # bare script path, optionally preceded by its interpreter.
    quoted = re.findall(r"`([^`]+)`", guidance)
    for text, is_command in ([(part, True) for part in quoted]
                             + [(line, False) for line in guidance.splitlines()]):
        try:
            tokens = shlex.split(text.replace("`", ""))
        except ValueError:
            # Prose may contain an unmatched apostrophe; a separately quoted
            # command above remains parseable without treating prose as shell.
            continue
        for index, token in enumerate(tokens):
            token = token.rstrip(".,;")
            path = Path(token)
            if not path.is_absolute():
                path = root / path
            if not path.resolve().is_relative_to((root / "scripts").resolve()) or not path.is_file():
                continue
            if is_command and tokens and shutil.which(tokens[0]):
                return tokens
            launchers = [start for start in range(index)
                         if shutil.which(tokens[start])]
            if launchers:
                command = tokens[launchers[-1]:index] + [token]
            elif os.access(path, os.X_OK):
                command = [token]
            else:
                continue
            if is_command:
                command.extend(tokens[index + 1:])
            return command
    test.fail("The improvement message must name a runnable generator command "
              "under scripts/ that refreshes both debt files:\n" + guidance)


class InventoryDriftTest(unittest.TestCase):
    def test_inventory_counted_rows_equal_each_checked_in_baseline(self):
        baselines = read_baselines(SCRIPTS / BASELINE)
        lines = (SCRIPTS / INVENTORY).read_text().splitlines()
        self.assertEqual(len(lines[:7]), 7)
        self.assertTrue(all(line.startswith("#") for line in lines[:7]))
        rows = {key: [] for key in baselines}
        for line in lines[7:]:
            self.assertIn("\t", line, "Inventory rows must be key<TAB>diagnostic")
            key, diagnostic = line.split("\t", 1)
            self.assertIn(key, rows)
            self.assertRegex(diagnostic, DIAGNOSTIC)
            if key == SERVER:
                self.assertRegex(diagnostic, r"^\s*(?:error|warning|info) - ",
                                 "Every server row must use dart analyze format")
            rows[key].append(diagnostic)
        for key, expected in baselines.items():
            with self.subTest(key=key):
                self.assertEqual(rows[key], sorted(set(rows[key]), key=lambda s: s.encode()),
                                 "Rows must be unique and sorted with LC_ALL=C")
                separator = "•" if key.startswith(CLIENT) else "-"
                counted = re.compile(r"^\s*(?:error|warning|info) " + separator + " ")
                count = sum(bool(counted.match(line)) for line in rows[key])
                self.assertEqual(count, expected,
                                 f"{key}: inventory has {count} counted rows; baseline is {expected}")
                shared_count = sum(bool(re.match(r"^\s*(?:error|warning|info) - ", line))
                                   for line in rows[key])
                if key == CLIENT:
                    self.assertEqual(shared_count, expected,
                                     "Client shared dart diagnostics must also be inventoried")
                elif key.startswith(CLIENT + ":"):
                    self.assertEqual(shared_count, 0, "Scoped rows come from flutter analyze")

    def test_drift_guard_rejects_server_baseline_mutations_without_sdk(self):
        with tempfile.TemporaryDirectory() as scratch:
            scripts = Path(scratch) / "scripts"
            scripts.mkdir()
            for name in (Path(__file__).name, INVENTORY):
                shutil.copy2(SCRIPTS / name, scripts / name)
            # Start with matching totals even when the actual checkout has
            # drift. This specifies the mutation independently of generation.
            counts = dict.fromkeys(read_baselines(SCRIPTS / BASELINE), 0)
            for line in (scripts / INVENTORY).read_text().splitlines()[7:]:
                key, diagnostic = line.split("\t", 1)
                separator = "•" if key.startswith(CLIENT) else "-"
                counts[key] += bool(re.match(r"^\s*(?:error|warning|info) " + separator + " ", diagnostic))
            baseline = scripts / BASELINE
            matching = "".join(f"{key} {count}\n" for key, count in counts.items())
            baseline.write_text(matching)
            command = [sys.executable, str(scripts / Path(__file__).name),
                       "InventoryDriftTest.test_inventory_counted_rows_equal_each_checked_in_baseline"]
            env = dict(os.environ, PATH="")  # Neither SDK is reachable.
            passed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
            baseline.write_text(matching.replace(f"{SERVER} {counts[SERVER]}",
                                                 f"{SERVER} {counts[SERVER] + 1}"))
            failed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(failed.returncode, 0, "Changing only the server count must fail the guard")
            self.assertIn(f"{SERVER}: inventory has {counts[SERVER]} counted rows; "
                          f"baseline is {counts[SERVER] + 1}", failed.stdout + failed.stderr)


class AnalyzerBaselineGenerationTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        # Copy scripts so the eventual generator can use production helpers.
        shutil.copytree(SCRIPTS, self.root / "scripts", ignore=shutil.ignore_patterns(
            "__pycache__", "node_modules"))
        self.scripts = self.root / "scripts"
        self.initial_baseline = "# Ratcheting issue counts (may only go down).\n" + "".join(
            f"{key} 3\n" for key in KEYS)
        (self.scripts / BASELINE).write_text(self.initial_baseline)
        (self.scripts / INVENTORY).write_text(
            HEADERS + SERVER + "\t   info - lib/stale.dart:1:1 - Old debt. - avoid_print\n")
        (self.scripts / "custom-lint-baseline.txt").write_text(
            f"{CLIENT} 99\n{SERVER} 99\n")
        for package in (CLIENT, SERVER):
            for relative in ("lib/ui/l10n/l10n.dart", "lib/app/router/root_router.gr.dart",
                             "lib/domain/entity/jwt_entity.freezed.dart",
                             "lib/data/database/tentura_db.g.dart"):
                path = self.root / package / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
        self.dart_rows = [
            "warning - lib/z.dart:3:8 - Unused import. - unused_import",
            "   info - lib/a.dart:2:3 - Use const. - prefer_const_constructors",
        ]
        self.flutter_rows = [
            "   " + " • ".join((severity, message, location, code))
            for severity, location, message, code in
            (line.strip().split(" - ", 3) for line in self.dart_rows)
        ]
        self.custom = "   info - lib/custom.dart:1:1 - Use a token. - no_raw_edge_insets"
        self.scope_rows = ["   warning • Unused scoped import. • "
                           "lib/features/beacon_view/scoped.dart:4:8 • unused_import"]
        self.outputs = self.root / "outputs"
        self.outputs.mkdir()
        self.write_output("server", self.dart_rows)
        self.write_output("client-flutter", self.flutter_rows)
        self.write_output("client-dart", self.dart_rows + [self.custom])
        self.write_output("scoped", self.scope_rows)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for tool in ("dart", "flutter"):
            executable = bin_dir / tool
            executable.write_text(
                '#!/usr/bin/env python3\n'
                'import os, pathlib, sys\n'
                'assert sys.argv[1] == "analyze", sys.argv\n'
                'tool = pathlib.Path(sys.argv[0]).name\n'
                'key = "server" if pathlib.Path.cwd().name == "server" else "client-" + tool\n'
                'if "lib/features/beacon_view" in sys.argv: key = "scoped"\n'
                'root = pathlib.Path(os.environ["GENERATION_TEST_OUTPUTS"])\n'
                'sys.stdout.write((root / (key + ".txt")).read_text())\n'
                'status = int((root / (key + ".status")).read_text())\n'
                'if "--no-fatal-warnings" in sys.argv and status <= 3: status = 0\n'
                'sys.exit(status)\n')
            executable.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("TENTURA_ANALYZER_")
                    and key != "TENTURA_CUSTOM_LINT_RULES"}
        self.env.update(PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                        GENERATION_TEST_OUTPUTS=str(self.outputs), LC_ALL="C",
                        TMPDIR=str(self.root / "tmp"),
                        XDG_CACHE_HOME=str(self.root / "cache"))
        (self.root / "tmp").mkdir()
        # Obtain the documented command while the fixture analyzer is healthy,
        # before individual tests inject crashes or a regressed baseline.
        self.refresh_hint = self.run_command([
            "bash", str(self.scripts / "check-analyze-baseline.sh"), SERVER])

    def write_output(self, name, rows, status=2, suffix=None):
        # Deliberately duplicate diagnostics: the gate counts unique lines.
        text = "Analyzing project...\n" + "\n".join(rows + rows[:1]) + "\n"
        text += suffix if suffix is not None else (
            f"{len(rows)} issues found.\n" if rows else "No issues found!\n")
        (self.outputs / (name + ".txt")).write_text(text)
        (self.outputs / (name + ".status")).write_text(str(status))

    def run_command(self, command):
        return subprocess.run(command, cwd=self.root, env=self.env,
                              capture_output=True, text=True, timeout=30)

    def generator_command(self):
        output = self.refresh_hint.stdout + self.refresh_hint.stderr
        self.assertEqual(self.refresh_hint.returncode, 0, output)
        return documented_refresh_command(self, output, self.root)

    def generate(self):
        return self.run_command(self.generator_command())

    def snapshot(self):
        return tuple((self.scripts / name).read_bytes() for name in (BASELINE, INVENTORY))

    def assert_generated(self, expected):
        self.assertEqual((self.scripts / BASELINE).read_text(),
                         self.initial_baseline.splitlines()[0] + "\n" +
                         "".join(f"{key} {expected[key]}\n" for key in KEYS))
        text = (self.scripts / INVENTORY).read_text()
        self.assertTrue(text.startswith(HEADERS), "Preserve the seven inventory header lines")
        actual = {key: [] for key in KEYS}
        for line in text.splitlines()[7:]:
            key, diagnostic = line.split("\t", 1)
            self.assertIn(key, actual)
            actual[key].append(diagnostic)
        wanted = {CLIENT: self.flutter_rows + self.dart_rows,
                  SERVER: self.dart_rows, SCOPED: self.scope_rows}
        for key in KEYS:
            self.assertEqual(actual[key], sorted(set(wanted[key]), key=lambda s: s.encode()))
        return actual

    def test_one_refresh_replaces_stale_rows_and_lowers_all_baselines(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_generated({CLIENT: 2, SERVER: 2, SCOPED: 1})
        for package, scope, shared in ((SERVER, None, False), (CLIENT, None, False),
                                       (CLIENT, None, True),
                                       (CLIENT, "lib/features/beacon_view", False)):
            with self.subTest(package=package, scope=scope, shared=shared):
                command = ["bash", str(self.scripts / (
                    "check-analysis.sh" if shared else "check-analyze-baseline.sh")), package]
                if scope:
                    command.append(scope)
                gate = self.run_command(command)
                output = gate.stdout + gate.stderr
                key = package + (":" + scope if scope else "")
                total = 1 if scope else 2
                self.assertEqual(gate.returncode, 0, output)
                self.assertIn(f"{key} OK ({total} <= {total})", output)
                self.assertNotIn("improved", output)
                baseline = self.scripts / BASELINE
                saved = baseline.read_text()
                baseline.write_text(re.sub(rf"^{re.escape(key)} \d+$", key + " 0",
                                           saved, flags=re.MULTILINE))
                try:
                    failed = self.run_command(command)
                    report = failed.stdout + failed.stderr
                    self.assertEqual(failed.returncode, 1, report)
                    marker = f"{key} has {total} issues, baseline is 0."
                    self.assertIn(marker, report)
                    tail = report.split(marker, 1)[1]
                    self.assertFalse(any(DIAGNOSTIC.match(line) for line in tail.splitlines()), tail)
                finally:
                    baseline.write_text(saved)
        # The SDK-free guard accepts freshly generated files, but rejects an
        # edited baseline without ever invoking either fake SDK executable.
        guard = self.run_command(["python3", str(self.scripts / Path(__file__).name),
                                  "InventoryDriftTest"])
        self.assertEqual(guard.returncode, 0, guard.stdout + guard.stderr)
        baseline.write_text(saved.replace(f"{SERVER} 2", f"{SERVER} 1"))
        guard = self.run_command(["python3", str(self.scripts / Path(__file__).name),
                                  "InventoryDriftTest"])
        self.assertNotEqual(guard.returncode, 0)
        self.assertIn(SERVER, guard.stdout + guard.stderr)
        compatibility = self.run_command([
            "python3", str(self.scripts / "test_analyze_failure_reports.py")])
        self.assertEqual(compatibility.returncode, 0,
                         compatibility.stdout + compatibility.stderr)

    def test_an_empty_completed_analysis_removes_all_debt(self):
        for name in ("server", "client-flutter", "client-dart", "scoped"):
            self.write_output(name, [], status=0)
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(read_baselines(self.scripts / BASELINE), dict.fromkeys(KEYS, 0))
        self.assertEqual((self.scripts / INVENTORY).read_text(), HEADERS)

    def test_a_regression_in_any_key_rejects_the_entire_refresh(self):
        for key in KEYS:
            with self.subTest(key=key):
                baseline = self.scripts / BASELINE
                baseline.write_text(self.initial_baseline.replace(f"{key} 3", f"{key} 0"))
                before = self.snapshot()
                result = self.generate()
                output = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0, output)
                current = len(self.scope_rows if key == SCOPED else self.dart_rows)
                # Counts must identify the offending key together; unrelated
                # analyzer line numbers or summaries do not explain rejection.
                reports = [line for line in output.splitlines() if key in line]
                self.assertTrue(any(re.search(r"\b0\b", line) and
                                    re.search(rf"\b{current}\b", line) for line in reports),
                                f"Name {key}, baseline 0 and current total {current} "
                                f"together in the rejection report:\n{output}")
                self.assertEqual(self.snapshot(), before, "A rejected run must write neither file")

    def test_incomplete_analysis_of_any_key_preserves_both_files(self):
        failures = (
            (255, "2 issues found.\n"),
            (0, "Unhandled exception: analyzer crashed\n2 issues found.\n"),
            (0, "FileSystemException: cannot write SDK\n2 issues found.\n"),
            (0, "An error occurred while executing an analyzer plugin\n2 issues found.\n"),
            (0, "An error occurred while setting up the analyzer plugin\n2 issues found.\n"),
            (0, ""),
        )
        for name in ("server", "client-flutter", "client-dart", "scoped"):
            output_path = self.outputs / (name + ".txt")
            status_path = self.outputs / (name + ".status")
            saved_output, saved_status = output_path.read_bytes(), status_path.read_bytes()
            for status, suffix in failures:
                with self.subTest(analysis=name, status=status, suffix=suffix):
                    self.write_output(name, self.dart_rows if name in ("server", "client-dart")
                                      else self.flutter_rows[:1], status=status, suffix=suffix)
                    before = self.snapshot()
                    result = self.generate()
                    output = result.stdout + result.stderr
                    self.assertNotEqual(result.returncode, 0, output)
                    self.assertEqual(self.snapshot(), before)
            output_path.write_bytes(saved_output)
            status_path.write_bytes(saved_status)

    def test_improvement_message_gives_a_runnable_refresh_command(self):
        result = self.run_command(["bash", str(self.scripts / "check-analyze-baseline.sh"), SERVER])
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        command = documented_refresh_command(self, output, self.root)
        refreshed = self.run_command(command)
        self.assertEqual(refreshed.returncode, 0, refreshed.stdout + refreshed.stderr)
        expected = len(set(self.dart_rows))
        self.assertEqual(read_baselines(self.scripts / BASELINE)[SERVER], expected,
                         "The scratch SDK reports the fixture's unique diagnostic total")


if __name__ == "__main__":
    unittest.main()
