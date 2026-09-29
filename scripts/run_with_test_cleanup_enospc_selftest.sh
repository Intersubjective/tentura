#!/usr/bin/env bash
# tentura-ah4: scripts/run_with_test_cleanup.sh must survive a full/unwritable
# TMPDIR. Its marker/state bookkeeping is best-effort; losing it must never
# lose the wrapped command or its real exit code, and must not spray raw
# bash redirect errors over the output of a run that actually passed.
#
# Real-world trigger: /tmp tmpfs at 100% inodes (17G free by `df -h`) after
# ~995k files under /tmp/pytest-of-vader. The wrapped tests printed
# "All tests passed!" and then the wrapper printed
# "done: No space left on device" and exited 1.
#
# ENOSPC cannot be induced without root, so the failing open()/mkdir() calls
# are induced by other means that also work as root: a regular file where a
# directory is needed (ENOTDIR/EEXIST), an over-long path (ENAMETOOLONG) and a
# directory where the `done` file is needed (EISDIR). No case depends on
# permission bits, and none is skipped.
#
# Does not start Flutter/Dart. Run: bash scripts/run_with_test_cleanup_enospc_selftest.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"

# Hermetic like run_with_test_cleanup_selftest.sh: drop an outer run's tag and
# use a private TMPDIR so peer-run detection cannot skew the assertions.
if [[ -z "${ENOSPC_SELFTEST_ISOLATED:-}" ]]; then
  export ENOSPC_SELFTEST_ISOLATED=1
  exec env -u TENTURA_TEST_CLEANUP_RUN \
    TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tentura-enospc-selftest.XXXXXX")" \
    bash "$ROOT/scripts/run_with_test_cleanup_enospc_selftest.sh" "$@"
fi

# Scratch space for captured output. Fixed before any scenario TMPDIR is
# handed to the wrapper so a scenario's unusable TMPDIR never breaks the
# harness's own redirects.
OUTDIR="$TMPDIR"

pass=0
fail=0

log() { printf '[enospc-selftest] %s\n' "$*"; }
ok() { pass=$((pass + 1)); log "PASS: $1"; }
bad() { fail=$((fail + 1)); log "FAIL: $1"; }

finish() {
  if [[ "${TMPDIR:-}" == */tentura-enospc-selftest.* ]]; then
    chmod -R u+rwX "$TMPDIR" 2>/dev/null || true
    rm -rf "$TMPDIR"
  fi
  echo
  log "passed=$pass failed=$fail"
  [[ "$fail" -eq 0 ]]
}
trap finish EXIT

# The wrapper re-execs itself as the reaper, so it must already be executable;
# do not paper over a missing bit here.
if [[ -x "$WRAP" ]]; then
  ok "wrapper is executable"
else
  bad "wrapper $WRAP is not executable"
fi

# Runs the wrapper with TMPDIR=$2 under scenario name $1; remaining args are
# the wrapped command. Sets WRAP_RC and WRAP_ERR (wrapper stderr text).
run_case() {
  local name="$1" tmp="$2"
  shift 2
  set +e
  TMPDIR="$tmp" "$WRAP" --timeout 20s -- "$@" \
    >"$OUTDIR/out.$name" 2>"$OUTDIR/err.$name"
  WRAP_RC=$?
  set -e
  WRAP_ERR="$(cat "$OUTDIR/err.$name")"
}

# Raw bash failures look like "<script>: line N: <path>: <errno text>".
has_bash_error_noise() {
  grep -Eq 'run_with_test_cleanup\.sh: line [0-9]+:' <<<"$1"
}

# Checks the three properties for one induced failure. $1 = label, $2 = tmp
# dir handed to the wrapper, $3 = setup to run before each call (may be empty).
# The command records that it ran, so a wrapper that gave up early is caught.
expect_survives() {
  local label="$1" tmp="$2" ran="$OUTDIR/ran.$1"

  rm -f "$ran"
  run_case "$label.fail" "$tmp" sh -c "echo ran >'$ran'; exit 7"
  if [[ -f "$ran" ]]; then ok "$label: wrapped command still ran"; else bad "$label: wrapper gave up before running the command (rc=$WRAP_RC)"; fi
  if [[ "$WRAP_RC" -eq 7 ]]; then ok "$label: failing command's exit code (7) preserved"; else bad "$label: exit $WRAP_RC, expected the command's 7"; fi
  if has_bash_error_noise "$WRAP_ERR"; then bad "$label: raw bash error noise on stderr (failing command):
$WRAP_ERR"; else ok "$label: no raw bash error noise (failing command)"; fi

  rm -f "$ran"
  run_case "$label.pass" "$tmp" sh -c "echo ran >'$ran'; exit 0"
  if [[ -f "$ran" ]]; then ok "$label: passing command still ran"; else bad "$label: passing command never ran (rc=$WRAP_RC)"; fi
  if [[ "$WRAP_RC" -eq 0 ]]; then ok "$label: passing command exits 0"; else bad "$label: passing command exited $WRAP_RC (misleading wrapper failure)"; fi
  if has_bash_error_noise "$WRAP_ERR"; then bad "$label: raw bash error noise on stderr (passing command):
$WRAP_ERR"; else ok "$label: no raw bash error noise (passing command)"; fi
}

# --- 1. state root cannot be created (a file sits where the directory goes) ---
SC1="$(mktemp -d "$TMPDIR/sc1.XXXXXX")"
: >"$SC1/tentura-test-cleanup"
expect_survives state_root_blocked "$SC1"

# --- 2. TMPDIR itself unusable: its parent is a regular file ---
SC2="$(mktemp -d "$TMPDIR/sc2.XXXXXX")"
: >"$SC2/notadir"
expect_survives tmpdir_unusable "$SC2/notadir/tmp"

# --- 3. state root exists but the run's marker dir cannot be created ---
# The actual inode-exhaustion shape: `mkdir -p "$STATE_ROOT"` succeeds because
# the directory is already there, then `mkdir "$STATE_ROOT/<run id>"` fails.
# Induced without permission bits (so it also holds as root): TMPDIR is a
# ~4050-char path, so STATE_ROOT still fits in PATH_MAX but the marker below
# it does not (ENAMETOOLONG).
SC3="$(mktemp -d "$TMPDIR/sc3.XXXXXX")"
LONG_TMP="$(python3 - "$SC3" <<'PY'
import os, sys
os.chdir(sys.argv[1])
target = 4050
while len(os.getcwd()) + 201 < target:
    os.mkdir("d" * 200)
    os.chdir("d" * 200)
last = target - len(os.getcwd()) - 1
os.mkdir("e" * last)
os.chdir("e" * last)
os.mkdir("tentura-test-cleanup")
print(os.getcwd())
PY
)"
probe_marker="$LONG_TMP/tentura-test-cleanup/$(printf 'x%.0s' $(seq 1 32))"
if [[ -d "$LONG_TMP/tentura-test-cleanup" ]] && ! mkdir "$probe_marker" 2>/dev/null; then
  ok "marker_mkdir_fails: marker dir creation is impossible (setup proof)"
  expect_survives marker_mkdir_fails "$LONG_TMP"
else
  bad "marker_mkdir_fails: could not induce a marker mkdir failure (len=${#LONG_TMP})"
fi

# --- 4. marker turns unusable mid-run: writing `done` at exit fails ---
# Tests passed, then the wrapper failed on the done-marker write. The command
# makes `done` a directory (EISDIR on open) and proves it did so; without the
# proof file the noise/exit assertions could pass vacuously.
for want in 0 5; do
  SC4="$(mktemp -d "$TMPDIR/sc4.XXXXXX")"
  proof="$SC4/proof"
  run_case "done_unwritable.$want" "$SC4" sh -c "
    m=\"\$TMPDIR/tentura-test-cleanup/\$TENTURA_TEST_CLEANUP_RUN\"
    mkdir \"\$m/done\" && [ -d \"\$m/done\" ] && echo engaged >'$proof'
    exit $want"
  if [[ -f "$proof" ]]; then
    ok "done_unwritable exit $want: done-marker failure was actually induced"
  else
    bad "done_unwritable exit $want: could not induce a done-marker failure (marker dir missing?)"
  fi
  if [[ "$WRAP_RC" -eq "$want" ]]; then
    ok "done_unwritable exit $want: wrapper exits with the command's $want"
  else
    bad "done_unwritable exit $want: wrapper exited $WRAP_RC"
  fi
  if has_bash_error_noise "$WRAP_ERR"; then
    bad "done_unwritable exit $want: raw bash error noise on stderr:
$WRAP_ERR"
  else
    ok "done_unwritable exit $want: no raw bash error noise on stderr"
  fi
done

log "done"
