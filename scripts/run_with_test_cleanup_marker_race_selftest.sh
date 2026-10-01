#!/usr/bin/env bash
# Marker-dir race checks for scripts/run_with_test_cleanup.sh (tentura-1hx).
#
# A run creates its marker dir (STATE_ROOT/<run_id>) before its reaper has
# published reaper.pid. An earlier run's reaper still sweeping after that run's
# wrapper is gone used to take "no live reaper.pid" to mean "stale" and rm -rf
# the brand-new dir; the victim then lost its reaper and its `done` marker
# ("line NNN: .../done: No such file or directory" after "All tests passed!").
# Behavioural checks only: they do not prescribe how the race is closed.
# Does not start Flutter/Dart.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"
chmod +x "$WRAP"

# Hermetic: drop any outer run tag and use a private TMPDIR (STATE_ROOT derives
# from it), same as run_with_test_cleanup_selftest.sh.
if [[ -z "${SELFTEST_ISOLATED:-}" ]]; then
  export SELFTEST_ISOLATED=1
  exec env -u TENTURA_TEST_CLEANUP_RUN \
    TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tentura-selftest.XXXXXX")" \
    bash "$ROOT/scripts/run_with_test_cleanup_marker_race_selftest.sh" "$@"
fi

pass=0
fail=0

log() { printf '[selftest] %s\n' "$*"; }
ok() { pass=$((pass + 1)); log "PASS: $1"; }
bad() { fail=$((fail + 1)); log "FAIL: $1"; }

finish() {
  if [[ -n "${SELFTEST_ISOLATED:-}" && "${TMPDIR:-}" == */tentura-selftest.* ]]; then
    rm -rf "$TMPDIR"
  fi
  echo
  log "passed=$pass failed=$fail"
  [[ "$fail" -eq 0 ]]
}
trap finish EXIT

STATE_ROOT="${TMPDIR:-/tmp}/tentura-test-cleanup"
mkdir -p "$STATE_ROOT"

# Wait until STATE_ROOT is empty, i.e. every reaper has finished its post-exit
# sweep. Fails (and records it) instead of silently continuing, so a still
# running reaper cannot leak into the next case.
settle() {
  local what="$1" n=0
  while (( n < 300 )); do
    [[ -z "$(ls -A "$STATE_ROOT" 2>/dev/null)" ]] && return 0
    sleep 0.1
    n=$((n + 1))
  done
  bad "$what: reapers did not settle: $(ls -1 "$STATE_ROOT" | tr '\n' ' ')"
  rm -rf "${STATE_ROOT:?}"/* 2>/dev/null || true
  return 1
}

# --- 1. an old marker dir with no reaper.pid is still reclaimed (tentura-2tj) ---
# Also: the wrapped run's own stderr must stay free of shell errors.
OLD="$STATE_ROOT/selftest_old_$$"
mkdir -p "$OLD"
touch -d '1 hour ago' "$OLD"
OUT1="$("$WRAP" --timeout 10s -- sh -c 'echo "All tests passed!"' 2>&1)" || true
settle "case 1" || true
if [[ "$OUT1" == *"No such file or directory"* ]]; then
  bad "case 1: wrapped run leaked a shell error: $(printf '%s' "$OUT1" | grep 'No such file or directory' | head -1)"
elif [[ -d "$OLD" ]]; then
  bad "case 1: old marker dir without reaper.pid leaked instead of being reclaimed"
  rm -rf "$OLD"
else
  ok "case 1: old marker dir without reaper.pid is still reclaimed, run output clean"
fi

# --- 2. the run's own marker deleted mid-run: silent, real exit code kept ---
# The command reports its run id, so the test deletes exactly the wrapper's own
# marker dir (not some other STATE_ROOT entry) and proves it existed.
RUNID_FILE="${TMPDIR}/case2_runid"
OUT2="$(mktemp "${TMPDIR}/case2_out.XXXXXX")"
"$WRAP" --timeout 10s -- sh -c "echo \"\$TENTURA_TEST_CLEANUP_RUN\" >'$RUNID_FILE'; sleep 1; echo 'All tests passed!'; exit 7" >"$OUT2" 2>&1 &
WPID=$!
RUNID=""
for _ in $(seq 1 100); do
  RUNID="$(cat "$RUNID_FILE" 2>/dev/null || true)"
  [[ -n "$RUNID" ]] && break
  sleep 0.05
done
DELETED=0
if [[ -n "$RUNID" && -d "$STATE_ROOT/$RUNID" ]]; then
  rm -rf "${STATE_ROOT:?}/$RUNID"
  DELETED=1
fi
RC=0
wait "$WPID" || RC=$?
if [[ "$DELETED" -ne 1 ]]; then
  bad "case 2: could not delete the wrapper's own marker dir (run id '${RUNID}')"
elif grep -q 'No such file or directory' "$OUT2"; then
  bad "case 2: missing run marker leaked a shell error: $(grep 'No such file or directory' "$OUT2" | head -1)"
elif [[ "$RC" -ne 7 ]]; then
  bad "case 2: missing run marker reported exit $RC, expected 7"
else
  ok "case 2: own marker deleted mid-run is silent and keeps the real exit code"
fi
settle "case 2" || true

# --- 3. previous run's reaper still sweeping while a new run starts ---
# The reported scenario (two separate, non-parallel runs). Run A's wrapper is
# SIGKILLed so only A's detached reaper is left; once it logs that the wrapper
# is gone it spends ~2.4s killing A's tagged command (TERM, sleep 2, KILL,
# sleep 0.4) before it scans for stale marker dirs and removes its own.
# Run B is started only after A's reaper is observed alive and sweeping, and
# the test checks A's reaper is still alive when B's marker dir appears.
# A `sleep` shim on B's PATH only (A's reaper keeps the real one) stretches
# B's pre-sweep `sleep 0.4` to 4s, widening B's pid-less window over A's scan.
# B must keep its marker and reaper and report a clean pass.
SHIMS="$(mktemp -d "${TMPDIR}/shims.XXXXXX")"
cat >"$SHIMS/sleep" <<'SH'
#!/bin/sh
if [ "$1" = "0.4" ]; then exec /bin/sleep 4; fi
exec /bin/sleep "$@"
SH
chmod +x "$SHIMS/sleep"

for round in 1 2; do
  A_OUT="$(mktemp "${TMPDIR}/a_out.XXXXXX")"
  "$WRAP" --timeout 5m -- sleep 300 >"$A_OUT" 2>&1 &
  A_PID=$!
  A_MARKER="" A_REAPER=""
  for _ in $(seq 1 100); do
    for d in "$STATE_ROOT"/*/; do
      [[ -s "$d/reaper.pid" ]] || continue
      p="$(cat "$d/reaper.pid")"
      if kill -0 "$p" 2>/dev/null; then A_MARKER="${d%/}"; A_REAPER="$p"; fi
    done
    [[ -n "$A_MARKER" ]] && break
    sleep 0.05
  done
  if [[ -z "$A_MARKER" ]]; then
    bad "round $round: previous run never published a reaper"
    kill -KILL "$A_PID" 2>/dev/null || true
    wait "$A_PID" 2>/dev/null || true
    settle "round $round" || true
    continue
  fi

  kill -KILL "$A_PID" 2>/dev/null || true
  wait "$A_PID" 2>/dev/null || true

  # Wait for A's reaper to notice and enter its post-exit sweep.
  swept=0
  for _ in $(seq 1 100); do
    if grep -q 'is gone' "$A_MARKER/reaper.log" 2>/dev/null; then swept=1; break; fi
    sleep 0.05
  done
  if [[ "$swept" -ne 1 ]] || ! kill -0 "$A_REAPER" 2>/dev/null; then
    bad "round $round: previous run's reaper never entered a live post-exit sweep"
    settle "round $round" || true
    continue
  fi

  B_OUT="$(mktemp "${TMPDIR}/b_out.XXXXXX")"
  B_RC_FILE="$(mktemp "${TMPDIR}/b_rc.XXXXXX")"
  (
    rc=0
    PATH="$SHIMS:$PATH" "$WRAP" --timeout 10s -- sh -c \
      'if [ -d "$TMPDIR/tentura-test-cleanup/$TENTURA_TEST_CLEANUP_RUN" ]; then echo marker=present; else echo marker=missing; fi; echo "All tests passed!"' \
      >"$B_OUT" 2>&1 || rc=$?
    echo "$rc" >"$B_RC_FILE"
  ) &
  B_PID=$!

  # Overlap proof: B's marker dir shows up while A's reaper is still sweeping.
  overlap=0
  for _ in $(seq 1 100); do
    for d in "$STATE_ROOT"/*/; do
      [[ "${d%/}" == "$A_MARKER" ]] && continue
      if kill -0 "$A_REAPER" 2>/dev/null && [[ -d "$A_MARKER" ]]; then overlap=1; fi
      break 2
    done
    sleep 0.05
  done
  wait "$B_PID" || true

  B_RC="$(cat "$B_RC_FILE")"
  B_TEXT="$(cat "$B_OUT")"
  why=""
  [[ "$overlap" -eq 1 ]] || why="$why; previous run's reaper was not sweeping when the new run started"
  [[ "$B_RC" -eq 0 ]] || why="$why; exit $B_RC"
  [[ "$B_TEXT" == *"All tests passed!"* ]] || why="$why; no 'All tests passed!'"
  [[ "$B_TEXT" == *"marker=present"* ]] || why="$why; own marker dir was deleted by the previous run's reaper"
  [[ "$B_TEXT" != *"reaper did not publish pid"* ]] || why="$why; reaper never started"
  [[ "$B_TEXT" != *"No such file or directory"* ]] || why="$why; leaked 'No such file or directory'"
  if [[ -z "$why" ]]; then
    ok "round $round: new run unharmed by the previous run's still-sweeping reaper"
  else
    bad "round $round: new run harmed by previous run's reaper:${why#;} -- output: $(printf '%s' "$B_TEXT" | tr '\n' '|')"
  fi
  settle "round $round" || true
  rm -f "$A_OUT" "$B_OUT" "$B_RC_FILE"
done
rm -rf "$SHIMS"

log "done"
