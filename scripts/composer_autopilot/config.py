"""Configuration for Composer Autopilot."""

from __future__ import annotations

import argparse
import os
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INTEGRATION_BRANCH = "composer-autopilot"
DEFAULT_WORKER_MODEL = "auto"
DEFAULT_REVIEW_MODEL_FALLBACK = "claude-opus-4-8-thinking-high"
DEFAULT_MAX_RETRIES = 2
DEFAULT_AGENT_TIMEOUT_SECONDS = 1800.0
DEFAULT_SUBPROCESS_TIMEOUT_SECONDS = 600.0
RUNS_DIR = Path(__file__).resolve().parent / ".runs"


def load_dotenv(path: Path) -> dict[str, str]:
    """Minimal .env parser (KEY=VALUE, ignores comments/blank lines)."""
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key:
            out[key] = val
    return out


@dataclass
class Config:
    repo_root: Path = REPO_ROOT
    api_key: str = ""
    worker_model: str = DEFAULT_WORKER_MODEL
    review_model: str = DEFAULT_REVIEW_MODEL_FALLBACK
    integration_branch: str = DEFAULT_INTEGRATION_BRANCH
    target_branch: str | None = None
    max_retries: int = DEFAULT_MAX_RETRIES
    agent_timeout_seconds: float = DEFAULT_AGENT_TIMEOUT_SECONDS
    subprocess_timeout_seconds: float = DEFAULT_SUBPROCESS_TIMEOUT_SECONDS
    max_hours: float | None = None
    allow_dirty: bool = False
    dry_run: bool = False
    skip_review: bool = False
    task_ids: list[str] = field(default_factory=list)
    runs_dir: Path = RUNS_DIR

    @classmethod
    def from_env_and_args(cls, args: argparse.Namespace) -> Config:
        env = load_dotenv(REPO_ROOT / ".env")
        cfg = cls(
            api_key=os.environ.get("CURSOR_API_KEY", env.get("CURSOR_API_KEY", "")).strip(),
            worker_model=os.environ.get("AUTOPILOT_WORKER_MODEL", DEFAULT_WORKER_MODEL),
            review_model=os.environ.get(
                "AUTOPILOT_REVIEW_MODEL",
                DEFAULT_REVIEW_MODEL_FALLBACK,
            ),
            integration_branch=args.branch or DEFAULT_INTEGRATION_BRANCH,
            target_branch=args.target,
            max_retries=args.max_retries,
            agent_timeout_seconds=args.agent_timeout,
            subprocess_timeout_seconds=args.subprocess_timeout,
            max_hours=args.max_hours,
            allow_dirty=args.allow_dirty,
            dry_run=args.dry_run,
            skip_review=args.skip_review,
            task_ids=list(args.tasks or []),
            runs_dir=Path(args.runs_dir) if args.runs_dir else RUNS_DIR,
        )
        if not cfg.api_key:
            msg = (
                "CURSOR_API_KEY is not set. Add it to .env or the environment "
                "(https://cursor.com/dashboard/integrations)."
            )
            raise ValueError(msg)
        return cfg


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Composer Autopilot — sequential Cursor SDK task runner for Tentura.",
    )
    p.add_argument(
        "--branch",
        default=DEFAULT_INTEGRATION_BRANCH,
        help=f"Integration branch to commit onto (default: {DEFAULT_INTEGRATION_BRANCH})",
    )
    p.add_argument(
        "--target",
        default=None,
        help="Checkout this branch before running (default: stay on/create integration branch)",
    )
    p.add_argument(
        "--tasks",
        nargs="*",
        default=[],
        help="Task ids to run (default: all enabled tasks)",
    )
    p.add_argument("--max-retries", type=int, default=DEFAULT_MAX_RETRIES)
    p.add_argument("--agent-timeout", type=float, default=DEFAULT_AGENT_TIMEOUT_SECONDS)
    p.add_argument("--subprocess-timeout", type=float, default=DEFAULT_SUBPROCESS_TIMEOUT_SECONDS)
    p.add_argument("--max-hours", type=float, default=None, help="Wall-clock stop after N hours")
    p.add_argument("--allow-dirty", action="store_true", help="Stash dirty tree before start")
    p.add_argument("--dry-run", action="store_true", help="Run workers/gates/review without committing")
    p.add_argument("--skip-review", action="store_true", help="Skip Opus review (gates only)")
    p.add_argument("--runs-dir", default=None, help="Directory for run reports")
    p.add_argument("--include-disabled", action="store_true", help="Include default-OFF tasks")
    return p
