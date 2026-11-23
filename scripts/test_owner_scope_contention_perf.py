"""Acceptance checks for the local PostgreSQL owner-scope benchmark."""

from collections import Counter
import json
from math import ceil
import os
from pathlib import Path
import re
import subprocess
import unittest

from scripts.test_support.owner_scope_perf_postgres import PROBE_ENV, run_with_postgres_probe


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "packages/server"
SUITE = "test/perf/constellation_owner_scope_contention_pg_test.dart"
WRAPPER = ROOT / "scripts/run_with_test_cleanup.sh"
ANCHOR_FIXTURE = "owner_scope_anchor_batch"
FIELD_FIXTURE = "owner_scope_field_read"
REPLAY_ENV = "TENTURA_OWNER_SCOPE_BUDGET_SAMPLES"


class OwnerScopeContentionPerfTest(unittest.TestCase):
    def require_local_suite(self):
        plan = subprocess.run(
            ["bash", "scripts/perf/run_perf_suite.sh", "--print-plan"],
            cwd=ROOT, capture_output=True, text=True, check=True, timeout=15,
        ).stdout
        entries = [line for line in plan.splitlines() if SUITE in line.split()]
        self.assertEqual(
            len(entries), 1,
            f"The local perf plan should offer {SUITE} exactly once.",
        )

    def dart_environment(self, replay_samples=None):
        environment = {key: value for key, value in os.environ.items()
                       if key not in (REPLAY_ENV, PROBE_ENV)}
        environment["TENTURA_PG_TESTS_REQUIRED"] = "1"
        if replay_samples is not None:
            environment[REPLAY_ENV] = json.dumps(replay_samples)
        return environment

    def dart_command(self, *args, reporter="expanded", limit="4m"):
        return [str(WRAPPER), "--timeout", limit, "--", "dart", "test",
                "--reporter", reporter, *args, SUITE]

    def dart_test(self, *args, reporter="expanded", limit="4m", timeout=260, replay_samples=None):
        return subprocess.run(
            self.dart_command(*args, reporter=reporter, limit=limit),
            cwd=SERVER, capture_output=True, text=True, timeout=timeout,
            env=self.dart_environment(replay_samples),
        )

    def test_perf_exclusion_selects_no_tests_from_the_local_suite(self):
        self.require_local_suite()
        header = (SERVER / SUITE).read_text(encoding="utf-8").split("library;", 1)[0]
        tags = re.search(r"@Tags\(\s*(?:<String>)?\[([^\]]*)\]", header)
        self.assertIsNotNone(tags, "Declare the perf tags at library scope.")
        declared = set(re.findall(r"['\"](\w+)['\"]", tags[1]))
        self.assertLessEqual({"perf", "pg", "mr"}, declared)

        result = self.dart_test("-x", "perf", limit="45s", timeout=65)
        self.assertEqual(result.returncode, 79, result.stdout + result.stderr)

    def test_routine_postgres_profiles_report_that_they_skip_the_local_suite(self):
        for profile in ("server-pg", "server-mr"):
            with self.subTest(profile=profile):
                plan = subprocess.run(
                    ["bash", "scripts/run_tests.sh", "--dry-run", profile],
                    cwd=ROOT, capture_output=True, text=True, check=True, timeout=15,
                ).stderr
                self.assertIn(
                    f"skipping perf/load suite (manual measurement): {SUITE}",
                    [line.removeprefix("[run-tests] ") for line in plan.splitlines()
                     if "skipping perf/load suite" in line],
                )

    def test_local_postgres_run_reports_anchor_budget_and_field_wait(self):
        self.require_local_suite()
        exit_code, output, observations = run_with_postgres_probe(
            self.dart_command(), SERVER, self.dart_environment(), timeout=260,
        )
        self.assertEqual(exit_code, 0, output)
        reports = self.read_reports(output)
        self.assertLessEqual({ANCHOR_FIXTURE, FIELD_FIXTURE}, reports.keys(), output)
        for fixture in (ANCHOR_FIXTURE, FIELD_FIXTURE):
            with self.subTest(fixture=fixture):
                parameters = reports[fixture]["parameters"]
                self.assertEqual(parameters["attemptBudget"], 3)
                self.assertEqual(parameters["timeBudgetMs"], 5000)
                self.assertEqual(parameters["tagOpsPerImport"], 20)
                self.assertGreater(parameters["calls"], 1)

                contention = reports[fixture]["contention"]
                if fixture == ANCHOR_FIXTURE:
                    ratio, retry_rate = self.check_anchor_report(
                        contention, parameters["calls"],
                    )
                    self.assertGreaterEqual(
                        ratio, 0.99,
                        f"Within-budget ratio {ratio:.2%}, retry rate {retry_rate:.2%}.",
                    )
                    load = contention["loadSanity"]
                    self.assertGreater(load["overlappingCalls"], 0)
                    self.assertLessEqual(load["overlappingCalls"], parameters["calls"])
                    self.assertGreater(load["tagOpsIssued"], 0)
                    self.assertEqual(load["tagRowsCommitted"], load["tagOpsIssued"])
                    self.assertGreater(load["anchorOpsCommitted"], 0)
                    self.assertEqual(load["anchorCursorAdvance"], load["anchorOpsCommitted"])
                    self.assertEqual(load["anchorOpLogAdvance"], load["anchorOpsCommitted"])
                else:
                    self.assert_field_report(contention, parameters["calls"])
        self.assert_postgres_observations(reports, observations)

    def assert_postgres_observations(self, reports, observations):
        field_iterations = reports[FIELD_FIXTURE]["contention"]["iterations"]
        groups = {(ANCHOR_FIXTURE, None): []}
        groups.update({(FIELD_FIXTURE, index): [] for index in range(len(field_iterations))})
        for observation in observations:
            key = (observation["fixture"], observation.get("iteration"))
            self.assertIn(key, groups, observation)
            groups[key].append(observation)

        for (fixture, index), phases in groups.items():
            with self.subTest(fixture=fixture, iteration=index):
                self.assertEqual([phase["phase"] for phase in phases], ["before", "waiting", "after"])
                initial, blocked, final = phases
                for phase in phases:
                    self.assertEqual(phase["viewerId"], initial["viewerId"])
                    self.assertTrue(phase["state"]["scopeEnforced"])
                before, waiting, after = (phase["state"] for phase in phases)
                writer_xid = blocked["lock"]["writerXid"]
                self.assertTrue(writer_xid)
                committed_by_blocker = after["tagRowsByTransaction"].get(writer_xid, 0)
                self.assertNotIn(writer_xid, waiting["tagRowsByTransaction"])
                tag_rows = after["tagRows"] - before["tagRows"]
                tag_ops = after["tagOps"] - before["tagOps"]
                if fixture == ANCHOR_FIXTURE:
                    load = reports[fixture]["contention"]["loadSanity"]
                    self.assertGreater(committed_by_blocker, 0)
                    self.assertEqual(tag_rows, load["tagOpsIssued"])
                    self.assertEqual(tag_ops, tag_rows)
                    anchor_ops = after["anchorOps"] - before["anchorOps"]
                    self.assertEqual(anchor_ops, load["anchorOpsCommitted"])
                    self.assertEqual(after["anchorCursor"] - before["anchorCursor"], anchor_ops)
                    self.assertEqual(
                        after["anchorOpsRepeatableRead"] - before["anchorOpsRepeatableRead"],
                        anchor_ops,
                    )
                    self.assertGreater(after["anchorRowRevision"], before["anchorCursor"])
                else:
                    iteration = field_iterations[index]
                    for phase in phases:
                        self.assertEqual(phase["viewerId"], iteration["viewerId"])
                        self.assertEqual(phase["unseenPersonId"], iteration["unseenPersonId"])
                    self.assertFalse(before["firstSeen"])
                    self.assertFalse(waiting["firstSeen"])
                    self.assertTrue(after["firstSeen"])
                    self.assertIn(blocked["lock"]["waitingTransaction"], after["firstSeenWriters"])
                    self.assertEqual(committed_by_blocker, 20)
                    self.assertEqual(tag_rows, 20)
                    self.assertEqual(tag_ops, 20)

    def test_an_eventual_commit_over_five_seconds_fails_the_gate_with_measured_rates(self):
        self.require_local_suite()
        # Replay measured calls at the benchmark's reporting entry point. This
        # isolates the five-second boundary from PostgreSQL and scheduler noise.
        samples = [
            {"attempts": 1, "latencyMs": 4999, "committed": True},
            {"attempts": 2, "latencyMs": 5000, "committed": True},
            {"attempts": 1, "latencyMs": 5001, "committed": True},
            {"attempts": 3, "latencyMs": 15, "committed": True},
        ]
        result = self.dart_test(
            reporter="json", limit="45s", timeout=65, replay_samples=samples,
        )
        output = result.stdout + "\n" + result.stderr
        self.assertEqual(result.returncode, 1, output)

        events = self.read_test_events(result.stdout)
        printed = "\n".join(event["message"] for event in events if event["type"] == "print")
        reports = self.read_reports(output + "\n" + printed)
        self.assertIn(ANCHOR_FIXTURE, reports, output)
        contention = reports[ANCHOR_FIXTURE]["contention"]
        for key in ("attempts", "latencyMs", "committed"):
            self.assertEqual(
                [call[key] for call in contention["callSamples"]],
                [call[key] for call in samples],
            )
        self.assertEqual(self.check_anchor_report(contention, len(samples)), (0.75, 0.50))
        self.assertEqual(contention["exhaustedCalls"], 0)

        errors = [event["error"].lower() for event in events if event["type"] == "error"]
        ratio = re.compile(r"within[- ]budget ratio[^\d\n]*(?:75(?:\.0+)?\s*%|0\.750*\b)")
        retry = re.compile(r"retry rate[^\d\n]*(?:50(?:\.0+)?\s*%|0\.50*\b)")
        self.assertTrue(
            any(ratio.search(error) and retry.search(error) for error in errors),
            f"Expected one failure naming the 75% within-budget ratio and 50% retry rate. {errors}",
        )

    def read_test_events(self, output):
        events = []
        for line in output.splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(event, dict) and "type" in event:
                events.append(event)
        return events

    def read_reports(self, output):
        reports = {}
        decoder = json.JSONDecoder()
        for opening in re.finditer(r"(?m)^[^{\n]*\{", output):
            try:
                report, _ = decoder.raw_decode(output, opening.end() - 1)
            except json.JSONDecodeError:
                continue
            if (
                isinstance(report, dict)
                and isinstance(report.get("fixture"), str)
                and "parameters" in report
            ):
                self.assertNotIn(report["fixture"], reports)
                reports[report["fixture"]] = report
        return reports

    def check_anchor_report(self, contention, total):
        self.assertEqual(contention["calls"], total)
        calls = contention["callSamples"]
        self.assertEqual(len(calls), total)
        within_budget = 0
        unsuccessful = 0
        distribution = Counter()
        for index, call in enumerate(calls):
            attempts = call["attempts"]
            latency = call["latencyMs"]
            committed = call["committed"]
            self.assertIs(type(attempts), int)
            self.assertGreaterEqual(attempts, 1)
            self.assertGreater(latency, 0)
            self.assertIs(type(committed), bool)
            qualifies = committed and attempts <= 3 and latency <= 5000
            self.assertIs(call["withinBudget"], qualifies, f"Anchor call {index}: {call}")
            within_budget += qualifies
            unsuccessful += not committed
            distribution[str(attempts)] += 1

        self.assertEqual(contention["withinBudget"], within_budget)
        self.assertEqual(contention["budgetMisses"], total - within_budget)
        self.assertTrue(0 <= contention["exhaustedCalls"] <= unsuccessful)
        self.assertEqual(contention["attemptDistribution"], dict(distribution))
        retry_rate = 1 - distribution.get("1", 0) / total
        self.assertAlmostEqual(contention["retryRate"], retry_rate, places=3)
        self.assert_percentiles(
            contention["callLatencyMs"], [call["latencyMs"] for call in calls],
        )
        return within_budget / total, retry_rate

    def assert_field_report(self, contention, total):
        iterations = contention["iterations"]
        self.assertEqual(len(iterations), total)
        for iteration in iterations:
            viewer = iteration["viewerId"]
            person = iteration["unseenPersonId"]
            self.assertTrue(viewer)
            self.assertTrue(person)
            self.assertIsNone(iteration["firstSeenBefore"])
            self.assertIs(iteration["fieldReadSucceeded"], True)
            self.assertEqual(iteration["fieldPersonId"], person)
            self.assertIs(iteration["waitedOnWriter"], True)
            stored = iteration["firstSeenAfterWriterCommit"]
            self.assertEqual((stored["viewerId"], stored["personId"]), (viewer, person))
            self.assertEqual(iteration["tagRowsCommitted"], 20)
        for metric in ("firstSeenWaitMs", "fieldResponseMs"):
            self.assert_percentiles(
                contention[metric], [sample[metric] for sample in iterations],
            )
        self.assertGreater(contention["writerHoldMs"], 0)

    def assert_percentiles(self, series, samples):
        self.assertTrue(all(sample > 0 for sample in samples))
        ordered = sorted(samples)
        for percentile in (95, 99):
            expected = ordered[ceil(percentile * len(ordered) / 100) - 1]
            self.assertAlmostEqual(series[f"p{percentile}"], expected, places=3)


if __name__ == "__main__":
    unittest.main()
