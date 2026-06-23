"""Thin sync adapter over the Cursor Python SDK.

Vendored and trimmed from harnessexp src/indexer/sdk_client.py.
"""

from __future__ import annotations

import logging
import os
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import TYPE_CHECKING

from cursor_sdk import Agent, AgentOptions, LocalAgentOptions, SendOptions
from cursor_sdk.errors import CursorAgentError, NetworkError
from dotenv import load_dotenv

if TYPE_CHECKING:
    from cursor_sdk import RunResult
    from cursor_sdk._agent import Agent as AgentHandle

log = logging.getLogger(__name__)

DEFAULT_AGENT_CREATE_RETRIES = 3
DEFAULT_AGENT_TIMEOUT_SECONDS = 1800.0
NETWORK_BACKOFF_CAP_SECONDS = 30.0


class AgentInfrastructureError(RuntimeError):
    """Agent create/send failed after harness retries (see ``__cause__``)."""


class AgentTimeoutError(AgentInfrastructureError):
    def __init__(self, label: str, timeout_seconds: float) -> None:
        super().__init__(f"agent timed out label={label} after {timeout_seconds:.0f}s")
        self.label = label
        self.timeout_seconds = timeout_seconds


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def init_env() -> None:
    load_dotenv(repo_root() / ".env")


def load_api_key() -> str:
    init_env()
    key = os.environ.get("CURSOR_API_KEY", "").strip()
    if not key:
        msg = (
            "CURSOR_API_KEY is not set. Copy .env.example to .env and add your key "
            "(https://cursor.com/dashboard/integrations)."
        )
        raise ValueError(msg)
    return key


def _is_retryable_agent_error(exc: BaseException) -> bool:
    if isinstance(exc, NetworkError):
        return True
    if isinstance(exc, CursorAgentError):
        if exc.is_retryable:
            return True
        status = exc.status
        return status is not None and (status == 408 or status == 429 or status >= 500)
    return False


def _parse_retry_after_seconds(retry_after: str | None) -> float | None:
    if not retry_after:
        return None
    try:
        return float(retry_after)
    except ValueError:
        return None


def _backoff_seconds(
    attempt: int,
    retry_after: str | None,
    *,
    exc: BaseException | None = None,
) -> float:
    parsed = _parse_retry_after_seconds(retry_after)
    if parsed is not None:
        return parsed
    if isinstance(exc, NetworkError):
        return min(2.0**attempt, NETWORK_BACKOFF_CAP_SECONDS)
    return min(0.5 * (2**attempt), 2.0)


def _format_agent_error(exc: BaseException) -> str:
    if isinstance(exc, NetworkError):
        parts = ["bridge connection failed"]
        if exc.__cause__ is not None:
            parts.append(f"cause={exc.__cause__!s}")
        return " ".join(parts)
    if isinstance(exc, CursorAgentError):
        parts: list[str] = []
        if exc.status is not None:
            parts.append(f"status={exc.status}")
        if exc.code:
            parts.append(f"code={exc.code}")
        if exc.request_id:
            parts.append(f"request_id={exc.request_id}")
        parts.append(f"retryable={exc.is_retryable}")
        if exc.retry_after:
            parts.append(f"retry_after={exc.retry_after}")
        return " ".join(parts)
    return str(exc)


def _local_options(cwd: Path | str) -> LocalAgentOptions:
    return LocalAgentOptions(cwd=os.fspath(Path(cwd).resolve()))


def agent_options(
    *,
    model: str,
    cwd: Path | str | None = None,
    api_key: str | None = None,
) -> AgentOptions:
    path = Path(cwd) if cwd is not None else repo_root()
    return AgentOptions(
        api_key=api_key or load_api_key(),
        model=model,
        local=_local_options(path),
    )


def run_prompt(
    prompt: str,
    *,
    model: str,
    cwd: Path | str | None = None,
    api_key: str | None = None,
    timeout_seconds: float | None = DEFAULT_AGENT_TIMEOUT_SECONDS,
    label: str = "review",
) -> RunResult:
    """One-shot local agent prompt with optional wall-clock timeout."""
    opts = agent_options(model=model, cwd=cwd, api_key=api_key)
    last_exc: BaseException | None = None
    for attempt in range(DEFAULT_AGENT_CREATE_RETRIES):
        try:
            t0 = time.monotonic()
            result = Agent.prompt(prompt, opts)
            if timeout_seconds is not None and time.monotonic() - t0 > timeout_seconds:
                raise AgentTimeoutError(label, timeout_seconds)
            return result
        except AgentTimeoutError:
            raise
        except BaseException as exc:
            last_exc = exc
            if attempt >= DEFAULT_AGENT_CREATE_RETRIES - 1 or not _is_retryable_agent_error(exc):
                log.error(
                    "prompt failed label=%s attempt=%d/%d %s",
                    label,
                    attempt + 1,
                    DEFAULT_AGENT_CREATE_RETRIES,
                    _format_agent_error(exc),
                )
                if isinstance(exc, CursorAgentError | NetworkError):
                    raise AgentInfrastructureError("agent prompt failed") from exc
                raise
            delay = _backoff_seconds(
                attempt,
                exc.retry_after if isinstance(exc, CursorAgentError) else None,
                exc=exc,
            )
            log.warning(
                "prompt retry label=%s attempt=%d sleep=%.1fs %s",
                label,
                attempt + 1,
                delay,
                _format_agent_error(exc),
            )
            time.sleep(delay)
    msg = "prompt retries exhausted"
    raise RuntimeError(msg) from last_exc


def create_agent(
    *,
    model: str,
    cwd: Path | str | None = None,
    api_key: str | None = None,
) -> AgentHandle:
    return Agent.create(agent_options(model=model, cwd=cwd, api_key=api_key))


@contextmanager
def local_agent(
    *,
    model: str,
    cwd: Path | str | None = None,
    api_key: str | None = None,
) -> Iterator[AgentHandle]:
    with create_agent(model=model, cwd=cwd, api_key=api_key) as agent:
        yield agent


def send_and_wait(
    agent: AgentHandle,
    prompt: str,
    *,
    label: str,
    timeout_seconds: float | None = DEFAULT_AGENT_TIMEOUT_SECONDS,
) -> RunResult:
    """Send prompt, optionally stream text to log, wait for terminal result."""
    run = agent.send(prompt, SendOptions())
    log.info("agent send label=%s agent_id=%s run_id=%s", label, agent.agent_id, run.id)
    t0 = time.monotonic()
    try:
        for message in run.messages():
            if message.type == "assistant":
                for block in message.message.content:
                    if block.type == "text" and block.text.strip():
                        log.debug("assistant[%s]: %s", label, block.text[:200])
    except Exception:
        log.debug("stream ended label=%s", label, exc_info=True)
    if timeout_seconds is not None and time.monotonic() - t0 > timeout_seconds:
        if run.supports("cancel"):
            run.cancel()
        raise AgentTimeoutError(label, timeout_seconds)
    return run.wait()


def resolve_review_model(fallback: str) -> str:
    """Use configured review model; resolve Opus id from catalog only when needed."""
    if fallback.strip().lower() == "auto":
        log.info("using review model: auto")
        return "auto"
    try:
        from cursor_sdk import Cursor

        models = Cursor.models.list()
        for m in models:
            mid = getattr(m, "id", None) or str(m)
            low = mid.lower()
            if "opus" in low and ("4.8" in low or "4-8" in low):
                log.info("resolved review model: %s", mid)
                return mid
    except Exception as exc:
        log.warning("Cursor.models.list failed, using fallback: %s", exc)
    log.info("using review model fallback: %s", fallback)
    return fallback
