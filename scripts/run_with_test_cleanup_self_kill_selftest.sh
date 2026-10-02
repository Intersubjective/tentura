#!/usr/bin/env bash
# tentura-uh2m: the wrapper's own orphan sweep must not kill the command it
# wraps. kill_orphan_testers matches `frontend_server` anywhere in a process
# cmdline, so a wrapped command whose argv merely mentions
# frontend_server_aot.dart.snapshot (the wrapper itself, `timeout`, `env`, and
# the command all carry it) was SIGTERMed by the pre-run sweep and exited 143
# before the tests started. Does not start Flutter/Dart.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"

# Hermetic like run_with_test_cleanup_selftest.sh: drop an outer run's tag and
# use a private TMPDIR so no outer marker makes the sweeps skip.
if [[ -z "${SELFTEST_ISOLATED:-}" ]]; then
  export SELFTEST_ISOLATED=1
  exec env -u TENTURA_TEST_CLEANUP_RUN \
    TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tentura-selftest.XXXXXX")" \
    bash "$ROOT/scripts/run_with_test_cleanup_self_kill_selftest.sh" "$@"
fi

pass=0
fail=0
cleanup_pids=()

log() { printf '[selftest] %s\n' "$*"; }
ok() { pass=$((pass + 1)); log "PASS: $1"; }
bad() { fail=$((fail + 1)); log "FAIL: $1"; }

still_alive() { kill -0 "$1" 2>/dev/null; }

wait_dead() {
  local pid="$1" n=0
  while (( n < 40 )); do
    still_alive "$pid" || return 0
    sleep 0.1
    n=$((n + 1))
  done
  return 1
}

wait_pidfile() {
  local f="$1" n=0
  while (( n < 50 )); do
    [[ -s "$f" ]] && { cat "$f"; return 0; }
    sleep 0.1
    n=$((n + 1))
  done
  return 1
}

ppid_of() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $2}'; }

# Fixed-point test: the stand-in is orphaned when its parent is neither this
# selftest nor anything the sweep's runner-ownership check could mistake for a
# Flutter/Dart test runner or a wrapped (tagged) command.
is_genuine_orphan() {
  local pid="$1" ppid pcmd penv
  ppid="$(ppid_of "$pid")"
  [[ -n "$ppid" && "$ppid" != "$$" ]] || return 1
  # Braces so a failed /proc redirect (hardened hosts: Permission denied)
  # cannot leak the shell's own error. An unreadable environ belongs to a
  # process of another user (or a hidepid /proc), which cannot be one of this
  # user's tagged wrapped commands, so it never disqualifies the parent.
  pcmd="$({ tr '\0' ' ' <"/proc/$ppid/cmdline"; } 2>/dev/null || true)"
  case "$pcmd" in
    *flutter_tools.snapshot*|*/bin/test.dart*|*/pub/bin/test/test.dart*|*setsid*) return 1 ;;
  esac
  penv="$({ tr '\0' '\n' <"/proc/$ppid/environ"; } 2>/dev/null || true)"
  if grep -q '^TENTURA_TEST_CLEANUP_RUN=' <<<"$penv"; then
    return 1
  fi
  return 0
}

finish() {
  local p
  for p in "${cleanup_pids[@]+"${cleanup_pids[@]}"}"; do
    kill -KILL "$p" 2>/dev/null || true
  done
  if [[ -n "${SELFTEST_ISOLATED:-}" && "${TMPDIR:-}" == */tentura-selftest.* ]]; then
    rm -rf "$TMPDIR"
  fi
  echo
  log "passed=$pass failed=$fail"
  [[ "$fail" -eq 0 ]]
}
trap finish EXIT

SNAP="frontend_server_aot.dart.snapshot"

# --- 1. wrapped command whose argv names the snapshot keeps its exit code ---
OUT="$(mktemp "${TMPDIR:-/tmp}/self_kill_out.XXXXXX")"
STARTED="${TMPDIR:?}/command-started"
set +e
"$WRAP" --timeout 30s -- sh -c ": >\"\$1\"; exit 7 # $SNAP" sh "$STARTED" >"$OUT" 2>&1
rc=$?
set -e
if [[ -f "$STARTED" ]]; then
  ok "wrapped command mentioning $SNAP starts"
else
  bad "wrapped command mentioning $SNAP was killed before starting"
fi
if [[ "$rc" -eq 7 ]]; then
  ok "wrapped command mentioning $SNAP runs to its real exit code"
else
  bad "wrapped command mentioning $SNAP exited $rc, expected 7 (143 = killed by own sweep)"
  sed 's/^/    | /' "$OUT"
fi
if grep -q 'killed orphan test leftovers' "$OUT"; then
  bad "wrapper reported killing orphan leftovers for its own command"
else
  ok "wrapper did not report killing its own command as an orphan"
fi
rm -f "$OUT"
rm -f "$STARTED"

# --- 2. same, through the END-of-run sweep only ---
# While another wrapped run is active the pre-run sweep is skipped, so a decoy
# run lets the command start no matter what the pre-run sweep would do to it.
# The command then releases the decoy and waits until its marker is gone; the
# wrapper's own end-of-run sweep is then the first sweep that scans the process
# table, and it must not SIGTERM the wrapper whose argv names the snapshot.
STATE_DIR="${TMPDIR:?}/tentura-test-cleanup"
RELEASE="$TMPDIR/decoy-release"
OUT2="$(mktemp "${TMPDIR:-/tmp}/self_kill_out2.XXXXXX")"
rm -f "$STARTED" "$RELEASE"
"$WRAP" --timeout 30s -- sh -c 'n=0; until [ -e "$1" ] || [ "$n" -ge 300 ]; do sleep 0.1; n=$((n + 1)); done' sh "$RELEASE" >/dev/null 2>&1 &
DECOY_PID=$!
cleanup_pids+=("$DECOY_PID")
n=0
until compgen -G "$STATE_DIR/*/reaper.pid" >/dev/null || (( n >= 100 )); do sleep 0.1; n=$((n + 1)); done
if ! compgen -G "$STATE_DIR/*/reaper.pid" >/dev/null; then
  bad "decoy wrapped run never became active, end-of-run sweep not exercised"
  : >"$RELEASE"
  wait "$DECOY_PID" 2>/dev/null || true
else
  set +e
  "$WRAP" --timeout 30s -- sh -c ': >"$1"; : >"$2"
n=0
while [ "$n" -lt 200 ]; do
  others="$(find "$3" -mindepth 1 -maxdepth 1 -type d ! -name ".*" ! -name "$TENTURA_TEST_CLEANUP_RUN" 2>/dev/null)"
  [ -z "$others" ] && break
  sleep 0.1; n=$((n + 1))
done
[ -z "$others" ] || exit 9
exit 7 # '"$SNAP" sh "$STARTED" "$RELEASE" "$STATE_DIR" >"$OUT2" 2>&1
  rc=$?
  wait "$DECOY_PID"
  decoy_rc=$?
  set -e
  if [[ "$decoy_rc" -eq 0 ]]; then ok "decoy wrapped run completed"; else bad "decoy wrapped run exited $decoy_rc, expected 0"; fi
  if grep -q 'skipping orphan/tmpfs sweep' "$OUT2"; then
    ok "pre-run sweep was suppressed by the decoy"
  else
    bad "pre-run sweep was not suppressed, so this block does not isolate the end-of-run sweep"
  fi
  if [[ -f "$STARTED" ]]; then ok "command mentioning $SNAP starts under a suppressed pre-run sweep"; else bad "command mentioning $SNAP never started"; fi
  if [[ "$rc" -eq 9 ]]; then
    bad "decoy marker never went away, end-of-run sweep not exercised"
  elif [[ "$rc" -eq 7 ]]; then
    ok "end-of-run sweep leaves the wrapped command's exit code 7 alone"
  else
    bad "end-of-run sweep changed the exit code to $rc, expected 7 (143 = wrapper killed by own sweep)"
    sed 's/^/    | /' "$OUT2"
  fi
fi
rm -f "$STARTED" "$RELEASE" "$OUT2"

# The reported workaround is a control: identical content in a temporary
# script (absent from argv) must start and preserve the command's exit status.
CONTROL="${TMPDIR:?}/wrapped-control.sh"
printf '%s\n' ": >\"\$1\"; exit 7 # $SNAP" >"$CONTROL"
set +e
"$WRAP" --timeout 30s -- sh "$CONTROL" "$STARTED" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 7 && -f "$STARTED" ]]; then
  ok "temporary-script control starts and preserves exit 7"
else
  bad "temporary-script control did not start or exited $rc, expected 7"
fi
rm -f "$STARTED" "$CONTROL"

# --- 3. a real orphan compiler stand-in is still swept ---
# The stand-in publishes its own pid (no process-table guessing) and its argv
# carries a per-run marker, so the pid asserted on is unambiguous. It is only
# trusted as an orphan once its parent is verified to be neither this selftest
# nor a test-runner/tagged process.
ORPHAN_MARK="selftest_self_kill_orphan_$$"
ORPHAN_PIDFILE="${TMPDIR:?}/orphan.pid"
rm -f "$ORPHAN_PIDFILE"
setsid -f python3 -c "import os, sys, time
open(sys.argv[1], 'w').write(str(os.getpid()))
time.sleep(90)  # $SNAP $ORPHAN_MARK" "$ORPHAN_PIDFILE" </dev/null >/dev/null 2>&1
ORPHAN_PID="$(wait_pidfile "$ORPHAN_PIDFILE" || true)"
if [[ -z "$ORPHAN_PID" ]]; then
  bad "failed to spawn orphan frontend_server stand-in"
else
  cleanup_pids+=("$ORPHAN_PID")
  # Reparenting after setsid -f's fork is asynchronous: wait for it.
  n=0
  until is_genuine_orphan "$ORPHAN_PID" || (( n >= 30 )); do sleep 0.1; n=$((n + 1)); done
  if ! tr '\0' ' ' <"/proc/$ORPHAN_PID/cmdline" 2>/dev/null | grep -q -- "$ORPHAN_MARK"; then
    bad "orphan stand-in pid $ORPHAN_PID is not the process carrying marker $ORPHAN_MARK"
  elif ! is_genuine_orphan "$ORPHAN_PID"; then
    bad "orphan stand-in pid $ORPHAN_PID never became a genuine orphan (ppid=$(ppid_of "$ORPHAN_PID"))"
  elif ! still_alive "$ORPHAN_PID"; then
    bad "orphan stand-in pid $ORPHAN_PID died before the sweep ran"
  else
    SWEEP_OUT="$(mktemp "${TMPDIR:-/tmp}/self_kill_sweep.XXXXXX")"
    # A normal wrapped run exercises the same orphan sweep without triggering
    # the database maintenance performed exclusively by --sweep-only.
    "$WRAP" --timeout 30s -- true >"$SWEEP_OUT" 2>&1 || true
    if wait_dead "$ORPHAN_PID"; then ok "orphan frontend_server stand-in still killed"; else bad "orphan frontend_server stand-in survived sweep"; fi
    if grep -Eq "killed orphan test leftovers:.*\\b$ORPHAN_PID\\b" "$SWEEP_OUT"; then
      ok "sweep reported killing orphan pid $ORPHAN_PID"
    else
      bad "sweep did not report killing orphan pid $ORPHAN_PID"
      sed 's/^/    | /' "$SWEEP_OUT"
    fi
    rm -f "$SWEEP_OUT"
  fi
fi

log "done"
