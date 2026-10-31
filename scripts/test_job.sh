#!/usr/bin/env bash
#
# Detached test runs, polled in bounded waits.
#
# A suite can run longer than an agent's prompt cache lives (about 30 min).
# An agent blocked inside one long command comes back to a cold cache and
# pays to re-read its whole context; an agent that polls in waits shorter
# than the cache lifetime refreshes the cache on every poll. So start the run
# detached, then call `wait` until it reports the result.
#
# Usage:
#   scripts/test_job.sh start -- scripts/run_tests.sh client-all   # prints the job id
#   scripts/test_job.sh wait [<id>] [--max 20m]   # the run's exit code once it ends;
#                                                 # exit 3 while it still runs
#   scripts/test_job.sh status                    # one line per job
#   scripts/test_job.sh log [<id>] [lines]
#   scripts/test_job.sh kill [<id>]
#
# <id> defaults to the newest job. `start` runs the command from the current
# directory in its own session, output to the job's log. The command still
# goes through scripts/run_with_test_cleanup.sh (directly or via
# scripts/run_tests.sh); this script only detaches it. A job nobody has
# waited on for TENTURA_TEST_JOB_ABANDON (default 45m) is killed as
# abandoned: whoever started it is gone. `wait --max` defaults to
# TENTURA_TEST_JOB_WAIT (20m). Jobs live under
# ${XDG_STATE_HOME:-~/.local/state}/tentura-test-jobs; finished ones are
# dropped after two days.

set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
JOBS="${TENTURA_TEST_JOBS_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tentura-test-jobs}"
STILL_RUNNING=3
DIED=70

log() { printf '[test-job] %s\n' "$*" >&2; }

usage() {
  sed -n '2,27p' "$SELF" | sed 's/^# \?//'
  exit 2
}

seconds() {
  local raw="$1"
  case "$raw" in
    *h) echo $(( ${raw%h} * 3600 )) ;;
    *m) echo $(( ${raw%m} * 60 )) ;;
    *s) echo "${raw%s}" ;;
    *) echo "$raw" ;;
  esac
}

job_dir() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id="$(ls -1t "$JOBS" 2>/dev/null | head -1)"
    [[ -n "$id" ]] || { log "no jobs"; exit 2; }
  fi
  [[ -d "$JOBS/$id" ]] || { log "no job $id"; exit 2; }
  echo "$JOBS/$id"
}

alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }

mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }

elapsed_min() { echo $(( ($(date +%s) - $(cat "$1/started")) / 60 )); }

# The detached supervisor: runs the command, kills it when abandoned, and
# publishes its exit code atomically.
run_job() {
  local dir="$1"
  shift
  echo "$$" >"$dir/pid"
  local abandon
  abandon="$(seconds "${TENTURA_TEST_JOB_ABANDON:-45m}")"
  "$@" >"$dir/log" 2>&1 </dev/null &
  local child=$!
  while alive "$child"; do
    if [[ -f "$dir/stop" ]] || (( $(date +%s) - $(mtime "$dir/polled") > abandon )); then
      if [[ -f "$dir/stop" ]]; then
        printf '[test-job] stopped by test_job.sh kill\n' >>"$dir/log"
      else
        printf '[test-job] nobody waited on this job for %ss; killing it as abandoned\n' "$abandon" >>"$dir/log"
      fi
      # The cleanup wrapper defers its TERM trap until its command exits, so
      # KILL follows soon; the wrapper's reaper then tears the run down.
      kill -TERM "$child" 2>/dev/null || true
      local n=0
      while alive "$child" && (( n < 5 )); do sleep 1; n=$((n + 1)); done
      kill -KILL "$child" 2>/dev/null || true
      break
    fi
    sleep 2
  done
  local rc=0
  wait "$child" || rc=$?
  echo "$rc" >"$dir/rc.tmp" && mv "$dir/rc.tmp" "$dir/rc"
}

start() {
  [[ "${1:-}" == "--" ]] && shift
  [[ $# -gt 0 ]] || usage
  mkdir -p "$JOBS"
  find "$JOBS" -mindepth 1 -maxdepth 1 -type d -mtime +2 -exec test -f '{}/rc' ';' -exec rm -rf '{}' + 2>/dev/null || true
  local id dir
  id="$(date +%m%d-%H%M%S)-$$"
  dir="$JOBS/$id"
  mkdir -p "$dir"
  pwd >"$dir/cwd"
  printf '%q ' "$@" >"$dir/cmd"
  date +%s >"$dir/started"
  touch "$dir/polled"
  setsid -f "$SELF" --run "$dir" "$@" </dev/null >/dev/null 2>&1
  echo "$id"
  log "started $id: $(cat "$dir/cmd")"
  log "next: scripts/test_job.sh wait $id"
}

wait_job() {
  local id="" max="${TENTURA_TEST_JOB_WAIT:-20m}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max) max="$2"; shift 2 ;;
      *) id="$1"; shift ;;
    esac
  done
  local dir
  dir="$(job_dir "$id")"
  id="$(basename "$dir")"
  local deadline=$(( $(date +%s) + $(seconds "$max") ))
  touch "$dir/polled"
  # The supervisor publishes its pid right after setsid; give it a moment.
  local n=0
  while [[ ! -f "$dir/pid" && ! -f "$dir/rc" ]] && (( n < 50 )); do sleep 0.1; n=$((n + 1)); done
  while [[ ! -f "$dir/rc" ]]; do
    if ! alive "$(cat "$dir/pid" 2>/dev/null)"; then
      [[ -f "$dir/rc" ]] && break
      tail -n 40 "$dir/log" 2>/dev/null || true
      log "$id died without an exit code after $(elapsed_min "$dir") min (log: $dir/log)"
      exit "$DIED"
    fi
    if (( $(date +%s) >= deadline )); then
      touch "$dir/polled"
      tail -n 5 "$dir/log" 2>/dev/null || true
      log "$id still running after $(elapsed_min "$dir") min; call again: scripts/test_job.sh wait $id"
      exit "$STILL_RUNNING"
    fi
    sleep 5
  done
  local rc
  rc="$(cat "$dir/rc")"
  tail -n 60 "$dir/log" 2>/dev/null || true
  log "$id finished rc=$rc after $(elapsed_min "$dir") min (full log: $dir/log)"
  exit "$rc"
}

status() {
  local dir state
  for dir in $(ls -1dt "$JOBS"/*/ 2>/dev/null); do
    dir="${dir%/}"
    if [[ -f "$dir/rc" ]]; then
      state="rc=$(cat "$dir/rc")"
    elif alive "$(cat "$dir/pid" 2>/dev/null)"; then
      state="RUNNING"
    else
      state="DIED"
    fi
    printf '%s %s %smin %s: %s\n' "$(basename "$dir")" "$state" "$(elapsed_min "$dir")" \
      "$(cat "$dir/cwd")" "$(cat "$dir/cmd")"
  done
}

main() {
  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$cmd" in
    --run) local dir="$1"; shift; run_job "$dir" "$@" ;;
    start) start "$@" ;;
    wait) wait_job "$@" ;;
    status) status ;;
    log) local dir; dir="$(job_dir "${1:-}")"; tail -n "${2:-100}" "$dir/log" ;;
    kill)
      local dir pid; dir="$(job_dir "${1:-}")"
      pid="$(cat "$dir/pid" 2>/dev/null || true)"
      # The supervisor stops the command itself and still publishes an exit code.
      touch "$dir/stop"
      alive "$pid" && log "stopping $(basename "$dir")" || log "$(basename "$dir") is not running"
      ;;
    *) usage ;;
  esac
}

main "$@"
