"""Opus 4.8 one-shot review for Composer Autopilot."""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path

from schemas import ReviewDecision, WorkUnit
from sdk import run_prompt

log = logging.getLogger(__name__)


def build_review_prompt(
    unit: WorkUnit,
    *,
    diff_stat: str,
    diff_text: str,
    gate_summary: str,
    max_diff_chars: int = 12000,
) -> str:
    criteria = "\n".join(f"- {c}" for c in unit.success_criteria)
    diff_body = diff_text[-max_diff_chars:] if len(diff_text) > max_diff_chars else diff_text
    return (
        f"You are reviewing an autonomous code change for task `{unit.id}`.\n\n"
        f"## Intent\n{unit.intent}\n\n"
        f"## Success criteria\n{criteria}\n\n"
        f"## Gate summary\n{gate_summary}\n\n"
        f"## Diff stat\n{diff_stat}\n\n"
        f"## Diff\n```diff\n{diff_body}\n```\n\n"
        "Respond with JSON only, no markdown fences:\n"
        '{"approve": true|false, "reason": "one paragraph"}\n'
        "Approve only if the diff clearly meets the success criteria and looks safe to merge."
    )


def parse_review_response(text: str) -> ReviewDecision:
    raw = text.strip()
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, re.DOTALL)
    if fence:
        raw = fence.group(1)
    else:
        start = raw.find("{")
        end = raw.rfind("}")
        if start >= 0 and end > start:
            raw = raw[start : end + 1]
    data = json.loads(raw)
    return ReviewDecision.model_validate(data)


def review_task(
    unit: WorkUnit,
    *,
    diff_stat: str,
    diff_text: str,
    gate_summary: str,
    review_model: str,
    api_key: str,
    repo_root: Path,
    timeout_seconds: float,
) -> ReviewDecision:
    prompt = build_review_prompt(
        unit,
        diff_stat=diff_stat,
        diff_text=diff_text,
        gate_summary=gate_summary,
    )
    result = run_prompt(
        prompt,
        model=review_model,
        cwd=repo_root,
        api_key=api_key,
        timeout_seconds=timeout_seconds,
        label=f"review/{unit.id}",
    )
    if result.status == "error":
        return ReviewDecision(approve=False, reason=f"Review agent run failed: {result.id}")
    body = result.result or ""
    try:
        return parse_review_response(body)
    except (json.JSONDecodeError, ValueError) as exc:
        log.warning("review parse failed: %s", exc)
        return ReviewDecision(
            approve=False,
            reason=f"Could not parse review JSON: {exc}; raw={body[:500]}",
        )
