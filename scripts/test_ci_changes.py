import unittest

from ci_changes import ci_inputs, classify, pipeline_scripts

CI_SCRIPTS = {"scripts/check-custom-lints.sh"}


def plan_of(*paths):
    return dict(line.split("=", 1) for line in classify(list(paths), CI_SCRIPTS).lines())


EVERYTHING = {
    "server": "full",
    "client": "full",
    "web": "true",
    "server_image": "true",
    "deploy": "true",
}
NOTHING = {
    "server": "skip",
    "client": "skip",
    "web": "false",
    "server_image": "false",
    "deploy": "false",
}


class CiChangesTest(unittest.TestCase):
    def test_agent_docs_run_nothing_but_lints(self):
        self.assertEqual(
            plan_of("AGENTS.md", ".cursor/rules/x.mdc", ".claude/skills/a/SKILL.md"),
            NOTHING,
        )

    def test_server_change_runs_server_and_client_repo_file_tests(self):
        self.assertEqual(
            plan_of("packages/server/lib/a.dart"),
            {**NOTHING, "server": "full", "client": "repo-files",
             "server_image": "true", "deploy": "true"},
        )

    def test_client_change_runs_client_and_server_repo_file_tests(self):
        self.assertEqual(
            plan_of("packages/client/lib/a.dart"),
            {**NOTHING, "client": "full", "server": "repo-files",
             "web": "true", "deploy": "true"},
        )

    def test_vendored_client_package_counts_as_client(self):
        self.assertEqual(plan_of("packages/web_socket_client/lib/a.dart")["client"], "full")

    def test_docs_reach_tests_that_read_them(self):
        # Tests read docs/contracts/*.json and docs/plans journals.
        self.assertEqual(
            plan_of("docs/contracts/updates-event-contract.json"),
            {**NOTHING, "server": "repo-files", "client": "repo-files"},
        )

    def test_full_beats_repo_files_whichever_comes_first(self):
        plan = plan_of("docs/a.md", "packages/server/lib/a.dart", "docs/b.md")
        self.assertEqual(plan["server"], "full")

    def test_build_inputs_and_ci_run_everything(self):
        for path in (
            "pubspec.lock",
            "pubspec.yaml",
            "pubspec_overrides.yaml",
            "analysis_options.yaml",
            "lib/consts.dart",
            ".github/workflows/pipeline.yml",
            ".github/actions/setup-ssh/action.yml",
            "Dockerfile.builder",
            "packages/tentura_lints/lib/src/rule.dart",
            "scripts/check-custom-lints.sh",
        ):
            with self.subTest(path=path):
                self.assertEqual(plan_of(path), EVERYTHING)

    def test_script_outside_the_pipeline_only_reaches_repo_file_tests(self):
        self.assertEqual(
            plan_of("scripts/seed_society/run.py"),
            {**NOTHING, "server": "repo-files", "client": "repo-files"},
        )

    def test_deploy_assets_deploy_without_rebuilding(self):
        for path in ("hasura/metadata.json", "deploy.sh", "compose.prod.yaml"):
            with self.subTest(path=path):
                plan = plan_of(path)
                self.assertEqual(plan["deploy"], "true")
                self.assertEqual(plan["web"], "false")
                self.assertEqual(plan["server_image"], "false")

    def test_landing_rebuilds_web_archive(self):
        plan = plan_of("packages/landing/main.js")
        self.assertEqual((plan["web"], plan["deploy"]), ("true", "true"))

    def test_unknown_path_is_treated_as_outside_both_packages(self):
        self.assertEqual(
            plan_of("brand-new-dir/thing.txt"),
            {**NOTHING, "server": "repo-files", "client": "repo-files"},
        )

    def test_empty_change_set_runs_nothing(self):
        self.assertEqual(plan_of(), NOTHING)

    def test_pipeline_scripts_are_read_from_the_workflow(self):
        scripts = pipeline_scripts()
        self.assertIn("scripts/ci_changes.py", scripts)
        # Reached only through check-analysis.sh, and the baselines they read.
        self.assertIn("scripts/check-custom-lints.sh", scripts)
        self.assertIn("scripts/check-analyze-baseline.sh", scripts)
        self.assertIn("scripts/custom-lint-baseline.txt", scripts)
        self.assertIn("scripts/analyze-baseline.txt", scripts)
        # Dev-only tooling stays out. (Spelled in two halves: this file is
        # CI-run, so naming it whole would pull it into the closure.)
        self.assertNotIn("scripts/migrate_terminology" + "_arb.py", scripts)

    def test_ci_inputs_cover_the_recipe(self):
        inputs = ci_inputs()
        for path in (
            ".github/workflows/pipeline.yml",
            "Dockerfile.builder",
            "scripts/resolve_deploy_web_config.sh",
            "scripts/check-custom-lints.sh",
            "scripts/lib",
        ):
            self.assertIn(path, inputs)


if __name__ == "__main__":
    unittest.main()
