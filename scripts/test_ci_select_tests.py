"""Shard selection (scripts/ci_select_tests.py) never loses or repeats a test
file: for every shard count CI could use, the shards of each family together
are exactly the full selection, with no file on two shards. Runs in the lints
shard, against the repository's real test trees and durations file."""

import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from ci_select_tests import DURATIONS, pack, select

REPO = Path(__file__).resolve().parent.parent
SELECT = REPO / "scripts" / "ci_select_tests.py"
BUNDLES = REPO / "scripts" / "gen_test_bundles.py"
PIPELINE = REPO / ".github" / "workflows" / "pipeline.yml"


def run_select(cwd: Path, *args: str, script: Path = SELECT) -> list[str]:
    out = subprocess.run(
        [sys.executable, str(script), *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [line for line in out.splitlines() if line]


def assert_partition(case: unittest.TestCase, full: list[str], shards: list[list[str]]) -> None:
    seen: dict[str, int] = {}
    for i, shard in enumerate(shards, 1):
        for f in shard:
            case.assertNotIn(f, seen, f"{f} on shards {seen.get(f)} and {i}")
            seen[f] = i
    case.assertEqual(sorted(seen), sorted(full), "shards do not cover the full selection")


# (package dir, --tag, --balance family, --reserve-last): as pipeline.yml runs them.
FAMILIES = [
    ("packages/client", None, "client", None),
    ("packages/server", "pg", "pg", "multi-connection"),
]


class RealTreeShardsTest(unittest.TestCase):
    def test_shards_partition_each_family_for_every_shard_count(self):
        for package, tag, family, reserve in FAMILIES:
            cwd = REPO / package
            base = ["test"] + (["--tag", tag] if tag else [])
            full = run_select(cwd, *base)
            self.assertGreater(len(full), 10, f"{package}: suspiciously few test files")
            for count in range(1, 9):
                extra = ["--balance", family] + (["--reserve-last", reserve] if reserve else [])
                with self.subTest(package=package, count=count):
                    shards = [
                        run_select(cwd, *base, "--shard", f"{i}/{count}", *extra)
                        for i in range(1, count + 1)
                    ]
                    assert_partition(self, full, shards)
                    if count <= len(full):
                        self.assertTrue(all(shards), "a shard got no files")

    def test_pipeline_shards_with_the_balanced_selection(self):
        text = PIPELINE.read_text(encoding="utf-8")
        self.assertIn("--balance client", text)
        self.assertIn("--balance pg --reserve-last multi-connection", text)

    def test_durations_file_is_well_formed(self):
        data = json.loads(DURATIONS.read_text(encoding="utf-8"))
        for family in ("client", "pg", "multi-connection"):
            with self.subTest(family=family):
                table = data[family]
                self.assertTrue(table, f"no {family} durations")
                for path, seconds in table.items():
                    self.assertRegex(path, r"^test/.+_test\.dart$")
                    self.assertIsInstance(seconds, (int, float))
                    self.assertGreaterEqual(seconds, 0)


class SyntheticShardsTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.pkg = Path(tmp.name)
        (self.pkg / "pubspec.yaml").write_text("name: fake\n")
        files = {
            "test/heavy_test.dart": "@Tags(['pg'])",
            "test/a/one_test.dart": "@Tags(['pg'])",
            "test/a/two_test.dart": "@Tags(['pg'])",
            "test/b/new_test.dart": "@Tags(['pg'])",
            "test/b/multi_test.dart": "@Tags(['pg', 'multi-connection'])",
            "test/untagged_test.dart": "",
            "test/_bundle/bundle_0_test.dart": "@Tags(['pg'])",
        }
        for rel, body in files.items():
            (self.pkg / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.pkg / rel).write_text(body + "\nvoid main() {}\n")
        self.durations = self.pkg / "durations.json"
        self.durations.write_text(
            json.dumps(
                {
                    "pg": {
                        "test/heavy_test.dart": 100,
                        "test/a/one_test.dart": 10,
                        "test/a/two_test.dart": 20,
                        "test/b/multi_test.dart": 30,
                        "test/gone_test.dart": 500,
                    },
                    "multi-connection": {"test/b/multi_test.dart": 90},
                    # The pg run fills two slots, the multi-connection run one:
                    # its 90 s of wall time book 180 slot-seconds.
                    "_parallelism": {"pg": 2, "multi-connection": 1},
                }
            )
        )

    def shard(self, i, n, *extra):
        return run_select(
            self.pkg, "test", "--tag", "pg", "--shard", f"{i}/{n}",
            "--balance", "pg", "--durations", str(self.durations), *extra,
        )

    def test_round_robin_without_balance_is_unchanged(self):
        full = run_select(self.pkg, "test", "--tag", "pg")
        self.assertEqual(
            full,
            ["test/a/one_test.dart", "test/a/two_test.dart", "test/b/multi_test.dart",
             "test/b/new_test.dart", "test/heavy_test.dart"],
        )
        self.assertEqual(run_select(self.pkg, "test", "--tag", "pg", "--shard", "2/2"), full[1::2])

    def test_without_tag_every_test_file_but_bundles(self):
        self.assertEqual(len(run_select(self.pkg, "test")), 6)

    def test_heaviest_file_gets_a_shard_to_itself(self):
        self.assertEqual(self.shard(1, 2), ["test/heavy_test.dart"])
        # The unknown new file weighs the median (30); the stale entry for a
        # deleted file only shifts that median. Longest first.
        self.assertEqual(
            self.shard(2, 2),
            ["test/b/multi_test.dart", "test/b/new_test.dart",
             "test/a/two_test.dart", "test/a/one_test.dart"],
        )

    def test_reserved_time_lands_on_the_last_shard(self):
        # 180 slot-seconds booked on shard 2 first: everything else fits on
        # shard 1 (100 + 30 + 30 + 20 = 180), then one goes to shard 1 on the
        # tie (lowest index).
        shards = [self.shard(i, 2, "--reserve-last", "multi-connection") for i in (1, 2)]
        assert_partition(self, run_select(self.pkg, "test", "--tag", "pg"), shards)
        self.assertEqual(shards[1], [])
        self.assertEqual(len(shards[0]), 5)

    def test_bundles_hold_each_file_once_and_print_longest_first(self):
        listed = run_select(
            self.pkg, ".", "--chunks", "2", "--balance", "pg",
            "--durations", str(self.durations),
            "test/heavy_test.dart", "test/a", "test/b", "test/untagged_test.dart",
            script=BUNDLES,
        )
        bundled = []
        for entry in listed:
            if "_bundle" in entry:
                source = (self.pkg / entry).read_text()
                bundled += re.findall(r"group\('([^']+)'", source)
        standalone = [e for e in listed if "_bundle" not in e]
        everything = sorted(bundled + standalone)
        self.assertEqual(
            everything,
            ["test/a/one_test.dart", "test/a/two_test.dart", "test/b/multi_test.dart",
             "test/b/new_test.dart", "test/heavy_test.dart", "test/untagged_test.dart"],
        )
        # pg-tagged files run standalone; the heaviest is printed first.
        self.assertEqual(listed[0], "test/heavy_test.dart")

    def test_pack_is_longest_first_onto_the_lightest(self):
        shards, loads = pack({"a": 5, "b": 4, "c": 3, "d": 3}, 2)
        self.assertEqual(shards, [["a", "d"], ["b", "c"]])
        self.assertEqual(loads, [8, 7])


if __name__ == "__main__":
    unittest.main()
