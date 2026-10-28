#!/usr/bin/env bash
#
# Balanced local/agent test runs: one profile per kind of suite, a memory-aware
# `-j`, tag runs that load only the files carrying the tag, and every run
# through run_with_test_cleanup.sh (which also queues runs machine-wide, so two
# suites never overlap). Use this instead of hand-written `dart test` lines.
#
# Profiles (run from the repo root):
#   server-files <test files...>  server suites you name (pg allowed)
#   server-affected               server tests for files changed vs HEAD
#   server-unit                   dart test --exclude-tags pg, without toolchain
#   server-pg                     pg suites, without mr / perf / load
#   server-mr                     mr suites (always -j 1), without perf / load
#   server-gates                  analyzer baseline + custom lints (direct, as CI)
#   server-regression             server-gates + server-unit + server-pg, and
#                                 server-mr when the change touches Field /
#                                 visibility / trust code
#   client-files <test paths...>  flutter test on the paths you name
#   client-affected               client tests for files changed vs HEAD
#   client-all                    the whole client suite
#   client-gates                  analyzer baseline + custom lints
#
# Options (before the profile): --dry-run prints the commands; -j N overrides
# the computed concurrency. Never run perf or load suites here: they are
# manual measurements on an idle machine.
#
# Concurrency: -j = clamp(MemAvailable / per-suite budget, 1, profile cap),
# read once at start. Budgets and caps come from the measurements in
# docs/testing-resource-profile.md: on an idle 16-core / 61 GB machine every
# profile stays under ~7 GB, so the caps (CPU, Postgres, timing-sensitive
# tests) bind long before memory does; the budgets only bite when something
# else already holds the RAM.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$ROOT/scripts/run_with_test_cleanup.sh"
SELECT="$ROOT/scripts/ci_select_tests.py"

# profile -> "budget_mib cap"
declare -A BUDGET=(
  [server-unit]="1000 8"
  [server-files]="1500 4"
  [server-pg]="1500 6"
  [server-mr]="0 1"
  [client]="1500 8"
)

dry_run=0
force_j=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    -j) force_j="$2"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) break ;;
  esac
done
[[ $# -ge 1 ]] || { sed -n '2,26p' "$0" | sed 's/^# \?//'; exit 2; }
profile="$1"; shift

log() { printf '[run-tests] %s\n' "$*" >&2; }

mem_available_mib() {
  awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo
}

concurrency() {
  local key="$1" budget cap avail j
  if [[ -n "$force_j" ]]; then echo "$force_j"; return; fi
  read -r budget cap <<<"${BUDGET[$key]}"
  if [[ "$budget" -eq 0 ]]; then echo "$cap"; return; fi
  avail="$(mem_available_mib)"
  j=$(( avail / budget ))
  (( j > cap )) && j=$cap
  (( j < 1 )) && j=1
  echo "$j"
}

run() {
  local timeout="$1"; shift
  log "$* (timeout $timeout)"
  if [[ "$dry_run" -eq 1 ]]; then return 0; fi
  "$WRAP" --timeout "$timeout" -- "$@"
}

# `dart test` keeps every compiled kernel (~20-25 MB per test file) in TMPDIR
# until it exits, and TMPDIR is RAM (see run_with_test_cleanup.sh): a full
# server run in one call held 15-20 GB. Big file lists therefore run in
# chunks of TENTURA_TEST_CHUNK files (default 80, ~2 GB); every chunk runs
# even after a failure, and the profile fails if any chunk did.
# Usage: run_chunked <timeout> <dart test args...> -- <files...>
run_chunked() {
  local timeout="$1"; shift
  local -a args=() files=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do args+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  files=("$@")
  local size="${TENTURA_TEST_CHUNK:-80}" total="${#files[@]}" i=0 n=0 rc=0 failed=()
  local chunks=$(( (total + size - 1) / size ))
  while (( i < total )); do
    n=$((n + 1))
    log "chunk $n/$chunks (${#files[@]} files total)"
    if ! run "$timeout" "${args[@]}" "${files[@]:i:size}"; then
      rc=1
      failed+=("$n")
    fi
    i=$((i + size))
  done
  (( rc == 0 )) || log "failed chunks: ${failed[*]} of $chunks"
  return "$rc"
}

# Test files under packages/server/test that carry none of the given tags.
server_files_without_tags() {
  local -A skip=()
  local tag f
  for tag in "$@"; do
    while IFS= read -r f; do skip["$f"]=1; done < <(server_tagged_files "$tag")
  done
  (cd "$ROOT/packages/server" && find test -name '*_test.dart' | sort) |
    while IFS= read -r f; do [[ -n "${skip[$f]:-}" ]] || echo "$f"; done
}

# 0 when the library-level @Tags (before `library;`) of a server test file
# (relative to packages/server) carry the given quoted tag. awk's own exit
# status, no pipe, so pipefail cannot misreport it.
server_header_has_tag() {
  awk -v tag="$1" '/^library/ {exit} /^@Tags/ {t=1} t && index($0, "\x27" tag "\x27") || t && index($0, "\"" tag "\"") {found=1; exit} END {exit !found}' "$ROOT/packages/server/$2"
}

server_tagged_files() {
  (cd "$ROOT/packages/server" && python3 "$SELECT" test --tag "$1")
}

# Changed or untracked files under a package, relative to the package.
changed_in() {
  local pkg="$1"
  (cd "$ROOT" && { git diff --name-only HEAD -- "$pkg"; git ls-files --others --exclude-standard -- "$pkg"; } |
    sed -n "s|^$pkg/||p" | sort -u)
}

# Test files for changed files: changed tests themselves, plus tests that
# import a changed lib file by package URI. Direct imports only; the
# regression profile catches the rest.
affected_tests() {
  local pkg="$1" package_name="$2" f
  local -a libs=() tests=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      test/*_test.dart) [[ -f "$ROOT/$pkg/$f" ]] && tests+=("$f") ;;
      lib/*.dart) libs+=("${f#lib/}") ;;
    esac
  done < <(changed_in "$pkg")
  if (( ${#libs[@]} > 0 )); then
    local pattern
    pattern="$(printf 'package:%s/%s\n' "$package_name" "${libs[@]}" | sed 's/[.]/\\./g' | paste -sd'|')"
    while IFS= read -r f; do tests+=("$f"); done < <(
      cd "$ROOT/$pkg" && grep -rlE "($pattern)['\"]" test --include='*_test.dart' 2>/dev/null || true)
  fi
  printf '%s\n' "${tests[@]}" | sort -u | sed '/^$/d'
}

touches_mr_area() {
  changed_in packages/server | grep -qE '(constellation|visib|meritrank|trust|graph|/migration/m[0-9]+\.dart)'
}

server_files() {
  local -a files=("$@")
  (( ${#files[@]} > 0 )) || { log "no server test files"; return 0; }
  local j; j="$(concurrency server-files)"
  # mr-tagged files must not share the run with others: split them out.
  # rss-isolated files (RSS-growth bound) run one by one, after the shared run.
  local -a mr=() rest=() isolated=() f
  local rc=0
  for f in "${files[@]}"; do
    if grep -qE "['\"]mr['\"]" "$ROOT/packages/server/$f" 2>/dev/null; then mr+=("$f")
    elif server_header_has_tag rss-isolated "$f"; then isolated+=("$f")
    else rest+=("$f"); fi
  done
  if (( ${#rest[@]} > 0 )); then
    (cd "$ROOT/packages/server" && export TENTURA_PG_TESTS_REQUIRED=1 && run_chunked 30m dart test -j "$j" -- "${rest[@]}") || rc=1
  fi
  if (( ${#mr[@]} > 0 )); then
    (cd "$ROOT/packages/server" && export TENTURA_PG_TESTS_REQUIRED=1 && run 30m dart test -j 1 "${mr[@]}") || rc=1
  fi
  for f in "${isolated[@]}"; do
    (cd "$ROOT/packages/server" && export TENTURA_PG_TESTS_REQUIRED=1 && run 10m dart test -j 1 "$f") || rc=1
  done
  return "$rc"
}

server_unit() {
  local j; j="$(concurrency server-unit)"
  # toolchain suites re-run the analyzer gates; server-gates runs those directly.
  local -a files; mapfile -t files < <(server_files_without_tags pg toolchain)
  (cd "$ROOT/packages/server" && \
    run_chunked 25m dart test -j "$j" --exclude-tags pg -x toolchain -- "${files[@]}")
}

gates() {
  local pkg="$1"
  (cd "$ROOT" && run 2m python3 scripts/check_cross_package_imports.py)
  log "check-analyze-baseline $pkg"
  [[ "$dry_run" -eq 1 ]] || (cd "$ROOT" && bash scripts/check-analyze-baseline.sh "$pkg")
  (cd "$ROOT" && run 10m ./scripts/check-custom-lints.sh "$pkg")
}

server_pg() {
  local j; j="$(concurrency server-pg)"
  # A file whose library-level @Tags has mr is excluded whole by -x mr
  # (server_mr runs it); passing it anyway makes a chunk made only of such
  # files fail with "No tests ran".
  local -a files=() isolated=() all f; mapfile -t all < <(server_tagged_files pg)
  for f in "${all[@]}"; do
    if ! server_header_has_tag mr "$f"; then
      if server_header_has_tag rss-isolated "$f"; then
        isolated+=("$f")
      else
        files+=("$f")
      fi
    fi
  done
  # RSS includes every isolate in a dart test process. Keep these suites out
  # of shared chunks, while still running them even if a shared chunk fails.
  local rc=0
  (cd "$ROOT/packages/server" && export TENTURA_PG_TESTS_REQUIRED=1 && \
    run_chunked 40m dart test -j "$j" --tags pg -x mr -x perf -x load -- "${files[@]}") || rc=1
  for f in "${isolated[@]}"; do
    (cd "$ROOT/packages/server" && export TENTURA_PG_TESTS_REQUIRED=1 && \
      run 10m dart test -j 1 --tags pg -x mr -x perf -x load "$f") || rc=1
  done
  return "$rc"
}

server_mr() {
  local -a files; mapfile -t files < <(server_tagged_files mr)
  (cd "$ROOT/packages/server" && export TENTURA_PG_TESTS_REQUIRED=1 && \
    run_chunked 45m dart test -j 1 --tags mr -x perf -x load -- "${files[@]}")
}

client_run() {
  local j; j="$(concurrency client)"
  (cd "$ROOT/packages/client" && run 60m flutter test -j "$j" \
    --dart-define=ENV=test --dart-define-from-file=env/test.env "$@")
}

case "$profile" in
  server-files) server_files "$@" ;;
  server-affected) mapfile -t t < <(affected_tests packages/server tentura_server); server_files "${t[@]}" ;;
  server-unit) server_unit ;;
  server-pg) server_pg ;;
  server-mr) server_mr ;;
  server-gates) gates packages/server ;;
  client-gates) gates packages/client ;;
  server-regression)
    gates packages/server
    server_unit
    server_pg
    if touches_mr_area; then server_mr; else log "server-mr skipped: no Field/visibility/trust change"; fi
    ;;
  client-files) client_run "$@" ;;
  client-affected)
    mapfile -t t < <(affected_tests packages/client tentura)
    if (( ${#t[@]} == 0 )); then log "no affected client tests"; else client_run "${t[@]}"; fi
    ;;
  client-all) client_run ;;
  *) log "unknown profile: $profile"; exit 2 ;;
esac
