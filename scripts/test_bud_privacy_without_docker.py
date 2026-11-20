"""Run the bud-privacy scenario through the pg shard and local Hasura paths."""

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


REPO = Path(__file__).resolve().parent.parent
SERVER = REPO / "packages" / "server"
WORKFLOW = REPO / ".github" / "workflows" / "pipeline.yml"
METADATA = REPO / "hasura" / "metadata.json"
BUD_TEST = "test/api/post_bud_hasura_privacy_pg_test.dart"
TEST_POSTGRES_HOST = "127.0.0.1"
TEST_POSTGRES_PORT = "5433"
PRIVACY_SCENARIO = "Hasura reveals Request lineage only to viewers who can read its source"
CAROL_BUD_ASSERTION = "Carol must not be able to read the bud Request"
MISSING_BACKEND = re.compile(
    r"(?:\bHasura\b|\bmetadata\.json\b).*(?:required|missing|not |unavailable|"
    r"unreachable|refused|no such|failed|could not|did not)"
    r"|(?:missing|required|failed|could not|cannot|no such).*"
    r"(?:\bHasura\b|\bmetadata\.json\b)",
    re.IGNORECASE,
)


def run(*args, cwd=REPO, env=None, timeout=15):
    return subprocess.run(
        args, cwd=cwd, env=env, capture_output=True, text=True,
        timeout=timeout,
    )


def result_output(result):
    return result.stdout + result.stderr


def read_report(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def step(job, *, identifier=None, name=None):
    return next(
        item for item in job["steps"]
        if (identifier is not None and item.get("id") == identifier)
        or (name is not None and item.get("name") == name)
    )


class BudPrivacyWithoutDockerTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="bud_privacy_pg_")
        self.addCleanup(temp.cleanup)
        self.scratch = Path(temp.name)
        self.report = self.scratch / "pg--pg-1.json"
        self.database = f"tentura_test_{self.scratch.name.lower()}"
        self.default_database = f"{self.database}_default"
        self.env = dict(os.environ)
        for name in ("CI", "GITHUB_ACTIONS", "TENTURA_PG_TESTS_REQUIRED"):
            self.env.pop(name, None)
        # Both the ordinary database setting and the test override point
        # away from dev, on the dedicated postgres-test instance.
        self.env.update(
            POSTGRES_HOST=TEST_POSTGRES_HOST,
            POSTGRES_PORT=TEST_POSTGRES_PORT,
            POSTGRES_USERNAME="postgres",
            POSTGRES_PASSWORD="password",
            POSTGRES_ADMIN_DBNAME="postgres",
            POSTGRES_DBNAME=self.default_database,
            TENTURA_POST_BUD_HASURA_PRIVACY_TEST_DB=self.database,
        )

    def without_docker(self):
        env = self.env.copy()
        env.pop("DOCKER_CONTEXT", None)
        env.pop("DOCKER_TLS_VERIFY", None)
        env["DOCKER_HOST"] = f"unix://{self.scratch / 'absent-docker.sock'}"
        return env

    def run_privacy(self, *, cwd=SERVER, env=None):
        return run(
            "dart", "test", "--tags", "pg",
            "--file-reporter", f"json:{self.report}", BUD_TEST,
            cwd=cwd, env=env or self.env, timeout=100,
        )

    def assert_privacy_passed(self, result):
        output = result_output(result)
        self.assertEqual(result.returncode, 0, output)
        self.assertTrue(self.report.is_file(), output)
        finishes = self.privacy_finishes(read_report(self.report))
        self.assertEqual(
            [(event["result"], event["skipped"], event["hidden"]) for event in finishes],
            [("success", False, False)],
            output,
        )

    def privacy_finishes(self, events):
        suites = {
            event["suite"]["id"] for event in events
            if event["type"] == "suite" and event["suite"]["path"].endswith(BUD_TEST)
        }
        tests = {
            event["test"]["id"] for event in events
            if event["type"] == "testStart"
            and event["test"]["suiteID"] in suites
            and event["test"]["name"] == PRIVACY_SCENARIO
        }
        return [
            event for event in events
            if event["type"] == "testDone" and event["testID"] in tests
        ]

    def plan(self, job, event, *, labels=""):
        diff = step(job, identifier="diff")["run"]
        expressions = {
            "github.event_name": event,
            "github.event.pull_request.number": "1",
            "github.event.pull_request.base.sha": "base",
            "github.repository": "owner/repo",
            "github.ref_name": "main",
        }
        for expression, value in expressions.items():
            diff = diff.replace("${{ " + expression + " }}", value)
        # Simulate the GitHub/remote Git inputs. Run the actual event logic,
        # change classifier, and matrix planner with those inputs.
        github_inputs = """
gh() {
  case "$1" in
    pr) printf '%s\n' "$PR_LABELS" ;;
    run) printf 'base\n' ;;
    *) return 1 ;;
  esac
}
git() {
  case "$1" in
    fetch) return 0 ;;
    diff) printf 'hasura/metadata.json\n' ;;
    *) return 1 ;;
  esac
}
"""
        output = self.scratch / "plan-output"
        scripts = self.scratch / "scripts"
        if not scripts.exists():
            scripts.symlink_to(REPO / "scripts")
        result = run(
            "bash", "-c", github_inputs + diff, cwd=self.scratch,
            env={**self.env, "GITHUB_OUTPUT": str(output), "PR_LABELS": labels},
        )
        self.assertEqual(result.returncode, 0, result_output(result))
        flags = dict(line.split("=", 1) for line in output.read_text().splitlines())
        output.unlink()
        planner = step(job, identifier="plan")
        result = run(
            "bash", "-c", planner["run"], env={
                **self.env,
                **{key: str(planner["env"][key]) for key in ("PG_SHARDS", "CLIENT_SHARDS")},
                "SERVER": flags["server"],
                "SERVER_CHANGED": flags["server_image"],
                "CLIENT": flags["client"],
                "WEB": flags["web"],
                "DEPLOY": flags["deploy"],
                "RUN_PG": flags["pg"],
                "CACHED_WEB": "",
                "IMAGE_FOUND": "",
                "GITHUB_OUTPUT": str(output),
            },
        )
        self.assertEqual(result.returncode, 0, result_output(result))
        flags = dict(line.split("=", 1) for line in output.read_text().splitlines())
        output.unlink()
        return flags["server"], json.loads(flags["shards"])

    def test_metadata_only_pg_shard_records_a_passing_bud_privacy_verdict(self):
        jobs = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))["jobs"]
        changes = jobs["changes"]
        mode, shards = self.plan(changes, "push")
        self.assertEqual(mode, "repo-files")
        pg_shards = [shard for shard in shards if shard["target"].startswith("pg-")]
        self.assertEqual([shard["target"] for shard in pg_shards], ["pg-1"])
        for event, labels, expect_pg in [
            ("pull_request", "", False),
            ("pull_request", "ci:full", True),
            ("workflow_dispatch", "", True),
        ]:
            _, planned = self.plan(changes, event, labels=labels)
            self.assertEqual(
                any(shard["target"].startswith("pg-") for shard in planned),
                expect_pg,
                event,
            )

        pg_shard = pg_shards[0]
        self.assertEqual(pg_shard["package"], "server")
        # Check both orders because the selector currently uses the last
        # --tag argument. The file must qualify for each tag independently.
        for tags in [("pg", "repo-files"), ("repo-files", "pg")]:
            selected = run(
                sys.executable, "../../scripts/ci_select_tests.py",
                "test", "--tag", tags[0], "--tag", tags[1], cwd=SERVER,
            )
            self.assertEqual(selected.returncode, 0, result_output(selected))
            self.assertIn(BUD_TEST, selected.stdout.splitlines(), tags)

        builder = step(
            jobs["test-shards"], name="Run ${{ matrix.target }} checks in builder container",
        )["run"]
        # Exercise the script sent into the builder. For this focused run,
        # dispatch only the bud test if the real shard selector scheduled it.
        # The test owns its migrated database, so no default DB migration runs.
        inner_script = builder.split("bash -c '", 1)[1].rsplit("'", 1)[0]
        inner_script = inner_script.replace(
            'git config --global --add safe.directory "*"', ':',
        ).replace("reports=/app/test-reports", 'reports="$BUD_REPORT_DIR"')
        focus = """
dart() {
  if [[ "$1" != test ]]; then
    return 0
  fi
  local arg
  local -a command=(test)
  local found=false
  shift
  for arg in "$@"; do
    case "$arg" in
      "$BUD_TEST") found=true; command+=("$arg") ;;
      test/*_test.dart) ;;
      *) command+=("$arg") ;;
    esac
  done
  if [[ "$found" == true ]]; then
    if [[ "${POSTGRES_HOST:-}:${POSTGRES_PORT:-}" != "$BUD_TEST_POSTGRES" ]]; then
      echo "Refusing to run the privacy test outside postgres-test" >&2
      return 1
    fi
    if [[ "${TENTURA_TEST_PG_POOL_SIZE:-}" != 1 ]]; then
      echo "The pg shard did not give the privacy test a one-connection pool" >&2
      return 1
    fi
    command dart "${command[@]}"
  fi
}
"""
        result = run(
            "bash", "-c", focus + inner_script, cwd=REPO,
            env={
                **self.without_docker(),
                # GitHub's host-network builder uses its runner's Postgres
                # on 5432. Locally, route to postgres-test on 5433 so the
                # same shard script cannot reach the default dev instance.
                "BUD_TEST_POSTGRES": f"{TEST_POSTGRES_HOST}:{TEST_POSTGRES_PORT}",
                "CI": "true",
                "GITHUB_ACTIONS": "true",
                "TEST_TARGET": "pg",
                "SHARD": pg_shard["shard"],
                "SHARD_NAME": pg_shard["target"],
                "SERVER_MODE": mode,
                "BUD_TEST": BUD_TEST,
                "BUD_REPORT_DIR": str(self.scratch),
            },
            timeout=100,
        )
        self.assert_privacy_passed(result)

    def test_required_pg_run_fails_with_the_missing_permission_source(self):
        checkout = self.overlay_checkout()
        env = self.without_docker() | {"TENTURA_PG_TESTS_REQUIRED": "1"}
        result = self.run_privacy(cwd=checkout, env=env)
        output = result_output(result)
        self.assertNotEqual(result.returncode, 0, output)
        self.assertTrue(self.report.is_file(), output)
        events = read_report(self.report)
        self.assertFalse(any(
            event["type"] == "testDone" and event["skipped"] for event in events
        ), output)
        errors = [event["error"] for event in events if event["type"] == "error"]
        self.assertRegex("\n".join(errors), MISSING_BACKEND, output)

    def overlay_checkout(self):
        """Give the test a scratch metadata path and reuse the built test sources."""
        checkout = self.scratch / "checkout"
        checkout.mkdir()
        for entry in REPO.iterdir():
            if entry.name not in {"hasura", "packages", ".git"}:
                (checkout / entry.name).symlink_to(entry)
        packages = checkout / "packages"
        packages.mkdir()
        for entry in SERVER.parent.iterdir():
            if entry != SERVER:
                (packages / entry.name).symlink_to(entry)
        server = packages / "server"
        server.mkdir()
        for entry in SERVER.iterdir():
            (server / entry.name).symlink_to(entry)
        return server

    def test_widening_repo_permissions_exposes_the_bud_to_carol(self):
        self.assert_privacy_passed(self.run_privacy())
        self.assert_fixture_cleaned_up()
        self.report.unlink()

        server = self.overlay_checkout()
        metadata = json.loads(METADATA.read_text(encoding="utf-8"))
        permission, = [
            rule["permission"]
            for source in metadata["metadata"]["sources"]
            for table in source["tables"]
            if table["table"] == {"schema": "public", "name": "beacon"}
            for rule in table["select_permissions"]
            if rule["role"] == "user"
        ]
        self.assertNotEqual(permission["filter"], {})
        permission["filter"] = {}
        metadata_path = server.parents[1] / "hasura" / "metadata.json"
        metadata_path.parent.mkdir()
        metadata_path.write_text(json.dumps(metadata), encoding="utf-8")

        result = self.run_privacy(cwd=server)
        output = result_output(result)
        self.assertNotEqual(result.returncode, 0, output)
        self.assertTrue(self.report.is_file(), output)
        events = read_report(self.report)
        finishes = self.privacy_finishes(events)
        self.assertEqual(
            [(event["result"], event["skipped"]) for event in finishes],
            [("failure", False)],
            output,
        )
        self.assert_fixture_cleaned_up()
        self.assertTrue(
            any(
                event["type"] == "error"
                and event["testID"] == finishes[0]["testID"]
                and CAROL_BUD_ASSERTION in event["error"]
                for event in events
            ),
            output,
        )

    def sql(self, database, query):
        result = run(
            "docker", "exec", "postgres-test", "psql", "-X", "-U", "postgres",
            "-d", database, "-Atc", query,
        )
        self.assertEqual(result.returncode, 0, result_output(result))
        return result.stdout.splitlines()

    def assert_fixture_cleaned_up(self):
        databases = self.sql(
            "postgres",
            "SELECT datname FROM pg_database "
            f"WHERE datname IN ('{self.database}', '{self.default_database}')",
        )
        self.assertNotIn(self.default_database, databases)
        if self.database in databases:
            self.assertEqual(
                self.sql(
                    self.database,
                    "SELECT id FROM public.beacon WHERE id = 'BbudprivacyP0' "
                    """UNION ALL SELECT id FROM public."user" """
                    "WHERE id IN ('UbudprivacyA', 'UbudprivacyB', 'UbudprivacyC', 'UbudprivacyH')",
                ),
                [],
                f"Leaked fixture rows in {self.database}",
            )


if __name__ == "__main__":
    unittest.main()
