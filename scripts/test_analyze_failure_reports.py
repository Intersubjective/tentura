"""Failed analyzer gates leave complete diagnostics readable after log clipping.

Exercise the real shell entry point in a scratch checkout, following the
analyzer gate's existing deterministic tool-fixture convention. No SDK,
codegen, network, or changes to the caller's checkout are needed.

The inventory records existing diagnostics independently of their position,
severity, and filename; only absent diagnostics belong in the failure summary.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


GATE = Path(__file__).resolve().with_name("check-analyze-baseline.sh")
PACKAGES = ("packages/client", "packages/server")


class AnalyzerFailureReportsTest(unittest.TestCase):
    def run_over_budget_gate(self, root, package, shared):
        scripts = root / "scripts"
        scripts.mkdir()
        for name in (GATE.name, "check-analysis.sh", "check-custom-lints.sh"):
            shutil.copy2(GATE.with_name(name), scripts / name)
        (scripts / "analyze-baseline.txt").write_text(
            "packages/client 1946\npackages/server 1946\n"
        )
        (scripts / "custom-lint-baseline.txt").write_text(
            "packages/client 0\npackages/server 0\n"
        )
        # Match the gate's generated-source preflight, as the other gate tests do.
        for relative in (
            "lib/ui/l10n/l10n.dart",
            "lib/app/router/root_router.gr.dart",
            "lib/domain/entity/jwt_entity.freezed.dart",
            "lib/data/database/tentura_db.g.dart",
        ):
            output = root / package / relative
            output.parent.mkdir(parents=True, exist_ok=True)
            output.touch()

        # Put the three actionable diagnostics at the START of a long log.
        # A tail-only caller loses them unless the gate retains the report.
        diagnostics = [
            "   warning - lib/changed.dart:3:8 - Unused import: 'dart:math'. - unused_import",
            "   warning - lib/changed.dart:8:9 - The value of the local variable 'count' isn't used. - unused_local_variable",
            "   info - lib/changed.dart:12:3 - Don't invoke 'print' in production code. - avoid_print",
        ] + [
            # Existing debt shares a file and rule with an introduced issue;
            # filename or severity heuristics cannot replace the inventory.
            "   warning - lib/changed.dart:1:8 - Unused import: 'dart:io'. - unused_import"
            if line == 1 else
            f"   info - lib/existing.dart:{line}:1 - Use a const constructor. - prefer_const_constructors"
            for line in range(1, 1947)
        ]
        if package == "packages/client" and not shared:
            # Flutter's human-readable format differs from dart analyze's.
            diagnostics = [
                "   " + " • ".join((severity, message, location, code))
                for severity, location, message, code in (
                    line.strip().split(" - ", 3) for line in diagnostics
                )
            ]
        (scripts / "analyze-baseline-inventory.tsv").write_text(
            "".join(f"{package}\t{line}\n" for line in sorted(set(diagnostics[3:])))
            # The same diagnostic under another key does not establish debt
            # for the package being checked.
            + "".join(f"{other}\t{line}\n" for other in PACKAGES if other != package
                      for line in sorted(diagnostics[:3]))
        )
        # This is only the fake tool's input. check-analysis.sh creates and
        # owns a DIFFERENT shared output, and the baseline gate filters that
        # into a third file, exactly as in production.
        analyzer_output = root / "tool-response.txt"
        analyzer_output.write_text(
            "Analyzing project...\n" + "\n".join(diagnostics)
            + "\n1949 issues found.\n"
        )
        bin_dir = root / "bin"
        bin_dir.mkdir()
        for tool in ("dart", "flutter"):
            executable = bin_dir / tool
            executable.write_text(
                '#!/usr/bin/env bash\nset -eu\n'
                '[[ "$1" == analyze ]] || exit 64\n'
                'printf "%s\\n" "$0 $*" >> "$REPORT_TEST_TOOL_CALLS"\n'
                'cat "$REPORT_TEST_ANALYZER_OUTPUT"\n'
                'for arg in "$@"; do\n'
                '  [[ "$arg" != --no-fatal-warnings ]] || exit 0\n'
                'done\nexit 2\n'
            )
            executable.chmod(0o755)

        # Observe temp-file ownership without replacing the production driver
        # or either gate. The first allocation belongs to check-analysis.sh.
        real_mktemp = shutil.which("mktemp")
        self.assertIsNotNone(real_mktemp)
        mktemp = bin_dir / "mktemp"
        mktemp.write_text(
            '#!/usr/bin/env python3\n'
            'import os, subprocess, sys\n'
            f'result = subprocess.run([{real_mktemp!r}, *sys.argv[1:]], '
            'capture_output=True, text=True, timeout=5)\n'
            'if result.returncode == 0:\n'
            '    with open(os.environ["REPORT_TEST_TEMP_FILES"], "a") as log:\n'
            '        log.write(result.stdout)\n'
            'sys.stdout.write(result.stdout)\n'
            'sys.stderr.write(result.stderr)\n'
            'sys.exit(result.returncode)\n'
        )
        mktemp.chmod(0o755)

        env = os.environ.copy()
        for key in tuple(env):
            if key.startswith("TENTURA_ANALYZER_") or key == "TENTURA_CUSTOM_LINT_RULES":
                env.pop(key)
        env.update({
            "PATH": str(bin_dir) + os.pathsep + env["PATH"],
            "REPORT_TEST_ANALYZER_OUTPUT": str(analyzer_output),
            "REPORT_TEST_TOOL_CALLS": str(root / "tool-calls.txt"),
            "REPORT_TEST_TEMP_FILES": str(root / "temp-files.txt"),
            "TMPDIR": str(root / "tmp"),
            "XDG_CACHE_HOME": str(root / "cache"),
        })
        (root / "tmp").mkdir()
        entrypoint = "check-analysis.sh" if shared else GATE.name
        result = subprocess.run(
            ["bash", str(scripts / entrypoint), package],
            cwd=root, env=env, capture_output=True, text=True, timeout=20,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 1, output[-2000:])
        self.assertIn(f"{package} has 1949 issues, baseline is 1946", output)
        if shared:
            self.assertIn(f"check-custom-lints: {package} OK", output)
            calls = (root / "tool-calls.txt").read_text().splitlines()
            self.assertEqual(len(calls), 1, "CI must share one analyzer run")
            temporary_files = (root / "temp-files.txt").read_text().splitlines()
            self.assertGreaterEqual(len(temporary_files), 3)
            upstream_output = Path(temporary_files[0])
            self.assertNotEqual(upstream_output, analyzer_output)
            self.assertFalse(
                upstream_output.exists(),
                "check-analysis.sh must have completed its own EXIT cleanup",
            )
        return output, diagnostics

    def assert_readable_report_in_failure_tail(self, output, diagnostics):
        tail = "\n".join(output.splitlines()[-12:])
        # Do not prescribe the report filename or the surrounding message.
        # The operator must be able to find a readable absolute path in the
        # final failure lines, even when earlier output has been clipped.
        candidates = re.findall(r"/[^\s\"'`<>]+", tail)
        reports = [Path(path.rstrip(".,:;)")) for path in candidates]
        reports = [path for path in reports if path.is_file()]
        self.assertTrue(
            reports,
            "Failure tail must point to a retained diagnostic report after "
            "the gate and its upstream analyzer have exited:\n" + tail,
        )
        contents = [path.read_text() for path in reports]
        self.assertTrue(
            any(all(line in content for line in diagnostics) for content in contents),
            "A referenced report must preserve all 1949 diagnostic lines, "
            "including the three early diagnostics hidden by log clipping",
        )
        # Assert the final summary itself, not just the retained full log.
        # The analyzer's raw output precedes this count-overrun verdict.
        summary = output.rsplit("has 1949 issues, baseline is 1946", 1)[1]
        for line in diagnostics[:3]:
            self.assertIn(line, summary, "Failure summary must identify new diagnostics")
            self.assertIn(line, tail, "New diagnostics must survive tail clipping")
        for line in diagnostics[3:]:
            self.assertNotIn(line, summary, "Existing debt must not be listed as new")

    def test_direct_analysis_failure_lists_new_diagnostics_and_preserves_full_report(self):
        for package in PACKAGES:
            with self.subTest(package=package), tempfile.TemporaryDirectory() as scratch:
                output, diagnostics = self.run_over_budget_gate(
                    Path(scratch), package, shared=False,
                )
                self.assert_readable_report_in_failure_tail(output, diagnostics)

    def test_shared_analysis_failure_lists_new_diagnostics_after_upstream_cleanup(self):
        for package in PACKAGES:
            with self.subTest(package=package), tempfile.TemporaryDirectory() as scratch:
                output, diagnostics = self.run_over_budget_gate(
                    Path(scratch), package, shared=True,
                )
                self.assert_readable_report_in_failure_tail(output, diagnostics)


if __name__ == "__main__":
    unittest.main()
