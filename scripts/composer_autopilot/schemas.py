"""Pydantic models for Composer Autopilot (trimmed from harnessexp refactor schemas)."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, model_validator

VerifierStatus = Literal["pass", "fail", "partial"]
VerifierChannel = Literal[
    "server_analyze",
    "server_tests",
    "client_analyze",
    "client_tests",
    "lint_tests",
    "infrastructure",
]


class VerifierEvidence(BaseModel):
    file: str | None = None
    line: int | None = None
    reason: str = Field(min_length=1, max_length=600)


class VerifierVerdict(BaseModel):
    channel: VerifierChannel
    status: VerifierStatus
    evidence: list[VerifierEvidence] = Field(default_factory=list)
    suggested_fix: str | None = Field(default=None, max_length=2000)
    raw_output_path: str | None = None

    @model_validator(mode="after")
    def _fail_needs_evidence(self) -> VerifierVerdict:
        if self.status in ("fail", "partial") and not self.evidence and not self.suggested_fix:
            raise ValueError(
                f"VerifierVerdict[{self.channel}] status={self.status} requires "
                "evidence or suggested_fix."
            )
        return self


def verdict_passes(verdict: VerifierVerdict) -> bool:
    return verdict.status == "pass"


class WorkUnit(BaseModel):
    id: str = Field(min_length=1, max_length=80)
    intent: str = Field(min_length=10, max_length=4000)
    write_set: list[str] = Field(min_length=1)
    read_set: list[str] = Field(default_factory=list)
    constraints: list[str] = Field(default_factory=list)
    success_criteria: list[str] = Field(min_length=1)
    depends_on: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def _no_self_overlap(self) -> WorkUnit:
        overlap = set(self.write_set) & set(self.read_set)
        if overlap:
            msg = (
                f"WorkUnit {self.id!r}: paths in both write_set and read_set: "
                f"{sorted(overlap)}"
            )
            raise ValueError(msg)
        return self


class ReviewDecision(BaseModel):
    approve: bool
    reason: str = Field(min_length=1, max_length=4000)


class TaskResult(BaseModel):
    task_id: str
    status: Literal["committed", "skipped", "failed", "dry_run"]
    commit_sha: str | None = None
    agent_id: str | None = None
    run_ids: list[str] = Field(default_factory=list)
    reason: str | None = None
    elapsed_seconds: float = 0.0
