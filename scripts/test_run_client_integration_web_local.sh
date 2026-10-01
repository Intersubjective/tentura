#!/usr/bin/env bash
# Behavioural tests for scripts/run_client_integration_web_local.sh when the
# repo root has .env.example but no gitignored .env (fresh worktree). The
# runner must bootstrap .env and continue into the stack-prep path (past the
# missing-file and QA .env checks), without clobbering an existing .env.
#
# Downstream services are stubbed only through the QA bootstrap smoke call —
# the first reliable continuation point after env validation.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REAL_ROOT}/scripts/run_client_integration_web_local.sh"
EXAMPLE_ENV="${REAL_ROOT}/.env.example"

[[ -f "$SCRIPT" ]] || { echo "missing $SCRIPT" >&2; exit 1; }
[[ -f "$EXAMPLE_ENV" ]] || { echo "missing $EXAMPLE_ENV" >&2; exit 1; }

fail() { echo "FAIL: $1" >&2; [[ -f "${OUT:-}" ]] && sed 's/^/  out: /' "$OUT" >&2; exit 1; }
ok() { echo "OK: $1"; }

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

stub() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$1"
  chmod +x "$1"
}

# run_case <name> [WITH_ENV=1]
run_case() {
  local name="$1"
  local with_env="${2:-}"

  T="$TMP_BASE/$name"
  ROOT="$T/root"
  OUT="$T/out.log"
  local BIN="$T/bin"
  mkdir -p "$ROOT/scripts" "$BIN"
  cp "$SCRIPT" "$ROOT/scripts/"
  cp "${REAL_ROOT}/scripts/gen-dev-jwt.sh" "$ROOT/scripts/"
  cp "$EXAMPLE_ENV" "$ROOT/.env.example"

  if [[ "$with_env" == WITH_ENV=1 ]]; then
    cat >"$ROOT/.env" <<'EOF'
# preseeded marker
QA_AUTH_ENABLED=true
QA_SIMPLE_LOGIN_MODE=true
QA_AUTH_TOKEN=preseeded
EOF
  fi

  stub "$ROOT/scripts/run-server-local.sh" 'exit 0'

  stub "$BIN/curl" '
url=""
for a in "$@"; do case "$a" in http*) url="$a";; esac; done
case "$url" in
  *:8080/healthz|*:2080/health) exit 0 ;;
  */_qa/integration/bootstrap)
    example_pub="$(grep -E "^JWT_PUBLIC_PEM=" "$SCRATCH_ROOT/.env.example" | cut -d= -f2-)"
    current_pub="$(grep -E "^JWT_PUBLIC_PEM=" "$SCRATCH_ROOT/.env" | cut -d= -f2-)"
    [[ "$current_pub" == "$example_pub" ]] && exit 22
    exit 0
    ;;
  *) exit 0 ;;
esac'

  set +e
  env PATH="$BIN:$PATH" SCRATCH_ROOT="$ROOT" timeout 45 bash "$ROOT/scripts/run_client_integration_web_local.sh" \
    >"$OUT" 2>&1
  RC=$?
  set -e
}

assert_past_env_bootstrap() {
  if grep -qE 'missing .*/\.env \(copy \.env\.example\)' "$OUT"; then
    fail "must not die on missing .env when .env.example is present"
  fi
  grep -q 'QA bootstrap OK' "$OUT" \
    || fail "runner must reach the QA bootstrap smoke checkpoint after env validation (rc=$RC)"
  if grep -qE 'QA bootstrap smoke call failed' "$OUT"; then
    fail "QA bootstrap smoke must succeed, not fail"
  fi
}

assert_jwt_initialized() {
  local example_pub current_pub
  example_pub="$(grep -E '^JWT_PUBLIC_PEM=' "$ROOT/.env.example" | cut -d= -f2-)"
  current_pub="$(grep -E '^JWT_PUBLIC_PEM=' "$ROOT/.env" | cut -d= -f2-)"
  [[ -n "$current_pub" && "$current_pub" != "$example_pub" ]] \
    || fail "fresh bootstrap must replace placeholder JWT keys (without echoing key material)"
}

assert_qa_defaults() {
  grep -qE '^ENVIRONMENT=dev$' "$ROOT/.env" || fail "fresh bootstrap must set ENVIRONMENT=dev"
  grep -qE '^QA_AUTH_ENABLED=true$' "$ROOT/.env" || fail "fresh bootstrap must set QA_AUTH_ENABLED=true"
  grep -qE '^QA_SIMPLE_LOGIN_MODE=true$' "$ROOT/.env" \
    || fail "fresh bootstrap must set QA_SIMPLE_LOGIN_MODE=true"
  grep -qE '^QA_AUTH_TOKEN=local-dev-qa-token$' "$ROOT/.env" \
    || fail "fresh bootstrap must set QA_AUTH_TOKEN=local-dev-qa-token"
}

# --- case 1: fresh worktree (only .env.example) ------------------------------
run_case fresh_worktree
assert_past_env_bootstrap
[[ -f "$ROOT/.env" ]] || fail "expected .env to exist after bootstrap"
grep -q '^POSTGRES_PASSWORD=password' "$ROOT/.env" \
  || fail ".env must retain content from .env.example after bootstrap"
assert_jwt_initialized
assert_qa_defaults
ok "bootstraps .env from .env.example and continues past env validation"

# --- case 2: existing .env is left intact ------------------------------------
run_case keeps_existing WITH_ENV=1
assert_past_env_bootstrap
grep -q '^# preseeded marker$' "$ROOT/.env" \
  || fail "existing .env contents must be preserved"
grep -q '^QA_AUTH_TOKEN=preseeded$' "$ROOT/.env" \
  || fail "must not replace an existing .env when bootstrapping"
ok "does not clobber a pre-existing .env and still reaches QA bootstrap"

echo "All run_client_integration_web_local tests passed."
