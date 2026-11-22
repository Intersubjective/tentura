#!/usr/bin/env bash
# Run a web compiler with scratch space that test cleanup can identify as live
# even when it cannot see the compiler's PID.
set -euo pipefail

scratch_parent="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
staging="$(mktemp -d -- "$scratch_parent/.flutter_tools.tentura-web.XXXXXXXXXXXX")"
trap 'rmdir -- "$staging"' EXIT
scratch="$scratch_parent/${staging##*/.}"

# Lock the directory inode before publishing it under the sweep's glob. The
# exec'd command inherits the descriptor, so the lock is released on exit,
# including SIGKILL. The next sweep reclaims the unlocked workspace.
exec {scratch_fd}<"$staging"
flock --exclusive "$scratch_fd"
mv --no-clobber --no-target-directory -- "$staging" "$scratch"
[[ ! -e "$staging" ]]
trap - EXIT
export TMPDIR="$scratch"
exec "$@"
