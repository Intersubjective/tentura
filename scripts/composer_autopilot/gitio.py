"""Git helpers for Composer Autopilot.

Vendored from harnessexp src/indexer/refactor/git_util.py with commit/revert helpers.
"""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path

log = logging.getLogger(__name__)


def git_run(args: list[str], cwd: Path, *, hint: str | None = None) -> str:
    log.debug("git %s (cwd=%s)", " ".join(args[1:]), cwd)
    out = subprocess.run(  # noqa: S603
        args, cwd=cwd, capture_output=True, text=True, check=False
    )
    if out.returncode != 0:
        err = out.stderr.strip() or out.stdout.strip()
        if hint:
            err = f"{err} {hint}"
        raise RuntimeError(f"git command failed ({' '.join(args[1:])}): {err}")
    return out.stdout.strip()


def git_run_optional(args: list[str], cwd: Path) -> str | None:
    try:
        return git_run(args, cwd)
    except RuntimeError:
        return None


def in_merge_state(repo: Path) -> bool:
    return (repo / ".git" / "MERGE_HEAD").exists()


def in_rebase_state(repo: Path) -> bool:
    git_dir = repo / ".git"
    return (git_dir / "rebase-merge").exists() or (git_dir / "rebase-apply").exists()


def unmerged_paths(repo: Path) -> list[str]:
    status = git_run_optional(["git", "diff", "--name-only", "--diff-filter=U"], repo)
    if not status:
        return []
    return [line.strip() for line in status.splitlines() if line.strip()]


def current_branch(repo: Path) -> str | None:
    try:
        return git_run(["git", "symbolic-ref", "--short", "HEAD"], repo)
    except RuntimeError:
        return None


def integration_git_blockers(
    repo: Path,
    *,
    integration_branch: str | None = None,
) -> list[tuple[str, str, str]]:
    blockers: list[tuple[str, str, str]] = []
    branch = integration_branch or current_branch(repo) or "(unknown)"

    if in_rebase_state(repo):
        blockers.append(
            (
                "git-rebase-state",
                f"rebase in progress on {branch}",
                "Run `git rebase --abort` in the target repo, then re-run autopilot",
            )
        )

    conflicts = unmerged_paths(repo)
    if in_merge_state(repo) or conflicts:
        if conflicts:
            preview = ", ".join(conflicts[:3])
            if len(conflicts) > 3:
                preview = f"{preview}, ..."
            detail = (
                f"unfinished merge on {branch} "
                f"({len(conflicts)} conflicted file(s): {preview})"
            )
        else:
            detail = f"unfinished merge on {branch}"
        blockers.append(
            (
                "git-merge-state",
                detail,
                "Run `git merge --abort` in the target repo, then re-run autopilot",
            )
        )

    return blockers


def format_integration_blockers(
    repo: Path,
    *,
    integration_branch: str | None = None,
) -> str | None:
    blockers = integration_git_blockers(repo, integration_branch=integration_branch)
    if not blockers:
        return None
    return "; ".join(detail for _name, detail, _hint in blockers)


def ensure_on_integration_branch(repo: Path, integration_branch: str) -> None:
    blockers = format_integration_blockers(repo, integration_branch=integration_branch)
    if blockers:
        raise RuntimeError(blockers)
    if current_branch(repo) != integration_branch:
        if git_run_optional(["git", "rev-parse", "--verify", integration_branch], repo):
            git_run(["git", "checkout", integration_branch], repo)
        else:
            git_run(["git", "checkout", "-b", integration_branch], repo)


def is_clean(repo: Path) -> bool:
    return not git_run(["git", "status", "--porcelain"], repo)


def stash_if_dirty(repo: Path, *, message: str = "composer-autopilot: pre-run stash") -> bool:
    if is_clean(repo):
        return False
    git_run(["git", "stash", "push", "-u", "-m", message], repo)
    return True


def require_clean_tree(repo: Path, *, allow_dirty: bool) -> None:
    if is_clean(repo):
        return
    if allow_dirty:
        stash_if_dirty(repo)
        return
    status = git_run(["git", "status", "--short"], repo)
    msg = (
        "Working tree is dirty. Commit or stash changes first, or pass --allow-dirty.\n"
        f"{status}"
    )
    raise RuntimeError(msg)


def task_start_ref(repo: Path) -> str:
    return git_run(["git", "rev-parse", "HEAD"], repo)


def diff_since(repo: Path, base_ref: str) -> str:
    return git_run(["git", "diff", base_ref], repo)


def diff_stat_since(repo: Path, base_ref: str) -> str:
    return git_run(["git", "diff", "--stat", base_ref], repo)


def changed_paths_since(repo: Path, base_ref: str) -> list[str]:
    out = git_run(["git", "diff", "--name-only", base_ref], repo)
    return [line.strip() for line in out.splitlines() if line.strip()]


def revert_worktree(repo: Path, base_ref: str) -> None:
    """Discard all changes since *base_ref* (staged + unstaged + untracked from task)."""
    git_run(["git", "reset", "--hard", base_ref], repo)
    git_run(["git", "clean", "-fd"], repo)


def commit_all(repo: Path, message: str) -> str | None:
    git_run(["git", "add", "-A"], repo)
    status = git_run(["git", "status", "--porcelain"], repo)
    if not status:
        return None
    git_run(["git", "commit", "-m", message], repo)
    return git_run(["git", "rev-parse", "HEAD"], repo)
