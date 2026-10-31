#!/usr/bin/env bash
# Self-test for scripts/test_job.sh: detached runs, bounded waits, kill,
# abandonment and a supervisor that died. Starts no Flutter/Dart; short
# shell stand-ins only, in a private jobs directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOB="$ROOT/scripts/test_job.sh"
export TENTURA_TEST_JOBS_DIR
TENTURA_TEST_JOBS_DIR="$(mktemp -d)"
trap 'pkill -f "$TENTURA_TEST_JOBS_DIR" 2>/dev/null || true; rm -rf "$TENTURA_TEST_JOBS_DIR"' EXIT

passed=0
failed=0
check() {
  local name="$1"
  shift
  if "$@"; then
    passed=$((passed + 1))
    echo "ok   $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name"
  fi
}

# Runs `test_job.sh "$@"`, leaving its exit code in $rc and output in $out.
run() {
  rc=0
  out="$("$JOB" "$@" 2>&1)" || rc=$?
}

# 1. The run's own exit code and output come back through wait.
id="$("$JOB" start -- bash -c 'echo hello-from-job; exit 7' 2>/dev/null)"
run wait "$id" --max 30s
check "wait returns the run's exit code" test "$rc" -eq 7
check "wait prints the run's output" grep -q hello-from-job <<<"$out"

# 2. A bounded wait on a long run returns 3 and says to call again; wait with
#    no id takes the newest job.
id="$("$JOB" start -- sleep 60 2>/dev/null)"
started=$(date +%s)
run wait --max 2s
check "a bounded wait returns 3 while the run is going" test "$rc" -eq 3
check "a bounded wait returns within its --max" test $(( $(date +%s) - started )) -lt 10
check "a bounded wait names the next call" grep -q "test_job.sh wait $id" <<<"$out"

# 3. kill stops the run and still publishes an exit code.
"$JOB" kill "$id" 2>/dev/null
run wait "$id" --max 30s
check "a killed run ends with a non-zero exit code" test "$rc" -ne 0 -a "$rc" -ne 3 -a "$rc" -ne 70
check "a killed run says so in its log" grep -q "stopped by test_job.sh kill" "$TENTURA_TEST_JOBS_DIR/$id/log"

# 4. A run nobody waits on is killed as abandoned.
id="$(TENTURA_TEST_JOB_ABANDON=3s "$JOB" start -- sleep 60 2>/dev/null)"
n=0
while [[ ! -f "$TENTURA_TEST_JOBS_DIR/$id/rc" ]] && (( n < 40 )); do sleep 0.5; n=$((n + 1)); done
check "an unpolled run is killed as abandoned" grep -q "killing it as abandoned" "$TENTURA_TEST_JOBS_DIR/$id/log"

# 5. A supervisor killed from outside is reported as died (70), not as running.
id="$("$JOB" start -- sleep 60 2>/dev/null)"
n=0
while [[ ! -f "$TENTURA_TEST_JOBS_DIR/$id/pid" ]] && (( n < 50 )); do sleep 0.1; n=$((n + 1)); done
kill -KILL "$(cat "$TENTURA_TEST_JOBS_DIR/$id/pid")"
run wait "$id" --max 10s
check "a dead supervisor is reported as died" test "$rc" -eq 70

# 6. status lists every job with its state.
run status
check "status lists every job" test "$(wc -l <<<"$out")" -eq 4

echo "passed=$passed failed=$failed"
[[ "$failed" -eq 0 ]]
