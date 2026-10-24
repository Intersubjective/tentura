#!/usr/bin/env bash
# A wrapped run whose launcher died must not outlive it.
#
# Agent sandboxes SIGKILL their own process, not the wrapper they spawned; the
# wrapper is reparented to the init subreaper and keeps its test command (and
# that command's multi-GB /tmp/flutter_tools.* cache) alive until --timeout,
# starving every concurrent run of tmpfs. Does not start Flutter/Dart — only
# sleeping stand-ins.
set -euo pipefail
# Overlapping wrapped runs on purpose: stay outside the machine-wide test
# queue (run_with_test_cleanup_selftest.sh section 15 covers the queue).
export TENTURA_TEST_LOCK=off
unset TENTURA_TEST_LOCK_HELD

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"

# Hermetic like run_with_test_cleanup_selftest.sh: drop an outer run's tag and
# use a private TMPDIR (STATE_ROOT and the tmpfs fixtures derive from it).
if [[ -z "${SELFTEST_ISOLATED:-}" ]]; then
  export SELFTEST_ISOLATED=1
  exec env -u TENTURA_TEST_CLEANUP_RUN \
    TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tentura-selftest.XXXXXX")" \
    bash "$ROOT/scripts/run_with_test_cleanup_orphaned_launcher_selftest.sh" "$@"
fi

pass=0
fail=0
cleanup_pids=()
cleanup_marks=()
TEARDOWN_SECS=15

log() { printf '[selftest] %s\n' "$*"; }
ok() { pass=$((pass + 1)); log "PASS: $1"; }
bad() { fail=$((fail + 1)); log "FAIL: $1"; }

still_alive() { kill -0 "$1" 2>/dev/null; }

# Polls once a second, up to TEARDOWN_SECS.
wait_until() {
  local n=0
  while (( n < TEARDOWN_SECS * 5 )); do
    "$@" && return 0
    sleep 0.2
    n=$((n + 1))
  done
  return 1
}

is_dead() { ! still_alive "$1"; }
is_gone() { [[ ! -e "$1" ]]; }

pid_by_marker() {
  python3 - "$1" <<'PY'
import os, pathlib, sys
mark = sys.argv[1].encode()
for p in pathlib.Path("/proc").iterdir():
    # The scanner's own argv carries the marker too.
    if not p.name.isdigit() or int(p.name) == os.getpid():
        continue
    try:
        cmd = (p / "cmdline").read_bytes()
        comm = (p / "comm").read_text().strip()
    except (FileNotFoundError, PermissionError):
        continue
    if mark in cmd and comm.startswith("python"):
        print(p.name)
        break
PY
}

kill_marked() {
  python3 - "$1" <<'PY'
import os, pathlib, signal, sys
mark = sys.argv[1].encode()
me = os.getpid()
for p in pathlib.Path("/proc").iterdir():
    if not p.name.isdigit() or int(p.name) == me:
        continue
    try:
        if mark in (p / "cmdline").read_bytes():
            os.kill(int(p.name), signal.SIGKILL)
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
PY
}

finish() {
  local p m
  for p in "${cleanup_pids[@]+"${cleanup_pids[@]}"}"; do
    kill -KILL "$p" 2>/dev/null || true
  done
  for m in "${cleanup_marks[@]+"${cleanup_marks[@]}"}"; do
    kill_marked "$m"
  done
  if [[ -n "${SELFTEST_ISOLATED:-}" && "${TMPDIR:-}" == */tentura-selftest.* ]]; then
    rm -rf "$TMPDIR"
  fi
  echo
  log "passed=$pass failed=$fail"
  [[ "$fail" -eq 0 ]]
}
trap finish EXIT

# Starts "<launcher bash> -> wrapper -> sleeping python" and prints the
# launcher pid. The inner `wait` keeps bash from exec-ing the wrapper, so the
# wrapper really is a child of a separate, killable launcher.
spawn_launched_wrapper() {
  local mark="$1"
  bash -c '"$1" --timeout 60s -- python3 -c "$2" </dev/null >/dev/null 2>&1 & wait' \
    _ "$WRAP" "import time; time.sleep(90)  # $mark" </dev/null >/dev/null 2>&1 &
  echo $!
}

await_child_pid() {
  local launcher="$1" pid="" n=0
  while (( n < 50 )); do
    pid="$(pgrep -P "$launcher" | head -1 || true)"
    [[ -n "$pid" ]] && break
    sleep 0.1
    n=$((n + 1))
  done
  echo "$pid"
}

await_marker_pid() {
  local mark="$1" pid="" n=0
  while (( n < 50 )); do
    pid="$(pid_by_marker "$mark")"
    [[ -n "$pid" ]] && break
    sleep 0.1
    n=$((n + 1))
  done
  echo "$pid"
}

# --- 1. launcher SIGKILLed: wrapped command, wrapper and tmpfs cache go away ---
# The cache dir's name sits in the wrapped command's argv, which is exactly
# what makes the tmpfs sweep treat it as "referenced by a live process".
ORPHAN_MARK="selftest_orphaned_launcher_$$"
CACHE_DIR="${TMPDIR:?}/flutter_tools.orphaned$$"
mkdir -p "$CACHE_DIR"
head -c 1048576 /dev/zero >"$CACHE_DIR/kernel.dill"
cleanup_marks+=("$ORPHAN_MARK")
LAUNCHER="$(spawn_launched_wrapper "$ORPHAN_MARK $CACHE_DIR")"
cleanup_pids+=("$LAUNCHER")
WRAPPER_PID="$(await_child_pid "$LAUNCHER")"
CHILD_PID="$(await_marker_pid "$ORPHAN_MARK")"
if [[ -z "$WRAPPER_PID" || -z "$CHILD_PID" ]]; then
  bad "orphan case: wrapper='$WRAPPER_PID' wrapped command='$CHILD_PID' never appeared"
else
  cleanup_pids+=("$WRAPPER_PID")
  kill -KILL "$LAUNCHER" 2>/dev/null || true
  wait "$LAUNCHER" 2>/dev/null || true
  if wait_until is_dead "$CHILD_PID"; then
    ok "wrapped command of a dead launcher is killed"
  else
    bad "wrapped command $CHILD_PID of a dead launcher still alive after ${TEARDOWN_SECS}s"
  fi
  if wait_until is_dead "$WRAPPER_PID"; then
    ok "wrapper of a dead launcher exits"
  else
    bad "wrapper $WRAPPER_PID of a dead launcher still alive after ${TEARDOWN_SECS}s"
  fi
  if wait_until is_gone "$CACHE_DIR"; then
    ok "tmpfs cache of a dead launcher's run is reclaimed"
  else
    bad "tmpfs cache $CACHE_DIR of a dead launcher's run survived"
  fi
fi

# --- 2. a concurrent run whose launcher is alive is left alone ---
ORPHAN2_MARK="selftest_orphaned_launcher_two_$$"
PEER_MARK="selftest_live_peer_$$"
cleanup_marks+=("$ORPHAN2_MARK" "$PEER_MARK")
PEER_LAUNCHER="$(spawn_launched_wrapper "$PEER_MARK")"
cleanup_pids+=("$PEER_LAUNCHER")
LAUNCHER2="$(spawn_launched_wrapper "$ORPHAN2_MARK")"
cleanup_pids+=("$LAUNCHER2")
PEER_PID="$(await_marker_pid "$PEER_MARK")"
CHILD2_PID="$(await_marker_pid "$ORPHAN2_MARK")"
WRAPPER2_PID="$(await_child_pid "$LAUNCHER2")"
if [[ -z "$PEER_PID" || -z "$CHILD2_PID" || -z "$WRAPPER2_PID" ]]; then
  bad "peer case: peer='$PEER_PID' orphan='$CHILD2_PID' wrapper='$WRAPPER2_PID' never appeared"
else
  cleanup_pids+=("$WRAPPER2_PID")
  kill -KILL "$LAUNCHER2" 2>/dev/null || true
  wait "$LAUNCHER2" 2>/dev/null || true
  if wait_until is_dead "$CHILD2_PID"; then
    ok "orphaned run is killed while another wrapped run is active"
  else
    bad "orphaned run $CHILD2_PID survived because another wrapped run is active"
  fi
  if still_alive "$PEER_PID"; then
    ok "concurrent run with a live launcher is not killed"
  else
    bad "concurrent run with a live launcher was killed"
  fi
fi

# --- 3. a wrapper started already detached keeps running its command ---
# `setsid -f` launches (nohup-style background runs) have no live launcher to
# lose, so they must run to completion rather than be treated as orphans.
DETACHED_DONE="${TMPDIR:?}/detached-done"
setsid -f bash -c 'sleep 0.5; exec "$1" --timeout 30s -- sh -c "sleep 3; touch \"\$1\"" _ "$2"' \
  _ "$WRAP" "$DETACHED_DONE" </dev/null >/dev/null 2>&1
n=0
while [[ ! -e "$DETACHED_DONE" && "$n" -lt 100 ]]; do
  sleep 0.1
  n=$((n + 1))
done
if [[ -e "$DETACHED_DONE" ]]; then
  ok "wrapper started detached runs its command to completion"
else
  bad "wrapper started detached was torn down before its command finished"
fi

log "done"
