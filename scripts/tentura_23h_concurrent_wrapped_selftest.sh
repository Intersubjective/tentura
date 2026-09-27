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
  VICTIM_FS_PID="$(pid_by_marker "$VICTIM_FS_MARK")"
  [[ -n "$VICTIM_FS_PID" ]] && break
  sleep 0.1
done

if [[ -z "${VICTIM_FS_PID:-}" ]]; then
  bad "victim frontend_server stand-in never appeared"
else
  sleep 0.3
  "$WRAP" --timeout 10s -- true
  sleep 0.5
  if still_alive "$VICTIM_FS_PID"; then
    ok "concurrent wrapped exit preserved victim frontend_server stand-in"
  else
    bad "concurrent wrapped exit killed victim frontend_server stand-in (orphan sweeper)"
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
sleep 0.5

"$WRAP" --timeout 10s -- true
sleep 0.3

if [[ -d "$VICTIM_KERNEL" ]]; then
  ok "concurrent wrapped exit preserved victim dart_test.kernel dir"
else
  bad "concurrent wrapped exit removed victim dart_test.kernel dir (global tmpfs sweep)"
fi

wait "$KERNEL_VICTIM_WP" 2>/dev/null || true
KERNEL_VICTIM_WP=""
cleanup_pids=()

rm -rf "$VICTIM_KERNEL"

log "done"
