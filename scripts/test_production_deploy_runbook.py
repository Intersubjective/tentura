"""Check the manual instructions against the real deploy CLI boundary."""

import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
CHECK_SCRIPT = "hasura_check_metadata.sh"
MIGRATION = r"\bmigrat(?:e[sd]?|ing|ions?)\b"
NUMBERED_STEP = re.compile(r"^( {0,3})([0-9]+)[.)][ \t]+(.*)$", re.MULTILINE)
FAILURE = r"\b(?:fail(?:s|ed|ure|ures)?|break(?:s)?|errors?|inconsistent|cannot)\b"
OLD = r"\b(?:old(?:er)?|previous|pre[- ]m032[01]|outdated|prior)\b"
APPLY = r"\b(?:appl(?:y|ies|ied|ying|ication)|runs?|executes?)\b"
LINEAGE = r"(?<!stored_)lineage_(?:parent|root)_beacon_id|\bold (?:column|lineage)"
WRITE = r"\b(?:writ\w+|insert\w+|updat\w+)\b"
READ = r"\b(?:read\w*|quer(?:y|ies|ying)|select\w*)\b"
CHECK_COMMAND = r"(?:/opt/tentura/)?scripts/" + re.escape(CHECK_SCRIPT)


def paragraphs(markdown):
    return [
        " ".join(part.replace("`", "").replace("**", "").split())
        for part in re.split(r"\n\s*\n", markdown)
        if part.strip()
    ]


def heading_slug(heading):
    return re.sub(r"[^\w -]", "", heading.lower()).replace(" ", "-")


def numbered_steps(section):
    first = NUMBERED_STEP.search(section)
    if first is None:
        return []
    indent = first[1]
    steps = []
    for line in section[first.start():].splitlines():
        step = NUMBERED_STEP.fullmatch(line)
        if step and step[1] == indent:
            steps.append((int(step[2]), [step[3]]))
        elif line.strip():
            if not line.startswith(indent + " "):
                break
            steps[-1][1].append(line.strip())
    return [(number, " ".join(lines)) for number, lines in steps]


def markdown_sections(markdown):
    # Commands in fenced code blocks can start with '#'; those aren't headings.
    prose = re.sub(
        r"(?ms)^ *```[^\n]*\n.*?^ *```[^\n]*",
        lambda match: re.sub(r"[^\n]", " ", match[0]),
        markdown,
    )
    headings = list(re.finditer(r"(?m)^(#{1,6}) +(.+)$", prose))
    for i, heading in enumerate(headings):
        end = next(
            (h.start() for h in headings[i + 1:] if len(h[1]) <= len(heading[1])),
            len(prose),
        )
        yield heading[2], prose[heading.end():end], markdown[heading.end():end]


def deploy_events():
    with tempfile.TemporaryDirectory(prefix="deploy-runbook-") as tmp:
        work = Path(tmp)
        for directory in ("bin", "hasura", "scripts", "bundle/app-assets/release"):
            (work / directory).mkdir(parents=True, exist_ok=True)
        for name in ("index.html", "flutter_bootstrap.js"):
            (work / "bundle" / name).write_text("/app-assets/release/")
        (work / "bundle/app-assets/release/asset").touch()
        archive = work / "build.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            for entry in (work / "bundle").iterdir():
                tar.add(entry, arcname=entry.name)

        (work / ".env").write_text("HASURA_GRAPHQL_ADMIN_SECRET=fixture-secret\n")
        (work / "compose.yaml").write_text("services: {}\n")
        for relative in ("hasura/metadata.json", "scripts/hasura_apply_metadata.sh"):
            (work / relative).symlink_to(ROOT / relative)

        docker = work / "bin/docker"
        docker.write_text(textwrap.dedent("""\
            #!/usr/bin/env bash
            set -eu
            case "$1" in
              compose)
                shift
                while [[ "$1" == -f ]]; do shift 2; done
                case "$1" in
                  down) echo stop-old >>"$DEPLOY_EVENTS" ;;
                  up)
                    [[ " $* " == *' --wait '* ]]
                    echo wait-for-new >>"$DEPLOY_EVENTS" ;;
                  ps)
                    if [[ "${2:-}" == -q ]]; then
                      echo fixture-hasura
                    else
                      echo deployment-complete >>"$DEPLOY_EVENTS"
                    fi ;;
                  pull) ;;
                  *) exit 2 ;;
                esac ;;
              inspect) echo fixture_backend ;;
              pull|image) ;;
              run)
                [[ " $* " == *' /apply.sh '* ]]
                [[ " $* " == *" $DEPLOY_DIR/scripts/hasura_apply_metadata.sh:/apply.sh:ro "* ]]
                [[ " $* " == *" $DEPLOY_DIR/hasura/metadata.json:/data/metadata.json:ro "* ]]
                echo apply-metadata >>"$DEPLOY_EVENTS" ;;
              *) exit 2 ;;
            esac
            """))
        docker.chmod(0o755)
        events = work / "events"
        env = {
            **os.environ,
            "PATH": f"{docker.parent}:{os.environ['PATH']}",
            "DEPLOY_DIR": str(work),
            "WEB_DIR": "./web",
            "LANDING_DIR": "./landing",
            "LANDING_ARCHIVE": str(work / "no-landing.tar.gz"),
            "COMPOSE_FILE": "compose.yaml",
            "OVERRIDE_FILE": "no-override.yaml",
            "DEPLOY_EVENTS": str(events),
            "APP_ASSETS_KEEP": "20",
        }
        result = subprocess.run(
            ["bash", ROOT / "deploy.sh", archive],
            env=env, capture_output=True, text=True, timeout=20,
        )
        return result, events.read_text().splitlines() if events.exists() else []


class ProductionDeployRunbookTest(unittest.TestCase):
    def window_section(self):
        sections = list(markdown_sections(
            (ROOT / "docs/production-deploy.md").read_text(encoding="utf-8")
        ))
        operations = [
            (title, body) for title, body, _ in sections if re.match(r"[67]\.", title)
        ]
        # Match the smallest section first so a sibling subsection cannot
        # accidentally satisfy requirements for the cutover procedure.
        for title, body, raw in sorted(sections, key=lambda entry: len(entry[1])):
            describes_cutover = re.search(
                r"deploy(?:ment)? (?:order|sequence)|mixed[- ]version|\bm032[01]\b",
                f"{title}\n{body}", re.IGNORECASE,
            )
            if describes_cutover and NUMBERED_STEP.search(body):
                anchor = f"](#{heading_slug(title)})"
                if any(body in entry or anchor in entry for _, entry in operations):
                    return body, raw
        self.fail("§6 or §7 must lead operators to the numbered mixed-version deploy procedure")

    def assert_passage(self, section, description, *patterns):
        self.assertTrue(
            any(all(re.search(pattern, part, re.I) for pattern in patterns)
                for part in paragraphs(section)),
            description,
        )

    def test_numbered_operator_steps_match_deploy_order(self):
        result, observed = deploy_events()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        expected = ["stop-old", "wait-for-new", "apply-metadata", "deployment-complete"]
        self.assertEqual(observed, expected)

        section, _ = self.window_section()
        steps = numbered_steps(section)
        self.assertEqual([number for number, _ in steps], [1, 2, 3], steps)
        actions = {
            "wait-for-new": (
                r"\b(?:new|updated|replacement)\b.{0,45}\b(?:server|tentura|container)\b",
                r"\b(?:starts?|starting|startup|boots?|launch(?:es)?)\b",
                APPLY + r".{0,80}\b(?:pending|outstanding)\b.{0,35}" + MIGRATION
                + r"|\b(?:pending|outstanding)\b.{0,35}" + MIGRATION + r".{0,65}" + APPLY,
            ),
            "apply-metadata": (APPLY, r"hasura/metadata\.json", r"hasura_apply_metadata\.sh"),
            "deployment-complete": (
                r"\b(?:serv\w+|resum\w+|accept\w+|route\w+)\b",
                r"\b(?:traffic|requests)\b",
                r"\b(?:new|updated|replacement)\b.{0,25}\b(?:version|release|stack|server)\b",
            ),
        }
        for action, (number, step) in zip(observed[1:], steps):
            clean_step = step.replace("`", "").replace("**", "")
            with self.subTest(step=number, deploy_event=action):
                for pattern in actions[action]:
                    self.assertRegex(clean_step, re.compile(pattern, re.I))

    def test_runbook_identifies_the_retired_schema_and_lineage_replacements(self):
        section, _ = self.window_section()
        for migration, identifiers in (
            ("m0320", [r"beacon_bud_observer"]),
            ("m0321", [
                r"(?<!stored_)lineage_parent_beacon_id",
                r"(?<!stored_)lineage_root_beacon_id",
                r"stored_lineage_(?:parent_beacon_id|\*)",
                r"stored_lineage_(?:root_beacon_id|\*)",
                r"beacon_get_lineage_(?:parent_beacon_id|\*_beacon_id)",
                r"beacon_get_lineage_(?:root_beacon_id|\*_beacon_id)",
            ]),
        ):
            with self.subTest(migration=migration):
                self.assertIn(migration, section)
                for identifier in identifiers:
                    self.assertRegex(section, identifier)

    def test_runbook_explains_why_old_servers_cannot_write_the_dropped_observer_table(self):
        section, _ = self.window_section()
        self.assert_passage(
            section,
            "Explain that pre-m0320 server writes to beacon_bud_observer fail once m0320 runs.",
            r"\bm0320\b.{0,60}\b(?:drops?|dropped|removes?|removed)\b"
            r"|\b(?:drops?|dropped|removes?|removed)\b.{0,60}\bm0320\b",
            r"\b(?:before|pre[- ]|older than|predat\w+)\s*m0320\b",
            r"\bservers?\b", r"\bbeacon_bud_observer\b",
            FAILURE + r"[^.!?]{0,90}" + WRITE + "|" + WRITE + r"[^.!?]{0,100}" + FAILURE,
            r"\b(?:after|once|when)\b.{0,85}\b(?:m0320|migration|drop\w+|runs?|applied)\b",
        )

    def test_runbook_explains_which_lineage_reads_and_metadata_fail_during_cutover(self):
        section, _ = self.window_section()
        self.assert_passage(
            section,
            "Explain that m0321 renames the physical lineage columns and adds computed fields.",
            r"\bm0321\b", r"\brenam\w+\b", LINEAGE, r"stored_lineage_",
            r"\b(?:adds?|introduc\w+|creat\w+)\b.{0,105}\bcomputed fields\b",
        )
        self.assert_passage(
            section,
            "Explain that old servers reading the former lineage columns fail after m0321.",
            OLD, r"\bservers?\b", LINEAGE,
            FAILURE + r"[^.!?]{0,90}" + READ + "|" + READ + r"[^.!?]{0,100}" + FAILURE,
            r"\b(?:after|once|when|between|until)\b.{0,100}\b(?:m0321|migration|metadata|rename\w*)\b",
        )
        self.assert_passage(
            section,
            "Explain that Hasura with pre-m0321 metadata fails until the new metadata is applied.",
            r"\bHasura\b[^.!?]{0,110}" + FAILURE + "|" + FAILURE + r"[^.!?]{0,80}\bHasura\b",
            r"(?:pre[- ]m0321|old|previous|stale)\b.{0,55}\bmetadata\b"
            r"|\bmetadata\b.{0,45}\b(?:from before|pre[- ]m0321)\b",
            r"\b(?:until|before|between)\b.{0,140}(?:metadata.{0,50}" + APPLY
            + "|" + APPLY + r".{0,50}metadata)",
        )

    def test_runbook_requires_one_server_per_host_without_rolling_overlap(self):
        section, _ = self.window_section()
        self.assert_passage(
            section,
            "Require one Tentura server instance per host.",
            r"\b(?:one|single|1)\b.{0,50}\b(?:server|instance|container)\b.{0,30}\b(?:per|on each)\s+host\b",
        )
        self.assert_passage(
            section,
            "Forbid rolling and side-by-side deployments of two server versions on the same database.",
            r"\b(?:no|never|do not|must not|forbid\w*|prohibit\w*|unsupported)\b",
            r"\brolling\b", r"\bside[- ]by[- ]side\b|\bparallel\b",
            r"\b(?:same|shared)\s+(?:database|db)\b",
        )

    def test_runbook_bounds_the_window_from_migration_to_metadata_apply(self):
        section, _ = self.window_section()
        self.assert_passage(
            section,
            "State that the old container stops before the replacement migrates.",
            r"\b(?:old|previous)\b.{0,45}\b(?:container|server)\b",
            r"\b(?:stops?|stopped|shut\w* down)\b.{0,85}\bbefore\b.{0,75}" + MIGRATION
            + r"|\bbefore\b.{0,75}" + MIGRATION + r".{0,85}\b(?:stops?|stopped|shut\w* down)\b",
            r"\b(?:new|replacement)\b",
        )
        self.assert_passage(
            section,
            "Describe the window as seconds on the single dev/prod host, from migration until metadata apply.",
            r"\bseconds\b", r"\b(?:dev|development)\b", r"\bprod(?:uction)?\b",
            r"\b(?:from|between|after|once)\b.{0,100}" + MIGRATION
            + r".{0,120}\b(?:to|and|until|before)\b.{0,70}"
            + r"(?:metadata.{0,45}" + APPLY + "|" + APPLY + r".{0,45}metadata)",
        )

    def test_runbook_says_old_servers_and_clients_must_upgrade_without_a_shim(self):
        section, _ = self.window_section()
        self.assert_passage(
            section,
            "State that old servers and old clients have no compatibility shim.",
            r"\b(?:no|without)\b.{0,35}\b(?:compatibility|shim)\b"
            r"|\bcompatibility\b.{0,35}\b(?:not provided|not supported|removed)\b",
            OLD + r"|\blegacy\b", r"\bservers?\b", r"\bclients?\b",
        )
        self.assert_passage(
            section,
            "Warn that versions older than the release fail until upgraded.",
            OLD + r"|\blegacy\b",
            r"\b(?:release|versions?|clients?|servers?)\b",
            FAILURE + r".{0,90}\buntil\b.{0,55}\b(?:updat\w+|upgrad\w+)\b",
        )

    def test_runbook_gives_operators_the_recovery_commands_in_order(self):
        _, raw = self.window_section()
        self.assertRegex(
            raw,
            r"(?is)\bmetadata\b.{0,100}\b(?:fail\w*|skipp\w*|miss\w*)\b"
            r".*?\bbash +/opt/tentura/scripts/hasura_apply_metadata\.sh\b"
            r".*?" + CHECK_COMMAND,
            f"Recovery must rerun the internal metadata apply command, then scripts/{CHECK_SCRIPT}",
        )

    def test_runbook_requires_consistency_check_after_every_migrating_deploy(self):
        _, raw = self.window_section()
        self.assert_passage(
            re.sub(r":\n[ \t]*\n(?=[ \t]*```)", ":\n", raw),
            "Tell operators to run the consistency check after every deploy that includes a migration.",
            r"\b(?:run|execute)\b",
            CHECK_COMMAND,
            r"\bafter\s+(?:each|every|any|all)\b.{0,85}\bdeploy\w*\b.{0,75}" + MIGRATION
            + r"|\b(?:each|every|any|all)\b.{0,65}\bdeploy\w*\b.{0,75}" + MIGRATION
            + r".{0,70}\b(?:finish\w*|complet\w*|afterwards|afterward)\b",
        )


if __name__ == "__main__":
    unittest.main()
