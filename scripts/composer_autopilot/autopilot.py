#!/usr/bin/env python3
"""Composer Autopilot — sequential Cursor SDK task runner for Tentura."""

from __future__ import annotations

import json
import logging
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Allow imports when run as scripts/composer_autopilot/autopilot.py
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from config import Config, build_arg_parser
from gates import (
    BaselineSnapshot,
    TaskGateSpec,
    capture_baseline,
    channels_for_packages,
    run_task_gates,
    summarize_verdicts,
    tail_output,
    verdict_passes,
)
from gitio import (
    changed_paths_since,
    commit_all,
    diff_since,
    diff_stat_since,
    ensure_on_integration_branch,
    require_clean_tree,
    revert_worktree,
    task_start_ref,
)
from review import review_task
from schemas import TaskResult
from sdk import local_agent, resolve_review_model
from tasks import (
    AutopilotTask,
    build_retry_prompt,
    diff_respects_constraint,
    select_tasks,
)
from worker import WorkerSession, run_worker_attempt

log = logging.getLogger(__name__)


def _setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%H:%M:%S",
    )


def _gate_regressions(baseline: BaselineSnapshot, verdicts: list, channels: list[str]) -> list:
    regressed = []
    for ch, v in zip(channels, verdicts, strict=False):
        if baseline.was_green(ch) and not verdict_passes(v):
            regressed.append(v)
    return regressed


def _all_packages(tasks: list[AutopilotTask]) -> set[str]:
    pkgs: set[str] = set()
    for t in tasks:
        pkgs.update(t.packages)
    return pkgs


def _validate_task_diff(task: AutopilotTask, repo: Path, base_ref: str) -> str | None:
    changed = changed_paths_since(repo, base_ref)
    if not changed:
        return "No file changes detected"
    if task.diff_must_be_under is not None:
        if not diff_respects_constraint(changed, task.diff_must_be_under):
            return f"Diff touches paths outside {task.diff_must_be_under}: {changed}"
    return None


def _write_report(path: Path, results: list[TaskResult], *, started: str, finished: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Composer Autopilot report",
        "",
        f"- Started: {started}",
        f"- Finished: {finished}",
        "",
    ]
    for r in results:
        lines.append(
            f"- **{r.task_id}** — {r.status} ({r.elapsed_seconds:.1f}s)"
            + (f" sha=`{r.commit_sha[:8]}`" if r.commit_sha else "")
            + (f" — {r.reason}" if r.reason else "")
        )
    path.write_text("\n".join(lines) + "\n")
    path.with_suffix(".json").write_text(
        json.dumps([r.model_dump() for r in results], indent=2)
    )


def run_autopilot(cfg: Config, *, include_disabled: bool = False) -> list[TaskResult]:
    repo = cfg.repo_root
    tasks = select_tasks(repo, task_ids=cfg.task_ids, include_disabled=include_disabled)
    if not tasks:
        log.warning("No tasks selected")
        return []

    review_model = resolve_review_model(cfg.review_model)
    cfg = Config(**{**cfg.__dict__, "review_model": review_model})

    require_clean_tree(repo, allow_dirty=cfg.allow_dirty)
    if cfg.target_branch:
        from gitio import git_run

        git_run(["git", "checkout", cfg.target_branch], repo)
    ensure_on_integration_branch(repo, cfg.integration_branch)

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = cfg.runs_dir / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    baseline_dir = run_dir / "baseline"
    baseline = capture_baseline(
        repo,
        _all_packages(tasks),
        baseline_dir,
        timeout_seconds=cfg.subprocess_timeout_seconds,
    )
    (run_dir / "baseline.json").write_text(
        json.dumps(
            {k: {"passed": v.passed, "status": v.verdict.status} for k, v in baseline.suites.items()},
            indent=2,
        )
    )

    started_at = datetime.now(timezone.utc).isoformat()
    deadline = (
        time.monotonic() + cfg.max_hours * 3600 if cfg.max_hours is not None else None
    )
    results: list[TaskResult] = []

    for task in tasks:
        if deadline is not None and time.monotonic() >= deadline:
            log.warning("max-hours reached; stopping queue")
            break

        t0 = time.monotonic()
        task_dir = run_dir / task.unit.id
        task_dir.mkdir(parents=True, exist_ok=True)
        log.info("=== task %s ===", task.unit.id)

        base_ref = task_start_ref(repo)
        session = WorkerSession(task=task)
        approved = False
        final_reason: str | None = None
        retry_prompt: str | None = None

        with local_agent(
            model=cfg.worker_model,
            cwd=repo,
            api_key=cfg.api_key,
        ) as agent:
            for attempt in range(cfg.max_retries + 1):
                if not run_worker_attempt(
                    agent,
                    session,
                    timeout_seconds=cfg.agent_timeout_seconds,
                    prompt=retry_prompt,
                ):
                    final_reason = session.last_error or "worker run failed"
                    if attempt >= cfg.max_retries:
                        break
                    retry_prompt = build_retry_prompt(
                        gate_summary=final_reason,
                        gate_tail="",
                        review_reason=None,
                    )
                    continue

                if task.skip_machine_gates:
                    diff_err = _validate_task_diff(task, repo, base_ref)
                    if diff_err:
                        final_reason = diff_err
                        retry_prompt = build_retry_prompt(
                            gate_summary=diff_err,
                            gate_tail="",
                            review_reason=None,
                        )
                        if attempt >= cfg.max_retries:
                            break
                        continue
                    gate_summary = "machine gates skipped (docs task)"
                else:
                    gate_cap = task_dir / f"attempt-{attempt}-gates"
                    verdicts = run_task_gates(
                        repo,
                        TaskGateSpec(packages=task.packages, test_scope=task.test_scope),
                        gate_cap,
                        timeout_seconds=cfg.subprocess_timeout_seconds,
                        full_suite=True,
                    )
                    channels = channels_for_packages(task.packages)
                    diff_err = _validate_task_diff(task, repo, base_ref)
                    regressed = _gate_regressions(baseline, verdicts, channels)

                    if diff_err or regressed:
                        final_reason = diff_err or summarize_verdicts(regressed)
                        retry_prompt = build_retry_prompt(
                            gate_summary=summarize_verdicts(verdicts),
                            gate_tail=tail_output(regressed or verdicts),
                            review_reason=None,
                        )
                        if attempt >= cfg.max_retries:
                            break
                        continue

                    gate_summary = summarize_verdicts(verdicts)

                if not cfg.skip_review:
                    decision = review_task(
                        task.unit,
                        diff_stat=diff_stat_since(repo, base_ref),
                        diff_text=diff_since(repo, base_ref),
                        gate_summary=gate_summary,
                        review_model=cfg.review_model,
                        api_key=cfg.api_key,
                        repo_root=repo,
                        timeout_seconds=cfg.agent_timeout_seconds,
                    )
                    (task_dir / f"review-attempt-{attempt}.json").write_text(
                        decision.model_dump_json(indent=2)
                    )
                    if not decision.approve:
                        final_reason = decision.reason
                        retry_prompt = build_retry_prompt(
                            gate_summary=gate_summary,
                            gate_tail="",
                            review_reason=decision.reason,
                        )
                        if attempt >= cfg.max_retries:
                            break
                        continue

                approved = True
                break

        elapsed = time.monotonic() - t0

        if approved:
            if cfg.dry_run:
                results.append(
                    TaskResult(
                        task_id=task.unit.id,
                        status="dry_run",
                        agent_id=session.agent_id,
                        run_ids=session.run_ids,
                        elapsed_seconds=elapsed,
                    )
                )
                revert_worktree(repo, base_ref)
            else:
                sha = commit_all(repo, f"[autopilot] {task.unit.id}")
                results.append(
                    TaskResult(
                        task_id=task.unit.id,
                        status="committed" if sha else "skipped",
                        commit_sha=sha,
                        agent_id=session.agent_id,
                        run_ids=session.run_ids,
                        reason=None if sha else "no changes to commit",
                        elapsed_seconds=elapsed,
                    )
                )
        else:
            revert_worktree(repo, base_ref)
            results.append(
                TaskResult(
                    task_id=task.unit.id,
                    status="failed",
                    agent_id=session.agent_id,
                    run_ids=session.run_ids,
                    reason=final_reason,
                    elapsed_seconds=elapsed,
                )
            )

    finished_at = datetime.now(timezone.utc).isoformat()
    _write_report(run_dir / "REPORT.md", results, started=started_at, finished=finished_at)
    log.info("Report written to %s", run_dir / "REPORT.md")
    return results


def main() -> int:
    _setup_logging()
    parser = build_arg_parser()
    args = parser.parse_args()
    try:
        cfg = Config.from_env_and_args(args)
    except ValueError as exc:
        log.error("%s", exc)
        return 1

    try:
        results = run_autopilot(cfg, include_disabled=args.include_disabled)
    except RuntimeError as exc:
        log.error("%s", exc)
        return 1
    except KeyboardInterrupt:
        log.warning("Interrupted")
        return 130

    failed = sum(1 for r in results if r.status == "failed")
    if failed:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
