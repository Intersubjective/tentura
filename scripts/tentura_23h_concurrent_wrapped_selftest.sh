#!/usr/bin/env bash
# tentura-23h bead acceptance: concurrent wrapped suites must not cross-kill or
# cross-sweep each other's dart test leftovers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"
chmod +x "$WRAP"

pass=0
fail=0
cleanup_pids=()

log() { printf '[tentura-23h-selftest] %s\n' "$*"; }
ok() { pass=$((pass + 1)); log "PASS: $1"; }
bad() { fail=$((fail + 1)); log "FAIL: $1"; }

still_alive() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

wait_dead() {
  local pid="$1" n=0
  while (( n < 50 )); do
    still_alive "$pid" || return 0
    sleep 0.1
    n=$((n + 1))
  done
  return 1
}

# Match the stand-in python -c process, never this helper (which is also
# `python3 - <marker>` and would otherwise self-match).
pid_by_marker() {
  local marker="$1"
  python3 - "$marker" <<'PY' || true
import os, pathlib, sys
mark = sys.argv[1].encode()
self_pid = os.getpid()
for p in pathlib.Path("/proc").iterdir():
    if not p.name.isdigit():
        continue
    pid = int(p.name)
    if pid == self_pid:
        continue
    try:
        cmd = (p / "cmdline").read_bytes()
        comm = (p / "comm").read_text().strip()
    except (FileNotFoundError, PermissionError):
        continue
    if (
        mark in cmd
        and comm.startswith("python")
        and b"-c\x00" in cmd
    ):
        print(p.name)
        break
sys.exit(0)
PY
}

# Wait until the victim wrap has published its cleanup marker dir so a peer
# pre-sweep cannot race ahead of other_active_markers.
wait_for_wrap_marker() {
  local wp="$1" n=0
  while (( n < 100 )); do
    if ! still_alive "$wp"; then
      return 1
    fi
    # Marker dirs are UUID hex under STATE_ROOT; presence of any active wrap
    # besides a finishing peer is enough once the victim WP is alive and has
    # been given a tick to mkdir.
    if [[ -d "${TMPDIR:-/tmp}/tentura-test-cleanup" ]] && \
       compgen -G "${TMPDIR:-/tmp}/tentura-test-cleanup/*/" >/dev/null; then
      # Confirm victim still running after a short settle.
      sleep 0.2
      still_alive "$wp" || return 1
      return 0
    fi
    sleep 0.05
    n=$((n + 1))
  done
  return 1
}

finish() {
  local p
  for p in "${cleanup_pids[@]+"${cleanup_pids[@]}"}"; do
    kill -KILL "$p" 2>/dev/null || true
  done
  log "passed=$pass failed=$fail"
  [[ "$fail" -eq 0 ]]
}
trap finish EXIT

# --- 1. Another wrapped suite finishing must not kill this run's frontend_server stand-in ---
VICTIM_FS_MARK="tentura_23h_victim_frontend_server_$$"
"$WRAP" --timeout 45s -- bash -c '
  setsid -f python3 -c "import time; time.sleep(40)  # frontend_server '"$VICTIM_FS_MARK"'" </dev/null &
  python3 -c "import time; time.sleep(35)  # tentura_23h_victim_hold"
' &
VICTIM_WP=$!
cleanup_pids+=("$VICTIM_WP")

for _ in $(seq 1 60); do
  VICTIM_FS_PID="$(pid_by_marker "$VICTIM_FS_MARK" || true)"
  [[ -n "$VICTIM_FS_PID" ]] && break
  sleep 0.1
done

if [[ -z "${VICTIM_FS_PID:-}" ]]; then
  bad "victim frontend_server stand-in never appeared"
else
  if ! wait_for_wrap_marker "$VICTIM_WP"; then
    bad "victim wrap marker never appeared before peer"
  else
    "$WRAP" --timeout 10s -- true
    sleep 0.5
    if still_alive "$VICTIM_FS_PID"; then
      ok "concurrent wrapped exit preserved victim frontend_server stand-in"
    else
      bad "concurrent wrapped exit killed victim frontend_server stand-in (orphan sweeper)"
    fi
  fi
fi

wait "$VICTIM_WP" 2>/dev/null || true
VICTIM_WP=""
cleanup_pids=()

# --- 2. Another wrapped suite sweep must not delete this run's dart_test.kernel dir ---
VICTIM_KERNEL="${TMPDIR:-/tmp}/dart_test.kernel.tentura23hvictim$$"
mkdir -p "$VICTIM_KERNEL/tentura_23h_marker"
"$WRAP" --timeout 45s -- bash -c '
  python3 -c "import time; time.sleep(35)  # tentura_23h_kernel_victim_hold"
' &
KERNEL_VICTIM_WP=$!
cleanup_pids+=("$KERNEL_VICTIM_WP")

if ! wait_for_wrap_marker "$KERNEL_VICTIM_WP"; then
  bad "kernel victim wrap marker never appeared before peer"
else
  "$WRAP" --timeout 10s -- true
  sleep 0.3

  if [[ -d "$VICTIM_KERNEL" ]]; then
    ok "concurrent wrapped exit preserved victim dart_test.kernel dir"
  else
    bad "concurrent wrapped exit removed victim dart_test.kernel dir (global tmpfs sweep)"
  fi
fi

wait "$KERNEL_VICTIM_WP" 2>/dev/null || true
KERNEL_VICTIM_WP=""
cleanup_pids=()

rm -rf "$VICTIM_KERNEL"

log "done"
