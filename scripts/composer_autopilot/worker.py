"""Worker agent (model=auto) for Composer Autopilot."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

from cursor_sdk.errors import CursorAgentError

from sdk import AgentInfrastructureError, send_and_wait
from tasks import AutopilotTask, build_worker_prompt

if TYPE_CHECKING:
    from cursor_sdk._agent import Agent as AgentHandle

log = logging.getLogger(__name__)


@dataclass
class WorkerSession:
    task: AutopilotTask
    agent_id: str | None = None
    run_ids: list[str] = field(default_factory=list)
    last_error: str | None = None


def run_worker_attempt(
    agent: AgentHandle,
    session: WorkerSession,
    *,
    timeout_seconds: float,
    prompt: str | None = None,
) -> bool:
    """Send one prompt on an open agent. Returns True when run finishes OK."""
    text = prompt or build_worker_prompt(session.task)
    label = f"worker/{session.task.unit.id}"
    try:
        result = send_and_wait(agent, text, label=label, timeout_seconds=timeout_seconds)
        session.agent_id = agent.agent_id
        session.run_ids.append(result.id)
        if result.status == "error":
            session.last_error = f"run failed: {result.id}"
            return False
        return True
    except CursorAgentError as exc:
        session.last_error = f"startup failed: {exc.message}"
        raise AgentInfrastructureError("worker send failed") from exc
