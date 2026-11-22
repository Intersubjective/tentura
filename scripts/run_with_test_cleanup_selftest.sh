#!/usr/bin/env bash
# Induced-crash checks for scripts/run_with_test_cleanup.sh.
# Does not start Flutter/Dart — only hang/orphan/tmpfs stand-ins.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"
chmod +x "$WRAP"

# Stay hermetic when invoked from inside an outer wrapped run: the outer run
# id sits in this process's /proc environ and the outer marker dir in the
# shared STATE_ROOT, and either one makes every inner wrapper sweep below
# report "another wrapped run is active" and skip — failing the sweep
# assertions. Re-exec once without the outer tag and with a private TMPDIR
# (STATE_ROOT and the tmpfs fixtures both derive from it).
if [[ -z "${SELFTEST_ISOLATED:-}" ]]; then
  export SELFTEST_ISOLATED=1
  # The cleanup scenarios below start overlapping wrapped runs on purpose, so
  # they run outside the machine-wide queue; section 15 tests the queue itself.
  exec env -u TENTURA_TEST_CLEANUP_RUN -u TENTURA_TEST_LOCK_HELD TENTURA_TEST_LOCK=off \
    TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tentura-selftest.XXXXXX")" \
    bash "$ROOT/scripts/run_with_test_cleanup_selftest.sh" "$@"
fi

pass=0
fail=0
cleanup_pids=()

log() { printf '[selftest] %s\n' "$*"; }
ok() { pass=$((pass + 1)); log "PASS: $1"; }
bad() { fail=$((fail + 1)); log "FAIL: $1"; }

still_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

wait_dead() {
  local pid="$1" n=0
  while (( n < 40 )); do
    still_alive "$pid" || return 0
    sleep 0.1
    n=$((n + 1))
  done
  return 1
}

pid_by_marker() {
  local marker="$1"
  python3 - "$marker" <<'PY'
import pathlib, sys
mark = sys.argv[1].encode()
for p in pathlib.Path("/proc").iterdir():
    if not p.name.isdigit():
        continue
    try:
        args = (p / "cmdline").read_bytes().split(b"\0")[1:]
        comm = (p / "comm").read_text().strip()
    except (FileNotFoundError, PermissionError):
        continue
    # Fixtures run inline Python. The lookup and watchdog also carry the
    # marker in argv, but neither runs an inline program.
    if args[:1] == [b"-u"]:
        args = args[1:]
    if (
        comm.startswith("python")
        and args[:1] == [b"-c"]
        and any(mark in arg for arg in args[1:])
    ):
        print(p.name)
        break
PY
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

check_marker_lookup() {
  local marker="selftest_marker_lookup_${BASHPID}_${RANDOM}_${RANDOM}"
  local ready found fixture_pid
  coproc MARKER_FIXTURE {
    exec python3 -u -c 'import sys; print("ready"); sys.stdin.read()' "$marker"
  }
  fixture_pid="$MARKER_FIXTURE_PID"
  if ! IFS= read -r -t 5 -u "${MARKER_FIXTURE[0]}" ready || [[ "$ready" != ready ]]; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
    bad "marker lookup fixture did not start"
    return
  fi
  found="$(pid_by_marker "$marker")"
  kill "$fixture_pid"
  wait "$fixture_pid" 2>/dev/null || true
  if [[ "$found" != "$fixture_pid" ]]; then
    bad "marker lookup returned '$found' for live fixture PID $fixture_pid"
    return
  fi

  found="$(pid_by_marker "$marker")"
  if [[ -z "$found" ]]; then
    ok "marker lookup returns no PID after the matching fixture exits"
  else
    bad "marker lookup returned PID $found after the matching fixture exited"
  fi
}

check_sigterm() {
  local inactivity="$1" label="inactivity=$1" wrapper_pid child_pid="" rc=0
  local fixture="$TMPDIR/selftest_sigterm_${BASHPID}_${RANDOM}"
  "$WRAP" --timeout 6s --inactivity "$inactivity" -- \
    python3 -c 'import os, pathlib, sys, time
assert input() == "ready"
pathlib.Path(sys.argv[1]).write_text(str(os.getpid()))
time.sleep(20)' "$fixture.pid" <<<ready >"$fixture.log" 2>&1 &
  wrapper_pid=$!
  for _ in $(seq 1 30); do
    if [[ -s "$fixture.pid" ]]; then
      child_pid="$(cat "$fixture.pid")"
      break
    fi
    sleep 0.1
  done
  if [[ -z "$child_pid" ]] || ! kill -TERM "$wrapper_pid"; then
    bad "SIGTERM ($label): fixture did not reach the wrapped command"
  else
    if wait_dead "$child_pid"; then
      ok "SIGTERM ($label) stops the child before the 6s timeout"
    else
      bad "SIGTERM ($label) left the child running until the timeout"
    fi
  fi
  wait "$wrapper_pid" || rc=$?
  if [[ "$rc" -eq 143 ]]; then
    ok "SIGTERM ($label) returns 143"
  else
    bad "SIGTERM ($label) returned $rc, expected 143"
    cat "$fixture.log"
  fi
}

if [[ "${1:-}" == --sigterm-only ]]; then
  check_sigterm 10m
  check_sigterm 0
  exit "$((fail != 0))"
fi

check_web_tmpfs_sweep() {
  local old_compiler="$TMPDIR/flutter_tools.abandoned-compiler-$$"
  local old_chrome="$TMPDIR/flutter_tools.abandoned-chrome-$$"
  local old_mixed="$TMPDIR/flutter_tools.abandoned-mixed-$$"
  local fresh_compiler="$TMPDIR/flutter_tools.fresh-compiler-$$"
  local fresh_chrome="$TMPDIR/flutter_tools.fresh-chrome-$$"
  local recent_write="$TMPDIR/flutter_tools.recent-write-$$"
  local kernel="$TMPDIR/dart_test.kernel.unreferenced-$$"
  local compiler_dirs chrome_dirs
  mkdir -p "$old_compiler/flutter_tool.build" "$old_chrome/flutter_test.output" \
    "$old_mixed/flutter_tool.build" "$old_mixed/flutter_test.output" \
    "$fresh_compiler/flutter_tool.build" "$fresh_chrome/flutter_test.output" \
    "$recent_write/flutter_tool.build" "$recent_write/flutter_test.output" "$kernel"
  printf '%s\n' 'compiled kernel' >"$old_compiler/flutter_tool.build/app.dill"
  printf '%s\n' 'Chrome output' >"$old_chrome/flutter_test.output/test.js"
  printf '%s\n' 'compiled kernel' >"$old_mixed/flutter_tool.build/app.dill"
  printf '%s\n' 'Chrome output' >"$old_mixed/flutter_test.output/test.js"
  printf '%s\n' 'Chrome output' >"$recent_write/flutter_test.output/test.js"
  find "$old_compiler" "$old_chrome" "$old_mixed" "$recent_write" -exec touch -d '1 day ago' {} +
  printf '%s\n' 'recent compilation' >"$recent_write/flutter_tool.build/app.dill"
  touch -d '1 day ago' "$recent_write" "$recent_write/flutter_tool.build"

  if [[ ! -f "$old_compiler/flutter_tool.build/app.dill" ||
        ! -f "$old_chrome/flutter_test.output/test.js" ||
        ! -f "$old_mixed/flutter_tool.build/app.dill" ||
        ! -f "$old_mixed/flutter_test.output/test.js" ]]; then
    bad "abandoned web fixtures are missing nested artifacts before the sweep"
    return
  fi
  # Record both directories so deletion followed by recreation fails as well.
  compiler_dirs="$(stat -c '%d:%i:%w' "$fresh_compiler" "$fresh_compiler/flutter_tool.build")"
  chrome_dirs="$(stat -c '%d:%i:%w' "$fresh_chrome" "$fresh_chrome/flutter_test.output")"

  if ! TENTURA_TEST_CLEANUP_SYSTEM_TMP="$TMPDIR" "$WRAP" --sweep-only; then
    bad "web directory sweep did not exit 0"
  elif [[ -e "$kernel" ]]; then
    bad "web directory sweep did not remove the unreferenced Dart kernel"
  else
    if [[ ! -e "$old_compiler" && ! -e "$old_compiler/flutter_tool.build" &&
          ! -e "$old_compiler/flutter_tool.build/app.dill" ]]; then
      ok "abandoned compiler dir removed"
    else
      bad "abandoned compiler dir survived"
    fi
    if [[ ! -e "$old_chrome" && ! -e "$old_chrome/flutter_test.output" &&
          ! -e "$old_chrome/flutter_test.output/test.js" ]]; then
      ok "abandoned flutter_test dir removed"
    else
      bad "abandoned flutter_test dir survived"
    fi
    if [[ ! -e "$old_mixed" && ! -e "$old_mixed/flutter_tool.build" &&
          ! -e "$old_mixed/flutter_tool.build/app.dill" &&
          ! -e "$old_mixed/flutter_test.output" &&
          ! -e "$old_mixed/flutter_test.output/test.js" ]]; then
      ok "abandoned compiler and Chrome output removed from the same tree"
    else
      bad "abandoned mixed web directory or nested output survived"
    fi
    if [[ -d "$fresh_compiler" && -d "$fresh_compiler/flutter_tool.build" ]] &&
      [[ "$(stat -c '%d:%i:%w' "$fresh_compiler" "$fresh_compiler/flutter_tool.build")" == "$compiler_dirs" ]]; then
      ok "fresh compiler dir kept"
    else
      bad "fresh compiler tree or nested dir deleted or replaced before app.dill was written"
    fi
    if [[ -d "$fresh_chrome" && -d "$fresh_chrome/flutter_test.output" ]] &&
      [[ "$(stat -c '%d:%i:%w' "$fresh_chrome" "$fresh_chrome/flutter_test.output")" == "$chrome_dirs" ]]; then
      ok "fresh flutter_test dir kept"
    else
      bad "fresh Chrome tree or nested dir deleted or replaced"
    fi
    if cmp -s "$recent_write/flutter_tool.build/app.dill" <(printf '%s\n' 'recent compilation') &&
      cmp -s "$recent_write/flutter_test.output/test.js" <(printf '%s\n' 'Chrome output'); then
      ok "deep recent write kept"
    else
      bad "recently written app.dill or its older Chrome sibling deleted or changed"
    fi
  fi
}

check_referenced_web_tmpfs_sweep() {
  local referenced="$TMPDIR/flutter_tools.referenced-compiler-$$"
  local app_dill="$referenced/flutter_tool.build/app.dill"
  local chrome_output="$referenced/flutter_test.output/test.js"
  local kernel="$TMPDIR/dart_test.kernel.live-owner-control-$$"
  local ready owner_pid
  mkdir -p "$(dirname "$app_dill")" "$(dirname "$chrome_output")" "$kernel"
  printf '%s\n' 'compiled kernel' >"$app_dill"
  printf '%s\n' 'Chrome output' >"$chrome_output"
  find "$referenced" -exec touch -d '1 day ago' {} +

  coproc WEB_TMPFS_OWNER {
    exec python3 -u -c 'import time; print("ready"); time.sleep(30)' "$referenced"
  }
  owner_pid="$WEB_TMPFS_OWNER_PID"
  if ! IFS= read -r -t 5 -u "${WEB_TMPFS_OWNER[0]}" ready || [[ "$ready" != ready ]] ||
     ! grep -Fxzq -- "$referenced" "/proc/$owner_pid/cmdline"; then
    bad "live compiler fixture did not expose its directory in argv"
  elif ! TENTURA_TEST_CLEANUP_SYSTEM_TMP="$TMPDIR" "$WRAP" --sweep-only; then
    bad "sweep with a live compiler reference did not exit 0"
  elif [[ -e "$kernel" ]]; then
    bad "sweep with a live compiler reference did not remove the unrelated Dart kernel"
  elif still_alive "$owner_pid" &&
    cmp -s "$app_dill" <(printf '%s\n' 'compiled kernel') &&
    cmp -s "$chrome_output" <(printf '%s\n' 'Chrome output'); then
    ok "referenced old dir kept"
  else
    bad "sweep deleted or changed referenced web output or stopped its live owner"
  fi
  kill "$owner_pid" 2>/dev/null || true
  wait "$owner_pid" 2>/dev/null || true

  # Sweep the same tree again with identical mtimes and no live reference.
  if ! TENTURA_TEST_CLEANUP_SYSTEM_TMP="$TMPDIR" "$WRAP" --sweep-only; then
    bad "sweep after the compiler reference exited did not exit 0"
  elif [[ ! -e "$referenced" && ! -e "$app_dill" && ! -e "$chrome_output" ]]; then
    ok "old compiler dir removed after its live reference exited"
  else
    bad "old compiler dir survived after its live reference exited"
  fi
}

check_locked_web_tmpfs_sweep() {
  local workspace artifact owner_pid
  local kernel="$TMPDIR/dart_test.kernel.locked-web-control-$$"
  mkdir "$kernel"
  coproc LOCKED_WEB_OWNER {
    exec bash "$ROOT/scripts/with_web_compiler_tmp.sh" python3 -u -c '
import os, pathlib, time
workspace = pathlib.Path(os.environ["TMPDIR"])
output = workspace / "flutter_tools.sdk" / "flutter_tool.build" / "app.dill"
output.parent.mkdir(parents=True)
output.write_text("compiled kernel")
print(workspace)
time.sleep(30)
'
  }
  owner_pid="$LOCKED_WEB_OWNER_PID"
  if ! IFS= read -r -t 5 -u "${LOCKED_WEB_OWNER[0]}" workspace; then
    bad "locked web compiler fixture did not start"
    kill "$owner_pid" 2>/dev/null || true
    wait "$owner_pid" 2>/dev/null || true
    return
  fi
  artifact="$workspace/flutter_tools.sdk/flutter_tool.build/app.dill"
  find "$workspace" -exec touch -d '1 day ago' {} +

  # The workspace appears only in the compiler's environment. A PID namespace
  # that cannot see its argv has the same lack of references in the sweep.
  if grep -Fq -- "${workspace##*/}" "/proc/$owner_pid/cmdline"; then
    bad "locked web compiler fixture exposed its workspace in argv"
  elif ! TENTURA_TEST_CLEANUP_SYSTEM_TMP="$TMPDIR" "$WRAP" --sweep-only; then
    bad "sweep with a locked web compiler did not exit 0"
  elif [[ -e "$kernel" ]]; then
    bad "locked web workspace prevented cleanup of an unrelated Dart kernel"
  elif still_alive "$owner_pid" && cmp -s "$artifact" <(printf '%s' 'compiled kernel'); then
    ok "locked web workspace kept without an argv reference"
  else
    bad "sweep deleted or changed the locked web workspace"
  fi

  kill -KILL "$owner_pid" 2>/dev/null || true
  wait "$owner_pid" 2>/dev/null || true
  if ! TENTURA_TEST_CLEANUP_SYSTEM_TMP="$TMPDIR" "$WRAP" --sweep-only; then
    bad "sweep after the locked web compiler died did not exit 0"
  elif [[ -e "$workspace" ]]; then
    bad "unlocked web workspace survived after its owner died"
  else
    ok "web workspace reclaimed after its owner was killed"
  fi
}

if [[ "${1:-}" == --web-tmpfs-only ]]; then
  check_web_tmpfs_sweep
  check_referenced_web_tmpfs_sweep
  check_locked_web_tmpfs_sweep
  exit "$((fail != 0))"
fi

check_marker_lookup
if [[ "${1:-}" == --marker-lookup-only ]]; then
  exit "$((fail != 0))"
fi

# --- 1. unreferenced tmpfs dirs go away; referenced dirs stay ---
KEEP_DIR="${TMPDIR:-/tmp}/flutter_tools.selftestkeep$$"
GONE_DIR="${TMPDIR:-/tmp}/flutter_tools.selftestgone$$"
KERNEL_GONE="${TMPDIR:-/tmp}/dart_test.kernel.selftestgone$$"
mkdir -p "$KEEP_DIR" "$GONE_DIR" "$KERNEL_GONE"
python3 - "$KEEP_DIR" <<'PY' &
import sys, time
time.sleep(30)
PY
KEEP_PID=$!
cleanup_pids+=("$KEEP_PID")
sleep 0.2
"$WRAP" --sweep-only >/dev/null
if [[ -d "$KEEP_DIR" ]]; then ok "referenced flutter_tools dir kept"; else bad "referenced flutter_tools dir deleted"; fi
if [[ ! -d "$GONE_DIR" ]]; then ok "unreferenced flutter_tools dir removed"; else bad "unreferenced flutter_tools dir survived"; fi
if [[ ! -d "$KERNEL_GONE" ]]; then ok "unreferenced dart_test.kernel dir removed"; else bad "unreferenced dart_test.kernel dir survived"; fi

check_web_tmpfs_sweep
check_referenced_web_tmpfs_sweep
check_locked_web_tmpfs_sweep

# --- 2. PID-1 flutter_tester stand-in is killed; dartdevc compiler is not ---
TESTER_MARK="selftest_flutter_tester_$$"
WEB_MARK="selftest_frontend_server_dartdevc_$$"
setsid -f python3 -c "import time; time.sleep(90)  # flutter_tester $TESTER_MARK" </dev/null
setsid -f python3 -c "import time; time.sleep(90)  # frontend_server --target=dartdevc $WEB_MARK" </dev/null
sleep 0.3
TESTER_PID="$(pid_by_marker "$TESTER_MARK")"
WEB_PID="$(pid_by_marker "$WEB_MARK")"
cleanup_pids+=("$WEB_PID")
if [[ -z "$TESTER_PID" || -z "$WEB_PID" ]]; then
  bad "failed to spawn tester/web stand-ins (tester='$TESTER_PID' web='$WEB_PID')"
else
  "$WRAP" --sweep-only >/dev/null
  if wait_dead "$TESTER_PID"; then ok "PID-1 flutter_tester stand-in killed"; else bad "PID-1 flutter_tester stand-in still alive"; fi
  if still_alive "$WEB_PID"; then ok "dartdevc compiler stand-in preserved"; else bad "dartdevc compiler stand-in killed"; fi
fi

# --- 3. normal exit ---
if "$WRAP" --timeout 10s -- true; then ok "true exits 0"; else bad "true did not exit 0"; fi

# --- 4. timeout kills a hang ---
HANG_MARK="selftest_timeout_hang_$$"
set +e
"$WRAP" --timeout 2s -- python3 -c "import time; time.sleep(90)  # $HANG_MARK"
to_rc=$?
set -e
HANG_PID="$(pid_by_marker "$HANG_MARK")"
if [[ "$to_rc" -eq 124 ]]; then ok "timeout returns 124"; else bad "timeout rc=$to_rc want 124"; fi
if [[ -z "$HANG_PID" ]] || wait_dead "$HANG_PID"; then ok "timed-out hang is gone"; else bad "timed-out hang pid $HANG_PID still alive"; fi

# --- 5. SIGTERM wrapper kills tagged children ---
check_sigterm 10m
check_sigterm 0

# --- 6. SIGKILL wrapper: EXIT trap cannot run; reaper must ---
KILL_MARK="selftest_sigkill_child_$$"
"$WRAP" --timeout 60s -- python3 -c "import time; time.sleep(90)  # $KILL_MARK" &
WPID=$!
cleanup_pids+=("$WPID")
for _ in $(seq 1 40); do
  KILL_PID="$(pid_by_marker "$KILL_MARK")"
  [[ -n "$KILL_PID" ]] && break
  sleep 0.1
done
if [[ -z "${KILL_PID:-}" ]]; then
  bad "SIGKILL case: child never appeared"
else
  kill -KILL "$WPID" 2>/dev/null || true
  wait "$WPID" 2>/dev/null || true
  # reaper polls every 1s
  for _ in $(seq 1 25); do
    still_alive "$KILL_PID" || break
    sleep 0.2
  done
  if wait_dead "$KILL_PID"; then ok "SIGKILL wrapper: reaper kills tagged child"; else bad "SIGKILL wrapper left child $KILL_PID (reaper gap)"; fi
fi

# --- 7. child that setsid's itself (new session) still dies on timeout ---
NEST_MARK="selftest_nested_setsid_$$"
set +e
"$WRAP" --timeout 2s -- setsid -f python3 -c "import time; time.sleep(90)  # $NEST_MARK"
nest_rc=$?
set -e
NEST_PID="$(pid_by_marker "$NEST_MARK")"
# `setsid -f` returns 0 immediately; EXIT sweep must still reap the grandchild.
if [[ -z "$NEST_PID" ]] || wait_dead "$NEST_PID"; then ok "nested setsid child reaped (cmd rc=$nest_rc)"; else bad "nested setsid child $NEST_PID survived wrapper return"; fi

# --- 8. unrelated hang without the env var survives a sweep-only ---
OTHER_MARK="selftest_unrelated_hang_$$"
setsid -f python3 -c "import time; time.sleep(90)  # $OTHER_MARK no-flutter" </dev/null
sleep 0.2
OTHER_PID="$(pid_by_marker "$OTHER_MARK")"
cleanup_pids+=("$OTHER_PID")
"$WRAP" --sweep-only >/dev/null
if still_alive "$OTHER_PID"; then ok "unrelated process not swept"; else bad "sweep-only killed unrelated $OTHER_PID"; fi

# --- 9. SIGKILL of the wrapper's own session (not the caller's group) ---
PGRP_MARK="selftest_pgrp_kill_$$"
# Without job control, setsid can exec in place and $! is the new group ID.
set +m
setsid "$WRAP" --timeout 60s -- python3 -c "import time; time.sleep(90)  # $PGRP_MARK" </dev/null &
WPID=$!
for _ in $(seq 1 40); do
  PGRP_PID="$(pid_by_marker "$PGRP_MARK")"
  [[ -n "$PGRP_PID" ]] && break
  sleep 0.1
done
if [[ -z "$PGRP_PID" ]]; then
  bad "PGID SIGKILL case: wrapper='$WPID' child='$PGRP_PID'"
elif ! kill -KILL -- "-$WPID" 2>/dev/null; then
  bad "could not SIGKILL wrapper group $WPID"
else
  wait "$WPID" 2>/dev/null || true
  for _ in $(seq 1 25); do
    still_alive "$PGRP_PID" || break
    sleep 0.2
  done
  if wait_dead "$PGRP_PID"; then ok "wrapper-session SIGKILL: reaper still reaps child"; else bad "wrapper-session SIGKILL left child $PGRP_PID"; fi
fi

# --- 10. a stale marker dir (dead reaper) does not permanently disable sweeps ---
# tentura-2tj: a SIGKILLed wrapper+reaper used to leak its marker dir forever,
# and other_active_markers() counted any marker dir as "active" without
# checking whether its reaper is actually still alive -- so one leaked
# marker permanently disabled every future sweep.
# The previous case's reaper can still be sweeping after its child exits.
# Give this case its own marker directory and sweep scope.
STALE_TMP="$TMPDIR/stale-marker"
DEAD_MARKER="$STALE_TMP/tentura-test-cleanup/selftest_stale_$$"
mkdir -p "$DEAD_MARKER"
sh -c 'exit 0' & DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null || true
echo "$DEAD_PID" >"$DEAD_MARKER/reaper.pid"

STALE_OUT="$(TMPDIR="$STALE_TMP" "$WRAP" --timeout 10s -- true 2>&1)"
if [[ "$STALE_OUT" == *"skipping orphan/tmpfs sweep"* ]]; then
  bad "stale marker dir with a dead reaper still blocked the sweep"
else
  ok "stale marker dir with a dead reaper does not block the sweep"
fi
if [[ -d "$DEAD_MARKER" ]]; then
  bad "stale marker dir was not reclaimed"
  rm -rf "$DEAD_MARKER"
else
  ok "stale marker dir was reclaimed"
fi

# --- 11. marker dir vanishing mid-run does not lose a passing exit code ---
# tentura-fy2: `: >"$marker/done"` had no `|| true` under set -e, so if the
# marker directory disappeared out from under an in-flight run (a race a
# concurrent sweep can trigger), the wrapper crashed on that write and
# reported the wrong exit code instead of the wrapped command's real one.
STATE_ROOT="${TMPDIR:-/tmp}/tentura-test-cleanup"
BEFORE_MARKERS="$(ls -1 "$STATE_ROOT" 2>/dev/null || true)"
"$WRAP" --timeout 10s -- sh -c 'sleep 1; exit 7' >/tmp/selftest_fy2_out_$$ 2>&1 &
RACE_WPID=$!
NEW_MARKER=""
for _ in $(seq 1 30); do
  NEW_MARKER="$(comm -13 <(printf '%s\n' "$BEFORE_MARKERS" | sort) <(ls -1 "$STATE_ROOT" 2>/dev/null | sort) | head -1)"
  [[ -n "$NEW_MARKER" ]] && break
  sleep 0.05
done
if [[ -n "$NEW_MARKER" ]]; then
  rm -rf "${STATE_ROOT:?}/$NEW_MARKER"
fi
RACE_RC=0
wait "$RACE_WPID" || RACE_RC=$?
rm -f /tmp/selftest_fy2_out_$$
if [[ -z "$NEW_MARKER" ]]; then
  bad "marker-vanishes-mid-run: could not find the run's marker dir to delete"
elif [[ "$RACE_RC" -eq 7 ]]; then
  ok "marker vanishing mid-run still reports the wrapped command's real exit code"
else
  bad "marker vanishing mid-run reported exit $RACE_RC, expected 7"
fi

# --- 12. leaked nested-harness TMPDIRs are reclaimed; live/fresh/foreign kept ---
# Harnesses hand a nested wrapped run a private `tentura-*` TMPDIR and drop it
# in `finally`; a SIGKILLed outer test leaks it with a multi-GB kernel cache.
NT="${TMPDIR:?}"
mkdir -p "$NT/tentura-st-leaked-A/tentura-test-cleanup" \
  "$NT/tentura-st-live-B/dart_test.kernel.X" \
  "$NT/tentura-st-fresh-C/dart_test.kernel.Y" \
  "$NT/tentura-st-foreign-D"
touch -d '-1 hour' "$NT/tentura-st-leaked-A" "$NT/tentura-st-live-B" "$NT/tentura-st-foreign-D"
env TMPDIR="$NT/tentura-st-live-B" python3 -c 'import time; time.sleep(30)' &
cleanup_pids+=("$!")
sleep 0.2
"$WRAP" --sweep-only >/dev/null 2>&1
if [[ ! -d "$NT/tentura-st-leaked-A" ]]; then ok "leaked nested TMPDIR removed"; else bad "leaked nested TMPDIR survived"; fi
if [[ -d "$NT/tentura-st-live-B" ]]; then ok "nested TMPDIR of a live process kept"; else bad "live nested TMPDIR deleted"; fi
if [[ -d "$NT/tentura-st-fresh-C" ]]; then ok "fresh nested TMPDIR kept"; else bad "fresh nested TMPDIR deleted"; fi
if [[ -d "$NT/tentura-st-foreign-D" ]]; then ok "tentura-* dir without nested signature kept"; else bad "foreign tentura-* dir deleted"; fi

# --- 13. unset TMPDIR uses a RAM tmpfs, never disk; explicit values survive ---
# These two cases exercise local tmpfs selection. CI deliberately uses /tmp.
RUNTIME_DIR="$NT/runtime"
mkdir -p "$RUNTIME_DIR"
if [[ "$(stat -f -c %T "$RUNTIME_DIR")" == "tmpfs" ]]; then
  if env -u CI -u TMPDIR XDG_RUNTIME_DIR="$RUNTIME_DIR" TENTURA_TEST_TMP_MIN_MB=1 \
    "$WRAP" --timeout 10s -- bash -c \
    '[[ "$TMPDIR" == "$1" && -d "$TMPDIR" ]]' bash "$RUNTIME_DIR/tentura-test-tmp"; then
    ok "unset TMPDIR uses and creates the runtime tmpfs dir"
  else
    bad "unset TMPDIR did not use \$XDG_RUNTIME_DIR/tentura-test-tmp"
  fi
else
  ok "unset TMPDIR runtime-tmpfs case skipped (selftest dir is not tmpfs)"
fi
DISK_HOME="$NT/disk-home"
rc=0
env -u CI -u TMPDIR HOME="$DISK_HOME" XDG_RUNTIME_DIR="$RUNTIME_DIR" TENTURA_TEST_TMP_MIN_MB=999999999 \
  "$WRAP" --timeout 10s -- true >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 75 && ! -e "$DISK_HOME/.cache/tentura-test-tmp" ]]; then
  ok "no tmpfs with room: refuses (75) instead of using disk"
else
  bad "no tmpfs with room: rc=$rc, disk dir $(ls -d "$DISK_HOME/.cache/tentura-test-tmp" 2>/dev/null || echo absent)"
fi
EXPLICIT_TMP="$NT/explicit tmp"
mkdir -p "$EXPLICIT_TMP"
if TMPDIR="$EXPLICIT_TMP" "$WRAP" --timeout 10s -- bash -c \
  '[[ "$TMPDIR" == "$1" ]]' bash "$EXPLICIT_TMP"; then
  ok "explicit TMPDIR preserved"
else
  bad "explicit TMPDIR changed"
fi

# Create fixtures inside the child so their names are absent from live
# command lines when the exit sweep checks whether they are referenced.
SYSTEM_TMP="${TENTURA_TEST_CLEANUP_SYSTEM_TMP:-/tmp}"
if TMPDIR="$EXPLICIT_TMP" "$WRAP" --timeout 10s -- python3 - <<'PY'
import os, pathlib
for root in (pathlib.Path(os.environ.get('TENTURA_TEST_CLEANUP_SYSTEM_TMP') or '/tmp'),
             pathlib.Path(os.environ['TMPDIR'])):
    for pattern in ('flutter_tools.', 'dart_test.kernel.'):
        (root / (pattern + 'lt6i-' + str(os.getppid()))).mkdir()
PY
then
  if compgen -G "$SYSTEM_TMP/flutter_tools.lt6i-*" >/dev/null || \
    compgen -G "$SYSTEM_TMP/dart_test.kernel.lt6i-*" >/dev/null || \
    compgen -G "$EXPLICIT_TMP/flutter_tools.*" >/dev/null || \
    compgen -G "$EXPLICIT_TMP/dart_test.kernel.*" >/dev/null; then
    bad "exit sweep left temporary fixtures behind"
  else
    ok "exit sweep cleans both /tmp and explicit TMPDIR"
  fi
else
  bad "dual-directory cleanup fixture command failed"
fi


# --- 15. machine-wide queue: a second run waits; nested runs do not deadlock ---
QLOCK="$NT/queue.lock"
QLOG="$NT/queue.log"
: >"$QLOG"
TENTURA_TEST_LOCK="$QLOCK" "$WRAP" --timeout 30s -- bash -c \
  "echo A-start \$(date +%s%N) >>'$QLOG'; sleep 2; \
   '$WRAP' --timeout 10s -- bash -c 'echo nested >>\"$QLOG\"'; \
   echo A-end \$(date +%s%N) >>'$QLOG'" >/dev/null 2>&1 &
QA=$!
sleep 0.5
TENTURA_TEST_LOCK="$QLOCK" "$WRAP" --timeout 30s -- bash -c \
  "echo B-start \$(date +%s%N) >>'$QLOG'" >/dev/null 2>&1 || true
wait "$QA" || true
a_end="$(awk '$1=="A-end"{print $2}' "$QLOG")"
b_start="$(awk '$1=="B-start"{print $2}' "$QLOG")"
if grep -q '^nested$' "$QLOG"; then ok "queue: nested wrapped run inside a held lock does not deadlock"; else bad "queue: nested run never ran"; fi
if [[ -n "$a_end" && -n "$b_start" ]] && (( b_start >= a_end )); then
  ok "queue: second run starts only after the first ends"
else
  bad "queue: runs overlapped (A-end=$a_end B-start=$b_start)"
fi
if TENTURA_TEST_LOCK="$QLOCK" "$WRAP" --no-lock --timeout 10s -- true >/dev/null 2>&1; then
  ok "queue: --no-lock runs"
else
  bad "queue: --no-lock run failed"
fi

# A process that escapes the run's tag (here: clears TENTURA_TEST_CLEANUP_RUN,
# like a long-lived analyzer daemon outside the cleanup) must not keep the
# queue's lock fd: the wrapped command does not inherit it (tentura-dckd).
QDAEMON="$NT/queue-daemon.pid"
TENTURA_TEST_LOCK="$QLOCK" "$WRAP" --timeout 10s -- bash -c \
  "env -u TENTURA_TEST_CLEANUP_RUN setsid sleep 60 >/dev/null 2>&1 </dev/null & echo \$! >'$QDAEMON'" \
  >/dev/null 2>&1 || true
lock_free=0
for _ in $(seq 1 50); do
  if flock -n "$QLOCK" true; then lock_free=1; break; fi
  sleep 0.2
done
if (( lock_free )); then
  ok "queue: an escaped background process does not hold the lock after the run"
else
  bad "queue: lock still held after the run by an escaped background process"
fi
[[ -s "$QDAEMON" ]] && kill "$(cat "$QDAEMON")" 2>/dev/null || true

log "done"
