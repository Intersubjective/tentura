"""Refreshed analyzer debt equals the real checkout's SDK diagnostics.

Run through run_with_test_cleanup.sh (this test invokes the real SDK gates).
Only the two debt files are temporarily changed; cleanup restores their exact
bytes even on assertion failure. Do not run alongside manual baseline edits.
"""

import os
import re
import subprocess
import unittest

from test_analyze_baseline_generation import (
    BASELINE, CLIENT, DIAGNOSTIC, HEADERS, INVENTORY, SCOPED,
    SCRIPTS, SERVER, documented_refresh_command, read_baselines,
)


class LiveAnalyzerInventoryTest(unittest.TestCase):
    maxDiff = 6000

    def run_cli(self, command, timeout=600):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("TENTURA_ANALYZER_")
               and key not in ("TENTURA_CUSTOM_LINT_RULES", "GENERATION_TEST_OUTPUTS")}
        env["LC_ALL"] = "C"
        result = subprocess.run(command, cwd=SCRIPTS.parent, env=env,
                                capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout + result.stderr

    def test_refresh_matches_live_diagnostics_and_baseline_zero_reports_no_new_debt(self):
        originals = {name: (SCRIPTS / name).read_bytes() for name in (BASELINE, INVENTORY)}

        def restore():
            for name, content in originals.items():
                (SCRIPTS / name).write_bytes(content)

        self.addCleanup(restore)
        old_totals = read_baselines(SCRIPTS / BASELINE)
        with self.subTest(behavior="one command refreshes both debt files"):
            # Trigger the public improvement guidance even if today's server
            # count equals its baseline. Restore the original ratchet BEFORE
            # invoking the documented generator.
            baseline = SCRIPTS / BASELINE
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
        # checked-in inventory. This exposes stale/missing rows independently
        # of script existence and cannot be satisfied by fixture-shaped rows.
        generated_baseline = (SCRIPTS / BASELINE).read_bytes()
        generated_totals = read_baselines(SCRIPTS / BASELINE)
        inventory = (SCRIPTS / INVENTORY).read_text()
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
            (SCRIPTS / BASELINE).write_text(re.sub(
                rf"^{re.escape(key)} \d+$", key + " 0",
                generated_baseline.decode(), flags=re.MULTILINE))
            try:
                print(f"Checking live diagnostics: {key}, shared={shared}", flush=True)
                status, output = self.run_cli(command)
            finally:
                (SCRIPTS / BASELINE).write_bytes(generated_baseline)
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
            status, output = self.run_cli([
                "python3", "scripts/test_analyze_baseline_generation.py", "InventoryDriftTest"], timeout=30)
            self.assertEqual(status, 0, output)


if __name__ == "__main__":
    unittest.main()
