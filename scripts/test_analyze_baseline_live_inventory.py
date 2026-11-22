"""Refreshed analyzer debt equals the real checkout's SDK diagnostics.

Run through run_with_test_cleanup.sh (this test invokes the real SDK gates).
The gates analyze the checkout's sources using private copies of the debt files.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_analyze_baseline_generation import (
    BASELINE, CLIENT, DIAGNOSTIC, HEADERS, INVENTORY, SCOPED,
    SCRIPTS, SERVER, documented_refresh_command, read_baselines,
)


class LiveAnalyzerInventoryTest(unittest.TestCase):
    maxDiff = 6000

    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.debt_dir = Path(scratch.name).resolve()

    def run_cli(self, command, timeout=600, **env_overrides):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("TENTURA_ANALYZER_")
               and key not in ("TENTURA_CUSTOM_LINT_RULES", "GENERATION_TEST_OUTPUTS")}
        env["LC_ALL"] = "C"
        env["TENTURA_ANALYZER_DEBT_DIR"] = str(self.debt_dir)
        env.update(env_overrides)
        result = subprocess.run(command, cwd=SCRIPTS.parent, env=env,
                                capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout + result.stderr

    def test_checked_in_client_locations_match_the_live_analyzer(self):
        for name in (BASELINE, INVENTORY):
            shutil.copyfile(SCRIPTS / name, self.debt_dir / name)
        committed_total = read_baselines(self.debt_dir / BASELINE)[CLIENT]
        captured = self.debt_dir / "client-diagnostics.txt"
        status, output = self.run_cli(
            ["bash", "scripts/check-analyze-baseline.sh", CLIENT],
            TENTURA_ANALYZER_CAPTURE=str(captured),
        )
        self.assertEqual(status, 0, output[-6000:])
        live_rows = set(captured.read_text().splitlines())
        self.assertTrue(live_rows, "The completed Flutter analysis must report diagnostics")
        live_total = len(live_rows)
        self.assertIn(f"{CLIENT} OK ({live_total} <= {committed_total})", output)
        inventory_rows = set()
        for row in (self.debt_dir / INVENTORY).read_text().splitlines():
            key, _, diagnostic = row.partition("\t")
            if key == CLIENT and re.match(r"^\s*(?:error|warning|info) • ", diagnostic):
                inventory_rows.add(diagnostic)
        stale = sorted(inventory_rows - live_rows)
        missing = sorted(live_rows - inventory_rows)
        if stale or missing:
            self.fail(
                f"Checked-in count {committed_total}, live count {live_total}.\n"
                f"Stale inventory rows ({len(stale)}), first eight:\n"
                + "\n".join(stale[:8])
                + f"\nLive rows missing from the inventory ({len(missing)}), first eight:\n"
                + "\n".join(missing[:8])
            )

    def test_refresh_matches_live_diagnostics_and_baseline_zero_reports_no_new_debt(self):
        originals = {name: (SCRIPTS / name).read_bytes() for name in (BASELINE, INVENTORY)}
        for name, content in originals.items():
            (self.debt_dir / name).write_bytes(content)
        baseline = self.debt_dir / BASELINE
        old_totals = read_baselines(baseline)
        with self.subTest(behavior="one command refreshes both debt files"):
            # Trigger the public improvement guidance even if today's server
            # count equals its baseline. Restore the original ratchet BEFORE
            # invoking the documented generator.
            baseline.write_text(re.sub(
                rf"^{re.escape(SERVER)} \d+$", f"{SERVER} {old_totals[SERVER] + 1000000}",
                originals[BASELINE].decode(), flags=re.MULTILINE))
            try:
                status, guidance = self.run_cli(["bash", "scripts/check-analyze-baseline.sh", SERVER])
            finally:
                baseline.write_bytes(originals[BASELINE])
            self.assertEqual(status, 0, guidance[-6000:])
            command = documented_refresh_command(self, guidance, SCRIPTS.parent)
            status, output = self.run_cli(command, timeout=1200)
            self.assertEqual(status, 0, output[-6000:])
        # Even when the CLI is missing, exercise live analysis against the
        # copied inventory. This exposes stale or missing rows independently
        # of script existence and cannot be satisfied by fixture-shaped rows.
        generated_baseline = baseline.read_bytes()
        generated_totals = read_baselines(baseline)
        inventory = (self.debt_dir / INVENTORY).read_text()
        with self.subTest(behavior="headers and baseline key order are preserved"):
            self.assertTrue(inventory.startswith(HEADERS))
            self.assertEqual(list(generated_totals), list(old_totals))
            comments = lambda text: [line for line in text.splitlines() if line.startswith("#")]
            self.assertEqual(comments(generated_baseline.decode()), comments(originals[BASELINE].decode()))
        actual = {key: [] for key in generated_totals}
        for row in inventory.splitlines()[7:]:
            key, diagnostic = row.split("\t", 1)
            self.assertIn(key, actual)
            self.assertRegex(diagnostic, DIAGNOSTIC)
            actual[key].append(diagnostic)
        status, rules = self.run_cli(["bash", "scripts/check-custom-lints.sh", "--print-rules"])
        self.assertEqual(status, 0, rules)
        custom = re.compile(r"(?: - | • )(?:(?:tentura_lints/)?(?:" + rules.strip() + r"))$")
        expected = {key: set() for key in generated_totals}
        live_totals = {}
        for key, shared in ((SERVER, False), (CLIENT, False), (CLIENT, True), (SCOPED, False)):
            package, _, scope = key.partition(":")
            command = ["bash", "scripts/check-analysis.sh" if shared else
                       "scripts/check-analyze-baseline.sh", package]
            if scope:
                command.append(scope)
            baseline.write_text(re.sub(
                rf"^{re.escape(key)} \d+$", key + " 0",
                generated_baseline.decode(), flags=re.MULTILINE))
            try:
                print(f"Checking live diagnostics: {key}, shared={shared}", flush=True)
                status, output = self.run_cli(command)
            finally:
                baseline.write_bytes(generated_baseline)
            # A missing summary or an analyzer crash must not masquerade as
            # the intended baseline-zero overrun.
            marker = re.search(re.escape(key) + r" has (\d+) issues, baseline is 0\.", output)
            self.assertIsNotNone(marker, output[-6000:])
            total = int(marker[1])
            live_totals[key] = total
            before, after = output[:marker.start()], output[marker.end():]
            # gate output, not a second hand-built parser fixture: the shared
            # gate prints custom hits too, but they do not belong in inventory.
            rows = {line for line in before.splitlines() if DIAGNOSTIC.match(line)
                    and not (package == CLIENT and custom.search(line))}
            self.assertEqual(len(rows), total, "Extract every unique line the real gate counted")
            expected[key].update(rows)
            with self.subTest(key=key, shared=shared, behavior="no new debt after refresh"):
                self.assertEqual(status, 1, output[-6000:])
                new_rows = [line for line in after.splitlines() if DIAGNOSTIC.match(line)]
                self.assertEqual(new_rows, [],
                                 f"{key}, shared={shared}: diagnostic tail after 'baseline is 0.' "
                                 "must be empty; known live diagnostics were reported as new debt")
            with self.subTest(key=key, shared=shared, behavior="baseline equals live total"):
                self.assertEqual(generated_totals[key], total)
                self.assertLessEqual(total, old_totals[key], "Refresh must never raise a baseline")
        for key in generated_totals:
            with self.subTest(key=key, behavior="every row is live and every live row is inventoried"):
                self.assertEqual(actual[key], sorted(expected[key], key=lambda line: line.encode()),
                                 "Exact set equality excludes stale/fabricated rows, missing formats, "
                                 "custom hits, and unscoped diagnostics in the scoped inventory")
        for package in (SERVER, CLIENT):
            with self.subTest(key=package, behavior="normal gate reports equal counts without improvement"):
                status, output = self.run_cli(["bash", "scripts/check-analyze-baseline.sh", package])
                self.assertEqual(status, 0, output[-6000:])
                total = live_totals[package]
                self.assertIn(f"{package} OK ({total} <= {total})", output)
                self.assertNotIn("improved", output)
        with self.subTest(behavior="generated files pass the SDK-free drift guard"):
            # The guard reads the debt files beside its own script.
            guard = self.debt_dir / "test_analyze_baseline_generation.py"
            shutil.copyfile(SCRIPTS / guard.name, guard)
            status, output = self.run_cli([
                "python3", str(guard), "InventoryDriftTest"], timeout=30)
            self.assertEqual(status, 0, output)


if __name__ == "__main__":
    unittest.main()
