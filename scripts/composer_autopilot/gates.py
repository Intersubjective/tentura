"""Dart/Flutter verification gates (pattern from harnessexp verify.py)."""

from __future__ import annotations

import logging
import shlex
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from schemas import VerifierChannel, VerifierEvidence, VerifierVerdict, verdict_passes

log = logging.getLogger(__name__)

PACKAGE_DIRS = {
    "server": Path("packages/server"),
    "client": Path("packages/client"),
    "lint": Path("packages/tentura_lints"),
}


@dataclass
class GateSuite:
    """Named gate channel -> pass/fail at baseline or after a task."""

    channel: str
    passed: bool
    verdict: VerifierVerdict


@dataclass
class BaselineSnapshot:
    suites: dict[str, GateSuite] = field(default_factory=dict)

    def was_green(self, channel: str) -> bool:
        suite = self.suites.get(channel)
        return suite.passed if suite is not None else True


def _truncate(s: str, n: int = 800) -> str:
    return s if len(s) <= n else s[:n] + " …(truncated)"


def _run_cmd(cmd: str, cwd: Path, capture_path: Path, *, timeout_seconds: float) -> tuple[int, str]:
    capture_path.parent.mkdir(parents=True, exist_ok=True)
    use_shell = any(op in cmd for op in ("&&", "||", ";", "|"))
    try:
        if use_shell:
            proc = subprocess.run(  # noqa: S603
                cmd,
                cwd=cwd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )
        else:
            args = shlex.split(cmd)
            proc = subprocess.run(  # noqa: S603
                args,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )
    except FileNotFoundError as exc:
        missing = shlex.split(cmd)[0] if not use_shell else cmd.split()[0]
        out = f"Command not found: {missing!r} ({exc})"
        capture_path.write_text(out)
        return 127, out
    except subprocess.TimeoutExpired:
        out = f"Timed out after {timeout_seconds}s"
        capture_path.write_text(out)
        return -1, out

    out = (proc.stdout or "") + (proc.stderr or "")
    capture_path.write_text(out)
    rc = proc.returncode if proc.returncode is not None else -1
    return rc, out


def _verdict_from_rc(
    channel: VerifierChannel,
    rc: int,
    out: str,
    cap: Path,
    *,
    label: str,
) -> VerifierVerdict:
    if rc == 0:
        return VerifierVerdict(channel=channel, status="pass", raw_output_path=str(cap))
    return VerifierVerdict(
        channel=channel,
        status="fail",
        evidence=[VerifierEvidence(reason=_truncate(out))],
        suggested_fix=f"{label} failed; see {cap}",
        raw_output_path=str(cap),
    )


def run_server_analyze(repo: Path, capture_dir: Path, *, timeout_seconds: float) -> VerifierVerdict:
    cwd = repo / PACKAGE_DIRS["server"]
    cap = capture_dir / "server_analyze.log"
    rc, out = _run_cmd(
        "dart analyze --no-fatal-warnings",
        cwd,
        cap,
        timeout_seconds=timeout_seconds,
    )
    return _verdict_from_rc("server_analyze", rc, out, cap, label="server analyze")


def run_client_analyze(repo: Path, capture_dir: Path, *, timeout_seconds: float) -> VerifierVerdict:
    cwd = repo / PACKAGE_DIRS["client"]
    cap = capture_dir / "client_analyze.log"
    rc, out = _run_cmd(
        "flutter analyze --no-fatal-warnings --no-fatal-infos",
        cwd,
        cap,
        timeout_seconds=timeout_seconds,
    )
    return _verdict_from_rc("client_analyze", rc, out, cap, label="client analyze")


def run_server_tests(
    repo: Path,
    capture_dir: Path,
    *,
    timeout_seconds: float,
    scope: str | None = None,
) -> VerifierVerdict:
    cwd = repo / PACKAGE_DIRS["server"]
    cap = capture_dir / "server_tests.log"
    cmd = "dart test" if scope is None else f"dart test {scope}"
    rc, out = _run_cmd(cmd, cwd, cap, timeout_seconds=timeout_seconds)
    return _verdict_from_rc("server_tests", rc, out, cap, label="server tests")


def run_client_tests(
    repo: Path,
    capture_dir: Path,
    *,
    timeout_seconds: float,
    scope: str | None = None,
) -> VerifierVerdict:
    cwd = repo / PACKAGE_DIRS["client"]
    cap = capture_dir / "client_tests.log"
    cmd = "flutter test" if scope is None else f"flutter test {scope}"
    rc, out = _run_cmd(cmd, cwd, cap, timeout_seconds=timeout_seconds)
    return _verdict_from_rc("client_tests", rc, out, cap, label="client tests")


def run_lint_plugin_tests(repo: Path, capture_dir: Path, *, timeout_seconds: float) -> VerifierVerdict:
    cwd = repo / PACKAGE_DIRS["lint"]
    cap = capture_dir / "lint_plugin_tests.log"
    rc, out = _run_cmd("dart test", cwd, cap, timeout_seconds=timeout_seconds)
    return _verdict_from_rc("lint_tests", rc, out, cap, label="tentura_lints tests")


@dataclass
class TaskGateSpec:
    packages: list[str]
    test_scope: str | None = None


def channels_for_packages(packages: list[str]) -> list[str]:
    channels: list[str] = []
    if "server" in packages:
        channels.extend(["server_analyze", "server_tests"])
    if "client" in packages:
        channels.extend(["client_analyze", "client_tests"])
    if "lint" in packages:
        channels.append("lint_tests")
    return channels


def run_gate_channel(
    repo: Path,
    channel: str,
    capture_dir: Path,
    *,
    timeout_seconds: float,
    test_scope: str | None = None,
) -> VerifierVerdict:
    if channel == "server_analyze":
        return run_server_analyze(repo, capture_dir, timeout_seconds=timeout_seconds)
    if channel == "server_tests":
        return run_server_tests(
            repo, capture_dir, timeout_seconds=timeout_seconds, scope=test_scope
        )
    if channel == "client_analyze":
        return run_client_analyze(repo, capture_dir, timeout_seconds=timeout_seconds)
    if channel == "client_tests":
        return run_client_tests(
            repo, capture_dir, timeout_seconds=timeout_seconds, scope=test_scope
        )
    if channel == "lint_tests":
        return run_lint_plugin_tests(repo, capture_dir, timeout_seconds=timeout_seconds)
    msg = f"unknown gate channel: {channel}"
    raise ValueError(msg)


def run_task_gates(
    repo: Path,
    gate_spec: TaskGateSpec,
    capture_dir: Path,
    *,
    timeout_seconds: float,
    full_suite: bool = True,
) -> list[VerifierVerdict]:
    """Run analyze + tests for task packages. Full suite ignores scoped test path."""
    scope = None if full_suite else gate_spec.test_scope
    verdicts: list[VerifierVerdict] = []
    capture_dir.mkdir(parents=True, exist_ok=True)
    for channel in channels_for_packages(gate_spec.packages):
        v = run_gate_channel(
            repo,
            channel,
            capture_dir,
            timeout_seconds=timeout_seconds,
            test_scope=scope,
        )
        verdicts.append(v)
    return verdicts


def capture_baseline(
    repo: Path,
    packages: set[str],
    capture_dir: Path,
    *,
    timeout_seconds: float,
) -> BaselineSnapshot:
    snap = BaselineSnapshot()
    for pkg in sorted(packages):
        spec = TaskGateSpec(packages=[pkg])
        for channel in channels_for_packages(spec.packages):
            cap = capture_dir / "baseline" / channel
            v = run_gate_channel(repo, channel, cap, timeout_seconds=timeout_seconds)
            snap.suites[channel] = GateSuite(channel=channel, passed=verdict_passes(v), verdict=v)
    return snap


def gates_regressed(
    baseline: BaselineSnapshot,
    verdicts: list[VerifierVerdict],
    channels: list[str],
) -> list[VerifierVerdict]:
    """Return failing verdicts that regressed from a green baseline."""
    by_channel = {channels[i]: verdicts[i] for i in range(min(len(channels), len(verdicts)))}
    regressed: list[VerifierVerdict] = []
    for ch, v in by_channel.items():
        if not verdict_passes(v) and baseline.was_green(ch):
            regressed.append(v)
    return regressed


def summarize_verdicts(verdicts: list[VerifierVerdict]) -> str:
    parts = [f"{v.channel}={v.status}" for v in verdicts]
    return ", ".join(parts)


def tail_output(verdicts: list[VerifierVerdict], *, max_chars: int = 4000) -> str:
    chunks: list[str] = []
    for v in verdicts:
        if v.status == "pass" or not v.raw_output_path:
            continue
        p = Path(v.raw_output_path)
        if p.is_file():
            chunks.append(f"--- {v.channel} ({p.name}) ---\n{p.read_text()[-max_chars:]}")
    text = "\n\n".join(chunks)
    return text[-max_chars:] if len(text) > max_chars else text
