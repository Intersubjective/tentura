"""Smoke tests for Composer Autopilot (no Cursor API required)."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from review import parse_review_response
from schemas import WorkUnit
from tasks import build_task_queue, diff_respects_constraint, select_tasks


class ComposerAutopilotSmokeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path(__file__).resolve().parents[2]

    def test_select_tasks_default_order(self) -> None:
        tasks = select_tasks(self.repo, task_ids=[], include_disabled=False)
        ids = [t.unit.id for t in tasks]
        self.assertIn("test-backfill", ids)
        self.assertIn("coord-phase-a", ids)
        self.assertLess(ids.index("test-backfill"), ids.index("coord-phase-a"))

    def test_dto_subtasks_generated(self) -> None:
        queue = build_task_queue(self.repo)
        dto = [t for t in queue if t.unit.id.startswith("dto-")]
        self.assertGreaterEqual(len(dto), 1)
        self.assertTrue(all("server" in t.packages for t in dto))

    def test_diff_respects_constraint(self) -> None:
        ok = diff_respects_constraint(
            ["packages/client/test/foo_test.dart"],
            ("packages/client/test/", "packages/server/test/"),
        )
        self.assertTrue(ok)
        bad = diff_respects_constraint(
            ["packages/client/lib/foo.dart"],
            ("packages/client/test/",),
        )
        self.assertFalse(bad)

    def test_parse_review_response_json(self) -> None:
        raw = '{"approve": true, "reason": "Looks good."}'
        d = parse_review_response(raw)
        self.assertTrue(d.approve)
        self.assertIn("good", d.reason)

    def test_parse_review_response_fenced(self) -> None:
        raw = 'Here:\n```json\n{"approve": false, "reason": "Missing tests"}\n```'
        d = parse_review_response(raw)
        self.assertFalse(d.approve)

    def test_workunit_validation(self) -> None:
        with self.assertRaises(ValueError):
            WorkUnit(
                id="x",
                intent="intent long enough here",
                write_set=["a.dart"],
                read_set=["a.dart"],
                success_criteria=["ok"],
            )


if __name__ == "__main__":
    unittest.main()
