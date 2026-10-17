#!/usr/bin/env python3
"""Decide which Pipeline jobs a set of changed files needs.

Reads changed paths (one per line, repo-relative) on stdin and prints
`key=value` lines for `$GITHUB_OUTPUT`:

  server        full | repo-files | skip   server + pg shards, analyzer gate
  client        full | repo-files | skip   client-a/client-b, analyzer gate
  web           true | false               build-web (wasm app + landing)
  server_image  true | false               build-server (server image push)
  deploy        true | false               deploy-dev

`full` runs the package's whole selection. `repo-files` runs only the tests
tagged `repo-files`: the ones that read files outside their own package
(docs/contracts, scripts, workflows, hasura metadata, the other package). They
must run whenever anything outside their package changes, even when the
package itself did not.

The lints shard is cheap and always runs, so it has no key.

When a path is not recognised it lands in the "outside both packages" bucket:
both packages run their `repo-files` tests. Anything that feeds the build
itself (workspace pubspecs, root `lib/`, CI scripts, workflows, the builder
image, the custom lint plugin) runs everything.

`--all` prints the run-everything answer (manual dispatch, unknown base).
`--ci-inputs` lists the paths that make up the build recipe (workflow,
composite actions, builder image, CI scripts): artifact keys hash them along
with the sources, so an artifact built by a different recipe is never reused.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PIPELINE = REPO_ROOT / ".github" / "workflows" / "pipeline.yml"

# Agent/editor configuration and prose no test reads. Only the lints shard
# (doc drift, terminology) looks at these. `docs/` is deliberately NOT here:
# tests read docs/contracts/*.json and some docs/plans journals.
AGENT_ONLY = re.compile(
    r"^("
    r"[^/]+\.md"  # root-level markdown: AGENTS.md, CONTEXT.md, README.md, ...
    r"|\.(agents|claude|codex|cursor|serena|beads|vscode)/.*"
    r"|\.claudeignore|\.mcp\.json|skills-lock\.json"
    r"|LICENSE|NOTICE|LICENSES/.*"
    r"|rag_[^/]*"
    r")$"
)

# Feeds compilation, codegen or the CI machinery of every job.
GLOBAL = re.compile(
    r"^("
    r"pubspec\.yaml|pubspec\.lock|pubspec_overrides\.yaml|analysis_options\.yaml"
    r"|lib/.*"  # tentura_root, imported by both packages
    r"|\.github/.*"
    r"|Dockerfile\.builder"
    r"|packages/tentura_lints/.*"
    r"|scripts/lib/.*"
    r")$"
)

CLIENT_VENDORED = re.compile(
    r"^packages/(ferry_generator|force_directed_graphview|image_cropper_for_web"
    r"|web_socket_client)/"
)

# Shipped to the VPS by .github/actions/deploy-web-archive.
DEPLOY_ASSETS = re.compile(
    r"^(hasura/.*|deploy\.sh|compose\.prod\.yaml|scripts/hasura_apply_metadata\.sh)$"
)


def pipeline_scripts() -> set[str]:
    """Files under scripts/ that CI runs or reads: changing one changes CI.

    The scripts the Pipeline workflow names, plus — transitively — every file
    in scripts/ one of them mentions by name (check-analysis.sh runs
    check-custom-lints.sh, which reads custom-lint-baseline.txt, ...).
    """
    try:
        text = PIPELINE.read_text(encoding="utf-8")
    except OSError:
        return set()
    scripts_dir = REPO_ROOT / "scripts"
    names = {f.name for f in scripts_dir.iterdir() if f.is_file()}
    found = {m.split("/", 1)[1] for m in re.findall(r"scripts/[A-Za-z0-9_.-]+", text)}
    found &= names
    pending = list(found)
    while pending:
        source = (scripts_dir / pending.pop()).read_text(encoding="utf-8", errors="replace")
        for name in names - found:
            if re.search(rf"(?<![A-Za-z0-9_.-]){re.escape(name)}(?![A-Za-z0-9_.-])", source):
                found.add(name)
                pending.append(name)
    return {f"scripts/{name}" for name in found}


LEVEL = {"skip": 0, "repo-files": 1, "full": 2}


class Plan:
    def __init__(self) -> None:
        self.server = "skip"
        self.client = "skip"
        self.web = False
        self.server_image = False
        self.deploy = False

    def bump(self, attr: str, level: str) -> None:
        if LEVEL[level] > LEVEL[getattr(self, attr)]:
            setattr(self, attr, level)

    def everything(self) -> None:
        self.server = self.client = "full"
        self.web = self.server_image = self.deploy = True

    def lines(self) -> list[str]:
        return [
            f"server={self.server}",
            f"client={self.client}",
            f"web={str(self.web).lower()}",
            f"server_image={str(self.server_image).lower()}",
            f"deploy={str(self.deploy).lower()}",
        ]


def classify(paths: list[str], ci_scripts: set[str] | None = None) -> Plan:
    if ci_scripts is None:
        ci_scripts = pipeline_scripts()
    plan = Plan()
    for raw in paths:
        path = raw.strip()
        if not path:
            continue
        if AGENT_ONLY.match(path):
            continue
        if GLOBAL.match(path) or path in ci_scripts:
            plan.everything()
            continue
        if path.startswith("packages/server/"):
            plan.bump("server", "full")
            plan.bump("client", "repo-files")
            plan.server_image = plan.deploy = True
            continue
        if path.startswith("packages/client/") or CLIENT_VENDORED.match(path):
            plan.bump("client", "full")
            plan.bump("server", "repo-files")
            plan.web = plan.deploy = True
            continue
        # Outside both packages: docs, other scripts, hasura, compose, landing,
        # anything new. Only tests that read such files can notice.
        plan.bump("server", "repo-files")
        plan.bump("client", "repo-files")
        if path.startswith("packages/landing/"):
            plan.web = plan.deploy = True
        if DEPLOY_ASSETS.match(path):
            plan.deploy = True
    return plan


def ci_inputs() -> list[str]:
    """Repo paths that make up the build recipe itself, for artifact keys."""
    return sorted(
        {
            ".github/workflows/pipeline.yml",
            ".github/actions",
            "Dockerfile.builder",
            # Sourced helpers (e.g. web_config_urls.sh); GLOBAL in classify.
            "scripts/lib",
        }
        | pipeline_scripts()
    )


def main(argv: list[str]) -> int:
    if "--ci-inputs" in argv:
        print("\n".join(ci_inputs()))
        return 0
    if "--all" in argv:
        plan = Plan()
        plan.everything()
    else:
        plan = classify(sys.stdin.read().splitlines())
    print("\n".join(plan.lines()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
