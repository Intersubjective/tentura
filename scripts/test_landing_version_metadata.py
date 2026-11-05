"""Exercise release metadata changes through the real lander's CLI.

Git, GitHub, sleeps and HTTP are shell functions supplied by BASH_ENV. The
actual script, including its sed commands, runs unchanged. Its hard-coded cd
destinations are redirected to disposable directories, so no checkout,
worktree, commit, push, merge or deployment is performed.
"""

import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent


class LandingVersionMetadataTest(unittest.TestCase):
    def test_release_bump_preserves_the_source_bootstrap_placeholder(self):
        configured = os.environ.get("TENTURA_LAND_PR_SCRIPT")
        canonical = ROOT.parent / "jules-ctl/land_pr.sh"
        lander = Path(configured) if configured else canonical
        self.assertTrue(
            lander.is_file(),
            "The required external lander is unavailable; provision the maintained "
            "jules-ctl/land_pr.sh or set TENTURA_LAND_PR_SCRIPT. This check cannot skip.",
        )
        entry_points = [lander]
        if canonical.is_file():
            self.assertTrue(lander.samefile(canonical),
                            "Test the maintained Jules lander, not a fixture copy")
            if canonical != lander:
                entry_points.append(canonical)
        manager = ROOT.parent / "manager-ctl/land_pr.sh"
        if manager.is_file():
            self.assertTrue(lander.samefile(manager),
                            "The Jules and manager paths must name the same maintained lander")
            if manager not in entry_points:
                entry_points.append(manager)
        for entry_point in entry_points:
            with self.subTest(entry_point=str(entry_point)):
                self.assert_release_bump_preserves_source(entry_point)

    def assert_release_bump_preserves_source(self, lander):
        with tempfile.TemporaryDirectory(prefix="landing-version-") as scratch:
            work = Path(scratch)
            main = work / "main"
            branch = work / "branch"
            original = (
                '<!doctype html>\n'
                '<script src="flutter_bootstrap.js?v=0.0.0-dev" async=""></script>\n'
            )
            for checkout in (main, branch):
                client = checkout / "packages/client"
                (client / "web").mkdir(parents=True)
                (client / "pubspec.yaml").write_text("name: tentura\nversion: 12.34.5\n")
                (client / "web/index.html").write_text(original)

            shell_environment = work / "land-test-env.sh"
            shell_environment.write_text(textwrap.dedent(r"""
                LANDER_TEST_SOURCE_ROOT=
                cd() {
                  # The first cd names the maintained script's configured main
                  # checkout. Learn that logical path without accessing it, so
                  # the same harness works outside the maintainer's machine.
                  if [[ -z "$LANDER_TEST_SOURCE_ROOT" ]]; then
                    LANDER_TEST_SOURCE_ROOT=$1
                  fi
                  case "$1" in
                    "$LANDER_TEST_SOURCE_ROOT") builtin cd "$LANDER_TEST_MAIN" ;;
                    "$LANDER_TEST_SOURCE_ROOT/../tentura-land-4242") builtin cd "$LANDER_TEST_BRANCH" ;;
                    *) printf 'Unexpected checkout: %s\n' "$1" >&2; return 97 ;;
                  esac
                }
                function /usr/bin/git() {
                  printf '%s\n' "$*" >> "$LANDER_TEST_GIT_LOG"
                  case "$1" in
                    show) cat "$LANDER_TEST_MAIN/packages/client/pubspec.yaml" ;;
                    diff) [[ "$2" != --quiet ]] ;;
                    worktree|fetch|merge|commit|push|branch|checkout|add) return 0 ;;
                    *) printf 'Unexpected git command: %s\n' "$*" >&2; return 97 ;;
                  esac
                }
                git() { /usr/bin/git "$@"; }
                gh() {
                  case "$*" in
                    'pr checks '*) printf 'PR checks\tpass\n' ;;
                    *headRefName*) printf 'fixture-branch\n' ;;
                    *mergeCommit*) printf 'abcdef1234567890\n' ;;
                    'pr merge '*) return 0 ;;
                    *) printf 'Unexpected GitHub command: %s\n' "$*" >&2; return 97 ;;
                  esac
                }
                sleep() { :; }
                curl() {
                  local version
                  version=$(sed -n 's/^version: //p' "$LANDER_TEST_BRANCH/packages/client/pubspec.yaml")
                  printf '{"version":"%s"}\n' "$version"
                }
            """))
            git_log = work / "git.log"
            env = {
                **os.environ,
                "BASH_ENV": str(shell_environment),
                "LANDER_TEST_MAIN": str(main),
                "LANDER_TEST_BRANCH": str(branch),
                "LANDER_TEST_GIT_LOG": str(git_log),
            }
            result = subprocess.run(
                ["bash", str(lander), "4242", "Preserve source release metadata"],
                cwd=work, env=env, capture_output=True, text=True, timeout=20,
            )
            transcript = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, transcript)
            self.assertIn("bumped: 12.34.5 -> 12.34.6", result.stdout)
            self.assertIn("deployed: 12.34.6", result.stdout)
            self.assertIn(
                "version: 12.34.6\n",
                (branch / "packages/client/pubspec.yaml").read_text(),
            )
            self.assertIn("push -q origin HEAD:fixture-branch", git_log.read_text())
            self.assertEqual(
                (branch / "packages/client/web/index.html").read_text(),
                original,
                "A landing must bump pubspec without rewriting the source bootstrap placeholder",
            )


if __name__ == "__main__":
    unittest.main()
