"""Task queue for Composer Autopilot (project-improvement menu)."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from schemas import WorkUnit

DTO_IGNORE = "ignore: tentura_lints/no_map_dynamic_in_use_case_api"


@dataclass(frozen=True)
class AutopilotTask:
    unit: WorkUnit
    packages: list[str]
    default_enabled: bool = True
    test_scope: str | None = None
    diff_must_be_under: tuple[str, ...] | None = None
    skip_machine_gates: bool = False


def _dto_subtasks(repo: Path) -> list[AutopilotTask]:
    tasks: list[AutopilotTask] = []
    server_root = repo / "packages/server/lib"
    for path in sorted(server_root.rglob("*.dart")):
        text = path.read_text(encoding="utf-8")
        if DTO_IGNORE not in text:
            continue
        rel = path.relative_to(repo).as_posix()
        task_id = f"dto-{path.stem.replace('_', '-')}"
        tasks.append(
            AutopilotTask(
                unit=WorkUnit(
                    id=task_id,
                    intent=(
                        f"Phase-2 DTO migration for {rel}: replace Map<String, dynamic> "
                        f"public use-case APIs with typed domain DTOs mapped at the GraphQL "
                        f"resolver boundary. Remove the // ignore: tentura_lints/no_map_dynamic "
                        f"baseline and its TODO(contract) comment."
                    ),
                    write_set=[rel],
                    read_set=[
                        "packages/server/lib/domain/port/",
                        "packages/server/lib/api/",
                    ],
                    constraints=[
                        "Do not add new // ignore: tentura_lints baselines.",
                        "Keep domain layer free of data/ui imports.",
                        "Run dart analyze --no-fatal-warnings in packages/server.",
                    ],
                    success_criteria=[
                        f"No {DTO_IGNORE} in {rel}",
                        "packages/server dart analyze passes",
                        "packages/server dart test passes",
                    ],
                    depends_on=["coord-phase-a"],
                ),
                packages=["server"],
                test_scope="test/domain/",
            )
        )
    return tasks


def build_task_queue(repo: Path) -> list[AutopilotTask]:
    base: list[AutopilotTask] = [
        AutopilotTask(
            unit=WorkUnit(
                id="test-backfill",
                intent=(
                    "Add additive unit/widget tests for under-tested Tentura areas. "
                    "Only create or extend files under test/ directories. Do not change "
                    "production lib/ code except tiny test-only exports if absolutely required."
                ),
                write_set=[
                    "packages/client/test/",
                    "packages/server/test/",
                ],
                read_set=[
                    "packages/client/lib/",
                    "packages/server/lib/",
                    "DEV_GUIDELINES.md",
                ],
                constraints=[
                    "Only touch paths under test/ (client or server).",
                    "Do not modify golden PNG files unless fixing an existing broken golden.",
                ],
                success_criteria=[
                    "New or extended tests pass",
                    "git diff touches only test/ paths",
                ],
            ),
            packages=["client", "server"],
            test_scope=None,
            diff_must_be_under=("packages/client/test/", "packages/server/test/"),
        ),
        AutopilotTask(
            unit=WorkUnit(
                id="coord-phase-a",
                intent=(
                    "Coordination Phase A: extract pure coordination_status_rules from "
                    "CoordinationRepository.recomputeAndPersistBeaconCoordinationStatus into "
                    "packages/server/lib/domain/coordination/coordination_status_rules.dart "
                    "with unit tests mirroring evaluation_visibility_rules_test.dart. "
                    "Document staleness behavior vs docs/over-offer-coordination-feature-design.md §8.5."
                ),
                write_set=[
                    "packages/server/lib/domain/coordination/coordination_status_rules.dart",
                    "packages/server/test/domain/coordination/coordination_status_rules_test.dart",
                    "packages/server/lib/data/repository/coordination_repository.dart",
                ],
                read_set=[
                    "packages/server/lib/domain/evaluation/evaluation_visibility_rules.dart",
                    "packages/server/test/domain/evaluation/evaluation_visibility_rules_test.dart",
                    "docs/future-arch-improvements.md",
                    "docs/over-offer-coordination-feature-design.md",
                ],
                success_criteria=[
                    "Pure deriveBeaconCoordinationStatus (or equivalent) with table-driven tests",
                    "Coordination repository calls the pure rules module",
                    "packages/server dart analyze and dart test pass",
                ],
            ),
            packages=["server"],
            test_scope="test/domain/coordination/",
        ),
        AutopilotTask(
            unit=WorkUnit(
                id="ds-tokens",
                intent=(
                    "Replace non-allowlisted inline Color(0x..), Colors.*, and fontSize: "
                    "literals in packages/client/lib/features/** with design-system tokens "
                    "(context.tt, TenturaText.*, theme.textTheme). Do not touch "
                    "design_system/, rating_scatter_view.dart, or colors_drawer.dart allow-list."
                ),
                write_set=["packages/client/lib/features/"],
                read_set=[
                    "packages/client/lib/design_system/",
                    "docs/tentura-design-system.md",
                    ".cursor/rules/tentura-design-system.mdc",
                ],
                constraints=[
                    "No new no_inline_font_size violations.",
                    "Do not run flutter test --update-goldens.",
                ],
                success_criteria=[
                    "flutter analyze --no-fatal-warnings --no-fatal-infos passes",
                    "Existing golden tests pass unchanged",
                ],
            ),
            packages=["client"],
            test_scope="test/",
        ),
        AutopilotTask(
            unit=WorkUnit(
                id="nplus1",
                intent=(
                    "Batch N+1 user/profile loads in evaluation participant flows and "
                    "helpOffersWithCoordination on the server. Use join/batch repository "
                    "methods instead of per-row getById in hot paths."
                ),
                write_set=[
                    "packages/server/lib/domain/use_case/evaluation_case.dart",
                    "packages/server/lib/domain/use_case/coordination_case.dart",
                    "packages/server/lib/data/repository/",
                ],
                read_set=[
                    "packages/server/lib/domain/port/",
                    "docs/future-arch-improvements.md",
                ],
                depends_on=["coord-phase-a"],
                success_criteria=[
                    "No per-row getById loops in the batched paths",
                    "packages/server dart test passes",
                ],
            ),
            packages=["server"],
            test_scope="test/domain/",
        ),
        AutopilotTask(
            unit=WorkUnit(
                id="cubit-usecase",
                intent=(
                    "Introduce thin *Case orchestrators for multi-repo cubits flagged by "
                    "cubit_requires_use_case_for_multi_repos (beacon_cubit, profile_view_cubit, "
                    "profile_edit_cubit, graph_cubit, app_update_cubit). Wire via Injectable; "
                    "cubits inject the case, not multiple repositories."
                ),
                write_set=[
                    "packages/client/lib/features/",
                    "packages/client/lib/domain/use_case/",
                ],
                read_set=[
                    ".cursor/rules/architecture.mdc",
                    "DEV_GUIDELINES.md",
                ],
                constraints=[
                    "Remove cubit_requires_use_case_for_multi_repos baselines when fixed.",
                ],
                success_criteria=[
                    "flutter analyze passes",
                    "Affected cubit tests pass",
                ],
            ),
            packages=["client"],
            default_enabled=False,
        ),
        AutopilotTask(
            unit=WorkUnit(
                id="docs",
                intent=(
                    "Fix stale code references and broken cross-links in docs/*.md journals "
                    "and architecture docs. Do not change production Dart code."
                ),
                write_set=["docs/"],
                read_set=[
                    "packages/",
                    ".cursor/rules/",
                ],
                success_criteria=[
                    "Cross-referenced paths exist",
                    "No contradictory guidance vs DEV_GUIDELINES.md",
                ],
                default_enabled=False,
                skip_machine_gates=True,
            ),
            packages=[],
        ),
    ]

    dto_tasks = _dto_subtasks(repo)
    return base + dto_tasks


def select_tasks(
    repo: Path,
    *,
    task_ids: list[str],
    include_disabled: bool,
) -> list[AutopilotTask]:
    queue = build_task_queue(repo)
    if not include_disabled:
        queue = [t for t in queue if t.default_enabled]

    if task_ids:
        allowed = set(task_ids)
        queue = [t for t in queue if t.unit.id in allowed]
        missing = allowed - {t.unit.id for t in queue}
        if missing:
            msg = f"Unknown or disabled task id(s): {sorted(missing)}"
            raise ValueError(msg)

    done: set[str] = set()
    ordered: list[AutopilotTask] = []
    by_id = {t.unit.id: t for t in queue}

    def visit(tid: str) -> None:
        if tid in done:
            return
        task = by_id.get(tid)
        if task is None:
            return
        for dep in task.unit.depends_on:
            visit(dep)
        if tid not in done:
            ordered.append(task)
            done.add(tid)

    for t in queue:
        visit(t.unit.id)
    return ordered


def build_worker_prompt(task: AutopilotTask) -> str:
    u = task.unit
    constraints = "\n".join(f"- {c}" for c in u.constraints) or "- Follow project architecture rules"
    criteria = "\n".join(f"- {c}" for c in u.success_criteria)
    writes = "\n".join(f"- {p}" for p in u.write_set)
    reads = "\n".join(f"- {p}" for p in u.read_set) if u.read_set else "- (minimal reads)"
    return (
        f"# Task: {u.id}\n\n"
        f"## Intent\n{u.intent}\n\n"
        f"## Write set (only modify these)\n{writes}\n\n"
        f"## Read set (context)\n{reads}\n\n"
        f"## Constraints\n{constraints}\n\n"
        f"## Success criteria\n{criteria}\n\n"
        "Implement the task in the working tree. Run the relevant analyze/test commands "
        "before finishing. Report DONE when complete."
    )


def build_retry_prompt(*, gate_summary: str, gate_tail: str, review_reason: str | None) -> str:
    parts = [
        "The previous attempt did not pass verification.",
        f"Gate summary: {gate_summary}",
    ]
    if review_reason:
        parts.append(f"Review rejection: {review_reason}")
    if gate_tail.strip():
        parts.append(f"Tool output (tail):\n{gate_tail}")
    parts.append("Fix the issues and report DONE.")
    return "\n\n".join(parts)


def diff_respects_constraint(changed: list[str], prefixes: tuple[str, ...]) -> bool:
    if not changed:
        return False
    for path in changed:
        if not any(path.startswith(p) for p in prefixes):
            return False
    return True


def count_dto_ignores(repo: Path, rel_path: str) -> int:
    p = repo / rel_path
    if not p.is_file():
        return 0
    return len(re.findall(re.escape(DTO_IGNORE), p.read_text(encoding="utf-8")))
