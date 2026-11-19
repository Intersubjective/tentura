"""Concurrent checkout readers and writers can run alongside the live inventory test."""

from contextlib import ExitStack, contextmanager
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from test_analyze_baseline_generation import (
    BASELINE, CLIENT, HEADERS, INVENTORY, KEYS, SCOPED, SCRIPTS, SERVER,
    read_baselines,
)


LIVE_TEST = "scripts/test_analyze_baseline_live_inventory.py"
GENERATOR = "scripts/generate_analyze_baseline.py"
ANALYZER = """#!/usr/bin/env python3
import os
from pathlib import Path
import sys
import time

assert sys.argv[1] == "analyze", sys.argv
tool = Path(sys.argv[0]).name
package = "packages/" + Path.cwd().name
scope = next((arg for arg in sys.argv[2:] if arg.startswith("lib/")), "")
key = package + (":" + scope if scope else "")
rows = Path(os.environ["ISOLATION_DIAGNOSTICS"], key.replace("/", "_") + "." + tool)
barriers = os.environ.get("ISOLATION_BARRIERS")
response = ""
if barriers:
    checkpoint = Path(barriers, str(os.getpid()))
    checkpoint.mkdir()
    (checkpoint / "ready").touch()
    resume = checkpoint / "resume"
    deadline = time.monotonic() + 45
    while not resume.exists():
        if time.monotonic() >= deadline:
            sys.exit("Timed out waiting for the concurrent checkout operation")
        time.sleep(0.01)
    response = resume.read_text()
if response == "error":
    print("error - lib/probe.dart:1:1 - Injected analysis error. - undefined_identifier")
    print("1 issue found.")
    sys.exit(3)
real_dart = os.environ.get("ISOLATION_SERVER_DART")
if package == "packages/server" and tool == "dart" and real_dart:
    os.execv(real_dart, [real_dart, *sys.argv[1:]])
print(rows.read_text(), end="")
"""


class CheckoutIsolationTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.scratch = Path(scratch.name)
        self.root = self.scratch / "checkout"
        self.scripts = self.root / "scripts"
        self.scripts.mkdir(parents=True)
        for name in (
            Path(LIVE_TEST).name, Path(GENERATOR).name,
            "test_analyze_baseline_generation.py", "check-analysis.sh",
            "check-analyze-baseline.sh", "check-custom-lints.sh", "custom-lint-baseline.txt",
        ):
            shutil.copy2(SCRIPTS / name, self.scripts / name)
        for package, generated in {
            CLIENT: ("lib/ui/l10n/l10n.dart", "lib/app/router/root_router.gr.dart"),
            SERVER: ("lib/domain/entity/jwt_entity.freezed.dart", "lib/data/database/tentura_db.g.dart"),
        }.items():
            for relative in generated:
                path = self.root / package / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
        (self.root / CLIENT / SCOPED.split(":", 1)[1]).mkdir(parents=True)

        self.diagnostics = self.scratch / "diagnostics"
        self.fixture_outputs(self.diagnostics, 2, "Known warning")
        self.original = self.fixture_outputs(self.scratch / "before", 3, "Known warning")
        for name, contents in zip((BASELINE, INVENTORY), self.original):
            (self.scripts / name).write_bytes(contents)

        bin_dir = self.scratch / "bin"
        bin_dir.mkdir()
        for tool in ("dart", "flutter"):
            executable = bin_dir / tool
            executable.write_text(ANALYZER)
            executable.chmod(0o755)
        self.tmp_dir = self.scratch / "tmp"
        self.tmp_dir.mkdir()
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("TENTURA_ANALYZER_") and key != "TENTURA_CUSTOM_LINT_RULES"
        }
        self.env.update(PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                        TMPDIR=str(self.tmp_dir), XDG_CACHE_HOME=str(self.scratch / "cache"),
                        ISOLATION_DIAGNOSTICS=str(self.diagnostics), PYTHONDONTWRITEBYTECODE="1",
                        LC_ALL="C")
        self.git("init", "-q")
        self.git("add", ".")

    def git_status(self):
        return self.git("status", "--porcelain", "--untracked-files=all")

    def fixture_outputs(self, directory, count, message):
        directory.mkdir()
        baseline = "# Analyzer debt counts.\n"
        inventory = HEADERS
        for key in KEYS:
            baseline += f"{key} {count}\n"
            inventory_rows = []
            for tool in {CLIENT: ("flutter", "dart"), SERVER: ("dart",), SCOPED: ("flutter",)}[key]:
                scope = key.partition(":")[2] or "lib"
                rows = []
                for index in range(count):
                    location = f"{scope}/warning_{index}.dart:1:1"
                    if tool == "flutter":
                        rows.append(f"   warning • {message}. • {location} • unused_import")
                    else:
                        rows.append(f"warning - {location} - {message}. - unused_import")
                path = directory / (key.replace("/", "_") + "." + tool)
                path.write_text("\n".join(rows) + f"\n{count} issues found.\n")
                inventory_rows.extend(rows)
            inventory += "".join(f"{key}\t{row}\n" for row in sorted(inventory_rows))
        return baseline.encode(), inventory.encode()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, env=self.env, check=True,
                              capture_output=True, text=True, timeout=10).stdout

    def snapshot(self):
        return tuple((self.scripts / name).read_bytes() for name in (BASELINE, INVENTORY))

    def checkout_paths(self):
        return {
            path.relative_to(self.root)
            for entry in self.root.iterdir() if entry.name != ".git"
            for path in (entry, *entry.rglob("*"))
        }

    def assert_no_leftovers(self, checkout_paths):
        # Git status omits empty directories and may omit ignored files.
        self.assertEqual(self.checkout_paths(), checkout_paths)
        for pattern in (".analyze-refresh-*", "*analyze-baseline.txt*", "*analyze-baseline-inventory.tsv*"):
            with self.subTest(temporary_artifact=pattern):
                self.assertEqual(list(self.tmp_dir.rglob(pattern)), [])

    def assert_clean_after_run(self, status, paths):
        with self.subTest(check="checkout status"):
            self.assertEqual(self.git_status(), status)
        with self.subTest(check="temporary artifacts"):
            self.assert_no_leftovers(paths)

    @contextmanager
    def process(self, script, env):
        with tempfile.TemporaryFile(mode="w+t", encoding="utf-8") as log:
            child = subprocess.Popen([sys.executable, script], cwd=self.root, env=env,
                                     stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                yield child, log
            finally:
                if child.poll() is None:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=5)

    def run_live(self, at_checkpoint, timeout=55):
        with tempfile.TemporaryDirectory(dir=self.scratch) as checkpoint_dir:
            env = dict(self.env, ISOLATION_BARRIERS=checkpoint_dir)
            seen = set()
            deadline = time.monotonic() + timeout
            with self.process(LIVE_TEST, env) as (child, log):
                while child.poll() is None and time.monotonic() < deadline:
                    for checkpoint in Path(checkpoint_dir).iterdir():
                        if checkpoint in seen or not (checkpoint / "ready").exists():
                            continue
                        response = at_checkpoint(len(seen))
                        resume = checkpoint / "response"
                        resume.write_text(response)
                        resume.rename(checkpoint / "resume")
                        seen.add(checkpoint)
                    time.sleep(0.01)
                log.seek(0)
                output = log.read()
                self.assertIsNotNone(child.poll(), f"Live inventory test timed out:\n{output}")
                self.assertTrue(seen, f"The live inventory test never invoked the analyzer:\n{output}")
                return child.returncode, output

    def run_gate(self, key, script, *, env=None, timeout=10):
        package, _, scope = key.partition(":")
        args = ["bash", f"scripts/{script}", package]
        if scope:
            args.append(scope)
        return subprocess.run(args, cwd=self.root, env=self.env if env is None else env,
                              capture_output=True, text=True, timeout=timeout)

    def test_checkout_gates_and_debt_files_stay_stable_during_live_analysis(self):
        gates = (
            (SERVER, "check-analyze-baseline.sh"),
            (CLIENT, "check-analyze-baseline.sh"),
            (SCOPED, "check-analyze-baseline.sh"),
            (SERVER, "check-analysis.sh"),
            (CLIENT, "check-analysis.sh"),
        )
        gate_verdicts = {}
        committed = read_baselines(self.scripts / BASELINE)
        for key, script in gates:
            control = self.run_gate(key, script)
            self.assertEqual(control.returncode, 0, control.stdout + control.stderr)
            verdict = self.baseline_verdict(key, control)
            self.assertRegex(verdict or "", rf"^check-analyze-baseline: {re.escape(key)} OK "
                                            rf"\([1-9]\d* <= {committed[key]}\)$")
            gate_verdicts[key, script] = verdict

        initial_status = self.git_status()
        for fail_analysis in (False, True):
            with self.subTest(injected_analysis_error=fail_analysis):
                observed = {}
                gate_failures = {}
                checkout_paths = self.checkout_paths()

                def inspect_checkout(index):
                    for name, before, current in zip((BASELINE, INVENTORY), self.original, self.snapshot()):
                        if current != before:
                            observed.setdefault(name, index + 1)
                    for (key, script), expected in gate_verdicts.items():
                        result = self.run_gate(key, script)
                        verdict = self.baseline_verdict(key, result)
                        if result.returncode or verdict != expected:
                            failure = (key, script, result.returncode, verdict)
                            gate_failures.setdefault(failure, result)
                    return "error" if fail_analysis and index == 0 else ""

                status, output = self.run_live(inspect_checkout)
                if fail_analysis:
                    self.assertEqual(status, 1, output)
                    self.assertIn("Injected analysis error.", output)
                    self.assertIn("AssertionError:", output)
                else:
                    self.assertEqual(status, 0, output)
                self.assert_clean_after_run(initial_status, checkout_paths)
                self.assertEqual(self.snapshot(), self.original, "Live analysis left debt files modified")
                for (key, script, code, verdict), result in gate_failures.items():
                    with self.subTest(key=key, gate=script, exit_code=code, verdict=verdict):
                        self.fail(f"Expected exit 0 and {gate_verdicts[key, script]!r}.\n"
                                  f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
                for name, checkpoint in observed.items():
                    with self.subTest(file=name):
                        self.fail(f"{name} differed from its original bytes at analyzer checkpoint {checkpoint}")

    def baseline_verdict(self, key, result):
        prefix = f"check-analyze-baseline: {key} "
        return next((line for line in (result.stdout + "\n" + result.stderr).splitlines()
                     if line.startswith(prefix + "OK ") or line.startswith(prefix + "has ")), None)

    def copy_workspace(self):
        repo = SCRIPTS.parent
        # Keep checkout sources and generated inputs together with their
        # workspace configuration. Leave SDK caches and build outputs behind.
        for name in (".gitignore", "analysis_options.yaml", "pubspec.yaml", "pubspec.lock", "pubspec_overrides.yaml",
                     ".dart_tool/package_config.json", ".dart_tool/package_graph.json"):
            source = repo / name
            if name.endswith(("pubspec_overrides.yaml", "package_graph.json")) and not source.exists():
                continue
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        ignore_caches = shutil.ignore_patterns(".dart_tool", ".git", ".alloy", ".local",
                                               "coverage", "ephemeral", "node_modules")
        for directory in (
            "lib", "test", SERVER, CLIENT, "packages/tentura_lints", "packages/ferry_generator",
            "packages/force_directed_graphview", "packages/image_cropper_for_web",
            "packages/web_socket_client",
        ):
            source = repo / directory

            def ignore_outputs(path, names):
                ignored = ignore_caches(path, names)
                if Path(path) == source:
                    ignored.add("build")
                return ignored

            shutil.copytree(source, self.root / directory, dirs_exist_ok=True, ignore=ignore_outputs)

    def test_live_inventory_rejects_a_new_warning_in_checkout_server_sources(self):
        real_dart = shutil.which("dart")
        self.assertIsNotNone(real_dart, "The live server source test requires the Dart SDK")
        self.copy_workspace()
        self.env["ISOLATION_SERVER_DART"] = real_dart

        # Calibrate the copied server's baseline before adding the warning.
        # The SDK version and pre-existing debt can differ between checkouts.
        baseline = self.scripts / BASELINE
        baseline.write_bytes(self.original[0].replace(f"{SERVER} 3".encode(),
                                                       f"{SERVER} 1000000".encode()))
        capture = self.scratch / "known-server-diagnostics"
        env = dict(self.env, TENTURA_ANALYZER_CAPTURE=str(capture))
        gate = self.run_gate(SERVER, "check-analyze-baseline.sh", env=env, timeout=180)
        self.assertEqual(gate.returncode, 0, gate.stdout[:4000] + gate.stderr[-2000:])
        rows = capture.read_text().splitlines()
        self.assertIn(f"{SERVER} OK ({len(rows)} <= 1000000)", gate.stdout)
        baseline.write_bytes(self.original[0].replace(f"{SERVER} 3".encode(),
                                                       f"{SERVER} {len(rows)}".encode()))
        inventory = self.scripts / INVENTORY
        lines = [line for line in inventory.read_text().splitlines()
                 if not line.startswith(SERVER + "\t")]
        lines.extend(f"{SERVER}\t{row}" for row in rows)
        inventory.write_text("\n".join(lines) + "\n")

        probe = self.root / SERVER / "lib/analyzer_debt_probe.dart"
        with probe.open("x") as source:
            source.write("import 'dart:math';\n")
        before = self.snapshot()
        status_before = self.git_status()
        paths_before = self.checkout_paths()
        changed = set()

        def inspect_checkout(_index):
            for name, expected, actual in zip((BASELINE, INVENTORY), before, self.snapshot()):
                if actual != expected:
                    changed.add(name)
            return ""

        status, output = self.run_live(inspect_checkout, timeout=720)
        self.assertEqual(status, 1, output[-6000:])
        marker = f"{SERVER} has {len(rows) + 1} issues, baseline is {len(rows)}."
        self.assertTrue(marker in output, output[-6000:])
        probe_warning = re.search(r"^\s*warning - lib/analyzer_debt_probe\.dart:.* - unused_import$",
                                  output, re.MULTILINE)
        self.assertIsNotNone(probe_warning, output[-6000:])
        self.assert_clean_after_run(status_before, paths_before)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(changed, f"Real server analysis exposed temporary changes to {sorted(changed)}")

    def test_live_inventory_passes_with_matching_debt_without_exposing_temporary_counts(self):
        self.copy_workspace()
        # Use the operator's Dart and Flutter on PATH for both the fixture
        # refresh and the entire live suite.
        env = dict(self.env, PATH=os.environ["PATH"])
        for name in (BASELINE, INVENTORY):
            shutil.copy2(SCRIPTS / name, self.scripts / name)
        with self.process(GENERATOR, env) as (generator, log):
            generator.wait(timeout=600)
            log.seek(0)
            self.assertEqual(generator.returncode, 0, log.read()[-6000:])
        # The public refresh gives the scratch checkout a debt-consistent
        # snapshot for the SDK version in use.
        self.git("add", "--", f"scripts/{BASELINE}", f"scripts/{INVENTORY}")
        before = self.snapshot()
        status_before = self.git_status()
        paths_before = self.checkout_paths()
        changed = set()
        deadline = time.monotonic() + 900
        with self.process(LIVE_TEST, env) as (child, log):
            while child.poll() is None and time.monotonic() < deadline:
                for name, expected in zip((BASELINE, INVENTORY), before):
                    path = self.scripts / name
                    try:
                        current = path.read_bytes()
                    except FileNotFoundError:
                        current = None
                    if current != expected:
                        changed.add(name)
                time.sleep(0.05)
            log.seek(0)
            output = log.read()
            self.assertIsNotNone(child.poll(), f"Live inventory run timed out:\n{output[-6000:]}")
            self.assertEqual(child.returncode, 0, output[-6000:])
        self.assertRegex(output, r"(?m)^Ran [1-9]\d* tests? in ")
        self.assertRegex(output, r"(?m)^OK$")
        self.assert_clean_after_run(status_before, paths_before)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(changed, f"Real SDK runs exposed temporary changes to {sorted(changed)}")

    def test_published_debt_files_survive_an_overlapping_live_inventory_run(self):
        diagnostics = self.scratch / "publisher-diagnostics"
        expected = self.fixture_outputs(diagnostics, 2, "Refreshed warning")
        env = dict(self.env, ISOLATION_DIAGNOSTICS=str(diagnostics))

        with ExitStack() as stack:
            publication = None

            def allow_publication(index):
                nonlocal publication
                if index == 0:
                    publication = stack.enter_context(self.process(GENERATOR, env))
                    publisher, log = publication
                    # Also allow a valid implementation to serialize writers.
                    try:
                        publisher.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        pass
                    else:
                        log.seek(0)
                        self.assertEqual(publisher.returncode, 0, log.read())
                        for name, current, contents in zip((BASELINE, INVENTORY), self.snapshot(), expected):
                            self.assertTrue(current == contents, f"The generator did not publish the expected {name}")
                return ""

            status, output = self.run_live(allow_publication)
            publisher, log = publication
            publisher.wait(timeout=10)
            log.seek(0)
            self.assertEqual(publisher.returncode, 0, log.read())
        self.assertEqual(status, 0, output)
        for name, contents in zip((BASELINE, INVENTORY), expected):
            with self.subTest(file=name):
                self.assertTrue((self.scripts / name).read_bytes() == contents,
                                f"The overlapping live run discarded the published {name}")

    def test_manual_baseline_edit_survives_an_overlapping_live_inventory_run(self):
        baseline = self.scripts / BASELINE
        edit = self.original[0].replace(f"{SERVER} 3".encode(), f"{SERVER} 2".encode())
        baseline.write_bytes(edit)
        expected_status = self.git_status()
        baseline.write_bytes(self.original[0])
        checkout_paths = self.checkout_paths()

        def edit_baseline(index):
            if index == 0:
                baseline.write_bytes(edit)
            return ""

        status, output = self.run_live(edit_baseline)
        self.assertEqual(status, 0, output)
        self.assert_clean_after_run(expected_status, checkout_paths)
        self.assertEqual(baseline.read_bytes(), edit, "The live run discarded the manual baseline edit")
        self.assertEqual((self.scripts / INVENTORY).read_bytes(), self.original[1])


if __name__ == "__main__":
    unittest.main()
