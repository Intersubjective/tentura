#!/usr/bin/env bash
#
# Local/agent test launcher with hang timeout and leftover cleanup.
#
# Do not use in CI — GitHub jobs already run in ephemeral containers.
# Use for every local `flutter test` / `dart test` / `dart analyze` /
# `check-custom-lints.sh` invocation (see AGENTS.md).
#
# Why a detached reaper: Cursor/Claude/Codex often SIGKILL the wrapper
# bash. EXIT traps do not run on SIGKILL. The reaper lives in its own
# session, watches the wrapper PID, then kills tagged descendants and
# drops unreferenced /tmp/flutter_tools.* and /tmp/dart_test.kernel.*,
# and stale disposable `tentura_test_*` Postgres databases
# (those sit on the 31GiB tmpfs and count as RAM).
#
# Preserves: `flutter run` web compilers (`--target=dartdevc`),
# tentura-server, Serena language-server, Chrome, Cursor.
#
# Usage:
#   scripts/run_with_test_cleanup.sh [--timeout 45m] -- flutter test ...
#   scripts/run_with_test_cleanup.sh --sweep-only
#   cd packages/client && ../../scripts/run_with_test_cleanup.sh -- \
#     flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env

set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
STATE_ROOT="${TMPDIR:-/tmp}/tentura-test-cleanup"
DEFAULT_TIMEOUT="45m"
KILL_AFTER="15s"

log() { printf '[test-cleanup] %s\n' "$*" >&2; }

usage() {
  sed -n '2,28p' "$SELF" | sed 's/^# \?//'
  exit 2
}

# Tagged processes carry TENTURA_TEST_CLEANUP_RUN=<id> in environ.
list_tagged_pids() {
  local run_id="$1"
  python3 - "$run_id" <<'PY'
import pathlib, sys
needle = f"TENTURA_TEST_CLEANUP_RUN={sys.argv[1]}".encode()
for p in pathlib.Path("/proc").iterdir():
    if not p.name.isdigit():
        continue
    try:
        env = (p / "environ").read_bytes()
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        continue
    if needle in env.split(b"\0"):
        print(p.name)
PY
}

pid_pgid() {
  python3 - "$1" <<'PY'
import pathlib, sys
pid = sys.argv[1]
try:
    st = (pathlib.Path("/proc") / pid / "stat").read_text()
except (FileNotFoundError, PermissionError):
    raise SystemExit(0)
# comm may contain spaces/parentheses; pgid is field 5 after the last ")"
rest = st[st.rfind(")") + 1 :].split()
print(rest[2])  # pgrp
PY
}

kill_pgid() {
  local sig="$1" pgid="$2"
  [[ -n "$pgid" && "$pgid" != "0" && "$pgid" != "1" ]] || return 0
  kill "-$sig" -- "-$pgid" 2>/dev/null || true
}

kill_tagged_tree() {
  local run_id="$1" pid pgid
  local -A seen=()
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    pgid="$(pid_pgid "$pid" || true)"
    [[ -n "$pgid" ]] || continue
    seen["$pgid"]=1
  done < <(list_tagged_pids "$run_id" || true)
  local g
  if ((${#seen[@]})); then
    for g in "${!seen[@]}"; do
      kill_pgid TERM "$g"
    done
    sleep 2
    for g in "${!seen[@]}"; do
      kill_pgid KILL "$g"
    done
  fi
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -KILL "$pid" 2>/dev/null || true
  done < <(list_tagged_pids "$run_id" || true)
}

# Orphans from a previous SIGKILL'd agent. Do not key off ppid==1:
# systemd user sessions reparent to a subreaper (not PID 1). A live
# `flutter test` tester is a child of flutter_tools.snapshot; after the
# runner dies it is not. Never touch `--target=dartdevc` (web `flutter run`).
kill_orphan_testers() {
  python3 - <<'PY'
import os, pathlib, signal, time

def cmd(pid: str) -> bytes:
    try:
        return (pathlib.Path("/proc") / pid / "cmdline").read_bytes()
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return b""

def ppid_of(pid: str) -> int:
    try:
        st = (pathlib.Path("/proc") / pid / "stat").read_text()
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return 0
    rest = st[st.rfind(")") + 1 :].split()
    return int(rest[1])

def is_web_compiler(blob: bytes) -> bool:
    return b"--target=dartdevc" in blob

def owned_by_flutter_tools(pid: str) -> bool:
    blob = cmd(str(ppid_of(pid)))
    return b"flutter_tools.snapshot" in blob

victims = []
for p in pathlib.Path("/proc").iterdir():
    if not p.name.isdigit():
        continue
    pid = p.name
    blob = cmd(pid)
    if b"flutter_tester" in blob and not owned_by_flutter_tools(pid):
        victims.append(int(pid))
        continue
    if (
        b"frontend_server" in blob
        and not is_web_compiler(blob)
        and not owned_by_flutter_tools(pid)
    ):
        victims.append(int(pid))

for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
if victims:
    time.sleep(1)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
if victims:
    print(" ".join(str(p) for p in victims))
PY
}

sweep_tmpfs() {
  python3 - <<'PY'
import os, pathlib, shutil

def live_cmdlines() -> bytes:
    blobs = []
    for p in pathlib.Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            blobs.append((p / "cmdline").read_bytes())
        except (FileNotFoundError, PermissionError):
            pass
    return b"\n".join(blobs)

live = live_cmdlines()
tmp = pathlib.Path(os.environ.get("TMPDIR", "/tmp"))
removed = []
for pat in ("flutter_tools.*", "dart_test.kernel.*"):
    for d in tmp.glob(pat):
        if not d.exists():
            continue
        token = d.name.encode()
        if token in live:
            continue
        try:
            if d.is_dir():
                shutil.rmtree(d, ignore_errors=True)
            else:
                d.unlink(missing_ok=True)
            removed.append(str(d))
        except OSError:
            pass
if removed:
    print("\n".join(removed))
PY
}

# Drops disposable Postgres databases left behind by killed test runs.
#
# Each pg test creates `tentura_test_*` and drops it in teardown; a SIGKILLed
# run leaves it. They accumulate — 113 were found on 2026-09-20 — and every
# `CREATE DATABASE` the suite issues gets slower, because the catalog and the
# template copy both grow. One run with that backlog took 4:35 against a usual
# 3:30 and failed five unrelated tests on 30-second timeouts.
#
# Runs only under `--sweep-only`, never as part of a test run. Only databases
# with no active connection and older than PG_GC_MIN_AGE_MIN minutes are
# dropped, so a concurrent run's databases are never touched either.
# `tentura_test_tpl_*` are schema templates, deliberately long-lived and
# reused across runs; they are dropped only when superseded, which needs
# `datistemplate` cleared first.
PG_GC_MIN_AGE_MIN="${PG_GC_MIN_AGE_MIN:-120}"

sweep_pg_databases() {
  command -v docker >/dev/null 2>&1 || return 0
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx postgres || return 0

  local keep_tpl
  keep_tpl="$(pg_gc_psql "SELECT datname FROM pg_database
                          WHERE datname LIKE 'tentura_test_tpl_%'" || true)"

  local victims
  victims="$(pg_gc_psql "
    SELECT d.datname
      FROM pg_database d
     WHERE d.datname LIKE 'tentura_test_%'
       AND d.datname NOT LIKE 'tentura_test_tpl_%'
       AND NOT EXISTS (
             SELECT 1 FROM pg_stat_activity a WHERE a.datname = d.datname)
       AND COALESCE(
             (pg_stat_file('base/' || d.oid::text, true)).modification,
             now() - interval '1 day')
           < now() - interval '${PG_GC_MIN_AGE_MIN} minutes'
  " || true)"

  local dropped=0 db
  while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    pg_gc_psql "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)" >/dev/null 2>&1 \
      && dropped=$((dropped + 1))
  done <<<"$victims"

  [[ "$dropped" -gt 0 ]] && log "dropped $dropped stale tentura_test_* database(s)"
  [[ -n "${keep_tpl:-}" ]] && log "kept schema template(s): $(echo "$keep_tpl" | tr '\n' ' ')"
  return 0
}

pg_gc_psql() {
  docker exec postgres psql -U postgres -d postgres -tAc "$1" 2>/dev/null
}

sweep_run() {
  local run_id="$1"
  kill_tagged_tree "$run_id"
  sleep 0.4
  local orphans
  orphans="$(kill_orphan_testers || true)"
  [[ -n "${orphans:-}" ]] && log "killed orphan test leftovers: $orphans"
  local gone
  gone="$(sweep_tmpfs || true)"
  if [[ -n "${gone:-}" ]]; then
    log "removed unreferenced tmpfs:"
    printf '%s\n' "$gone" | sed 's/^/  /' >&2
  fi
}

wait_reaper_ready() {
  local marker="$1" n=0
  while (( n < 40 )); do
    [[ -s "$marker/reaper.pid" ]] && kill -0 "$(cat "$marker/reaper.pid")" 2>/dev/null && return 0
    sleep 0.05
    n=$((n + 1))
  done
  log "warning: reaper did not publish pid"
  return 1
}

run_reaper() {
  local run_id="" parent="" deadline=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id) run_id="$2"; shift 2 ;;
      --parent) parent="$2"; shift 2 ;;
      --deadline) deadline="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local marker="$STATE_ROOT/$run_id"
  mkdir -p "$marker"
  echo "$$" >"$marker/reaper.pid"
  trap '' HUP
  local now
  while true; do
    now="$(date +%s)"
    if [[ -n "$deadline" && "$now" -ge "$deadline" ]]; then
      log "reaper: deadline reached for $run_id"
      break
    fi
    if [[ -n "$parent" ]] && ! kill -0 "$parent" 2>/dev/null; then
      log "reaper: wrapper $parent is gone"
      break
    fi
    if [[ -f "$marker/done" ]]; then
      break
    fi
    sleep 1
  done
  sweep_run "$run_id"
  rm -rf "$marker"
}

parse_duration_seconds() {
  # GNU timeout suffixes: s/m/h/d. Integer or float seconds with no suffix.
  python3 - "$1" <<'PY'
import sys
raw = sys.argv[1].strip().lower()
mult = {"s": 1, "m": 60, "h": 3600, "d": 86400}
if raw[-1:] in mult and raw[:-1].replace(".", "", 1).isdigit():
    print(int(float(raw[:-1]) * mult[raw[-1]]))
elif raw.replace(".", "", 1).isdigit():
    print(int(float(raw)))
else:
    sys.exit(1)
PY
}

main() {
  local timeout="$DEFAULT_TIMEOUT" sweep_only=0
  local -a cmd=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reaper) shift; run_reaper "$@"; exit 0 ;;
      --sweep-only) sweep_only=1; shift ;;
      --timeout)
        timeout="$2"
        shift 2
        ;;
      -h|--help) usage ;;
      --) shift; cmd=("$@"); break ;;
      *) cmd=("$@"); break ;;
    esac
  done

  mkdir -p "$STATE_ROOT"

  if [[ "$sweep_only" -eq 1 ]]; then
    sweep_run "sweep-only-$$"
    # Database GC is maintenance, not part of a test run: a few non-pg-tagged
    # tests still open Postgres connections, and there is no reason to let
    # housekeeping touch the database while any suite might be using it.
    sweep_pg_databases || true
    exit 0
  fi

  if [[ ${#cmd[@]} -eq 0 ]]; then
    usage
  fi

  local secs
  secs="$(parse_duration_seconds "$timeout")" || {
    log "invalid --timeout '$timeout'"
    exit 2
  }

  local run_id
  run_id="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
  local marker="$STATE_ROOT/$run_id"
  mkdir -p "$marker"
  local deadline=$(( $(date +%s) + secs + 45 ))

  # Pre-sweep leftovers from previous killed agents before we start more.
  sweep_run "pre-$run_id"

  log "run $run_id timeout=$timeout cwd=$(pwd)"
  setsid -f -- "$SELF" --reaper --run-id "$run_id" --parent "$$" --deadline "$deadline" \
    </dev/null >>"$marker/reaper.log" 2>&1 || true
  wait_reaper_ready "$marker" || true

  local rc=0
  trap 'rc=143; log "signal, sweeping $run_id"; : >"$marker/done" 2>/dev/null || true; trap - EXIT; sweep_run "$run_id"; exit $rc' INT TERM
  trap ': >"$marker/done" 2>/dev/null || true; sweep_run "$run_id"' EXIT

  # New session so a SIGKILL of this wrapper's process group cannot
  # silently take the reaper — and so leftover testers are findable by
  # environ even if they later reparent to PID 1.
  set +e
  setsid -f -w timeout --kill-after="$KILL_AFTER" -- "$timeout" \
    env TENTURA_TEST_CLEANUP_RUN="$run_id" "${cmd[@]}"
  rc=$?
  set -e

  : >"$marker/done"
  trap - EXIT INT TERM
  sweep_run "$run_id"
  exit "$rc"
}

main "$@"
