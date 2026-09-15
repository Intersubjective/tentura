#!/usr/bin/env bash
# Induced-crash checks for scripts/run_with_test_cleanup.sh.
# Does not start Flutter/Dart — only hang/orphan/tmpfs stand-ins.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"
chmod +x "$WRAP"

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
        cmd = (p / "cmdline").read_bytes()
        comm = (p / "comm").read_text().strip()
    except (FileNotFoundError, PermissionError):
        continue
    if mark in cmd and comm.startswith("python"):
        print(p.name)
        break
PY
}

finish() {
  local p
  for p in "${cleanup_pids[@]+"${cleanup_pids[@]}"}"; do
    kill -KILL "$p" 2>/dev/null || true
  done
  echo
  log "passed=$pass failed=$fail"
  [[ "$fail" -eq 0 ]]
}
trap finish EXIT

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
TERM_MARK="selftest_sigterm_child_$$"
"$WRAP" --timeout 60s -- python3 -c "import time; time.sleep(90)  # $TERM_MARK" &
WPID=$!
cleanup_pids+=("$WPID")
for _ in $(seq 1 30); do
  TERM_PID="$(pid_by_marker "$TERM_MARK")"
  [[ -n "$TERM_PID" ]] && break
  sleep 0.1
done
if [[ -z "${TERM_PID:-}" ]]; then
  bad "SIGTERM case: child never appeared"
else
  kill -TERM "$WPID" 2>/dev/null || true
  wait "$WPID" 2>/dev/null || true
  if wait_dead "$TERM_PID"; then ok "SIGTERM wrapper kills tagged child"; else bad "SIGTERM wrapper left child $TERM_PID"; fi
fi

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
setsid -f "$WRAP" --timeout 60s -- python3 -c "import time; time.sleep(90)  # $PGRP_MARK" </dev/null
sleep 0.3
PGRP_PID="$(pid_by_marker "$PGRP_MARK")"
WPID=""
for _ in $(seq 1 40); do
  WPID="$(pgrep -f "run_with_test_cleanup.sh --timeout 60s" | awk 'NR==1')"
  [[ -n "$WPID" ]] && break
  sleep 0.1
done
if [[ -z "${PGRP_PID:-}" || -z "$WPID" ]]; then
  bad "PGID SIGKILL case: wrapper='$WPID' child='$PGRP_PID'"
else
  cleanup_pids+=("$WPID")
  WPGID="$(ps -o pgid= -p "$WPID" | tr -d ' ')"
  kill -KILL -- "-$WPGID" 2>/dev/null || kill -KILL "$WPID" 2>/dev/null || true
  for _ in $(seq 1 25); do
    still_alive "$PGRP_PID" || break
    sleep 0.2
  done
  if wait_dead "$PGRP_PID"; then ok "wrapper-session SIGKILL: reaper still reaps child"; else bad "wrapper-session SIGKILL left child $PGRP_PID"; fi
fi

log "done"
