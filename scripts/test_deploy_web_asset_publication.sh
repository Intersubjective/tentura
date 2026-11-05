#!/usr/bin/env bash
# Exercise the real deploy entry point; only external Docker calls are stubbed.
# A kernel-event observer checks the live publication order without sleeps.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASE="${1:-dev}"
MODE="${2:-all}"
# An artifact produced by the client build tests can replace the canned payload.
# The expected version is supplied independently, from that test's pubspec.
ARTIFACT_DIR="${3:-}"
[[ -z "$ARTIFACT_DIR" || -n "${4:-}" ]] || { echo 'Artifact input needs its expected version' >&2; exit 2; }
[[ "$CASE" == dev || "$CASE" == prod ]] || { echo 'Expected dev or prod' >&2; exit 2; }
[[ "$MODE" == all || "$MODE" == order-only ]] || { echo 'Expected all or order-only' >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tentura-web-publication.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
DEPLOY="$WORK/$CASE deployment"
WEB="$DEPLOY/web"
PAYLOAD="$WORK/payload"
mkdir -p "$WORK/bin" "$WEB/assets/packages" "$WEB/canvaskit" \
  "$DEPLOY/hasura" "$DEPLOY/scripts" "$DEPLOY/landing" "$PAYLOAD"

cat > "$WORK/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  inspect) echo 'fixture_backend' ;;
  compose)
    case " $* " in
      *' ps -q hasura '*) echo 'fixture-hasura' ;;
    esac ;;
esac
DOCKER
# Deploy hosts do not provide rsync. Fail even on a developer machine where
# a system installation would otherwise hide that dependency.
cat > "$WORK/bin/rsync" <<'RSYNC'
#!/bin/sh
echo 'rsync is unavailable on the deploy host' >&2
exit 127
RSYNC
chmod +x "$WORK/bin/docker" "$WORK/bin/rsync"
printf '%s\n' 'HASURA_GRAPHQL_ADMIN_SECRET=fixture-only' > "$DEPLOY/.env"
printf '{}\n' > "$DEPLOY/hasura/metadata.json"
printf '# fixture consumed by the Docker stub\n' > "$DEPLOY/scripts/hasura_apply_metadata.sh"
printf '<p>Existing landing</p>\n' > "$DEPLOY/landing/index.html"
printf 'services: {}\n' > "$DEPLOY/compose.prod.yaml"
if [[ "$CASE" == dev ]]; then
  printf 'services: {}\n' > "$DEPLOY/compose.override.yaml"
fi

printf 'stale sqlite\n' > "$WEB/assets/packages/sqlite3.wasm"
printf 'stale worker\n' > "$WEB/assets/packages/drift_worker.js"
printf 'stale renderer\n' > "$WEB/canvaskit/canvaskit.wasm"
printf 'obsolete root file\n' > "$WEB/obsolete.js"
# More than the default retention window, with deterministic directory ages.
# Root synchronization must preserve these; only the later retention step
# may remove versions older than the window.
for number in $(seq 0 21); do
  mkdir -p "$WEB/app-assets/previous-$number/assets/packages"
  printf 'old build %s\n' "$number" > "$WEB/app-assets/previous-$number/assets/packages/sqlite3.wasm"
  touch -m -t "202001010000.$(printf '%02d' "$number")" "$WEB/app-assets/previous-$number"
done

VERSION="${4:-9.0.0-new-build}"
mkdir -p "$PAYLOAD/app-assets/$VERSION/assets/packages" "$PAYLOAD/app-assets/$VERSION/canvaskit"
printf 'new sqlite\n' > "$PAYLOAD/app-assets/$VERSION/assets/packages/sqlite3.wasm"
printf 'new worker\n' > "$PAYLOAD/app-assets/$VERSION/assets/packages/drift_worker.js"
printf 'new renderer\n' > "$PAYLOAD/app-assets/$VERSION/canvaskit/canvaskit.wasm"
# A restored/cached archive can carry old directory timestamps. The version
# selected by the NEW bootstrap must survive even outside the newest twenty.
touch -m -t 201901010000 "$PAYLOAD/app-assets/$VERSION"
for entry in index.html flutter_bootstrap.js tentura-app-cache-sw.js version.json manifest.json; do
  printf 'old entry\n' > "$WEB/$entry"
done
printf '_flutter.loader.load({config:{assetBase:"/app-assets/previous-0/"}});\n' > "$WEB/flutter_bootstrap.js"
printf '<!doctype html><script src="flutter_bootstrap.js?v=%s"></script>\n' "$VERSION" > "$PAYLOAD/index.html"
printf '_flutter.loader.load({config:{assetBase:"/app-assets/%s/"}});\n' "$VERSION" > "$PAYLOAD/flutter_bootstrap.js"
printf 'const CACHE_VERSION = "%s";\n' "$VERSION" > "$PAYLOAD/tentura-app-cache-sw.js"
printf '{"version":"%s"}\n' "$VERSION" > "$PAYLOAD/version.json"
printf '{"name":"Tentura","version":"%s"}\n' "$VERSION" > "$PAYLOAD/manifest.json"
printf 'root PWA icon\n' > "$PAYLOAD/tentura-icon-192.png"
if [[ -n "$ARTIFACT_DIR" ]]; then
  rm -rf "$PAYLOAD"
  mkdir -p "$PAYLOAD"
  cp -a "$ARTIFACT_DIR/." "$PAYLOAD/"
  touch -m -t 201901010000 "$PAYLOAD/app-assets/$VERSION"
fi

failures=0
check() {
  local description="$1"
  shift
  if "$@"; then
    printf 'OK: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description" >&2
    failures=$((failures + 1))
  fi
}

for attempt in 1 2; do
  ARCHIVE="$WORK/web-$CASE-$attempt.tar.gz"
  # Archive enumeration must not decide which build an open tab can load.
  # Put entry files first to expose an unsafe direct extraction into live web.
  tar -czf "$ARCHIVE" -C "$PAYLOAD" index.html flutter_bootstrap.js \
    tentura-app-cache-sw.js version.json manifest.json tentura-icon-192.png app-assets
  if [[ "$attempt" -eq 1 ]]; then
    check "$CASE new version starts absent" test ! -e "$WEB/app-assets/$VERSION"
    observe=(python3 "$ROOT/scripts/test_support/observe_web_publication.py"
      "$WEB" "$PAYLOAD" "$WORK/deploy.log" --)
  else
    # Reapply the same archive to check idempotence. Publication ordering was
    # checked above with an absent version, never with pre-existing assets.
    observe=()
  fi
  # Explicitly set every deployment path: never touch the live web or Docker.
  if "${observe[@]}" \
    env PATH="$WORK/bin:$PATH" DEPLOY_DIR="$DEPLOY" WEB_DIR='./web' \
    LANDING_DIR='./landing' LANDING_ARCHIVE="$WORK/no-landing.tar.gz" \
    COMPOSE_FILE='compose.prod.yaml' OVERRIDE_FILE='compose.override.yaml' \
    APP_ASSETS_KEEP=20 bash "$ROOT/deploy.sh" "$ARCHIVE" > "$WORK/observation.log" 2>&1; then
    cat "$WORK/observation.log"
    :
  else
    status=$?
    cat "$WORK/observation.log" >&2
    if [[ "$status" -eq 86 ]]; then
      failures=$((failures + 1))
    else
      echo 'FAIL: deploy entry point or publication observer did not finish' >&2
      exit 1
    fi
  fi
  [[ "$MODE" == all ]] || continue
  check "$CASE deployment $attempt serves the expected bootstrap version" \
    grep -Fq "flutter_bootstrap.js?v=$VERSION\"" "$WEB/index.html"
  check "$CASE deployment $attempt never serves the source placeholder" \
    test "$(grep -Fc 'flutter_bootstrap.js?v=0.0.0-dev' "$WEB/index.html" || true)" -eq 0
  check "$CASE deployment $attempt removes stale root assets" test ! -e "$WEB/assets"
  check "$CASE deployment $attempt removes stale root canvaskit" test ! -e "$WEB/canvaskit"
  check "$CASE deployment $attempt removes obsolete root files" test ! -e "$WEB/obsolete.js"
  for number in $(seq 2 21); do
    check "$CASE deployment $attempt preserves retained previous-$number bytes" \
      grep -qx "old build $number" "$WEB/app-assets/previous-$number/assets/packages/sqlite3.wasm"
  done
  for number in 0 1; do
    check "$CASE deployment $attempt prunes expired previous-$number" \
      test ! -e "$WEB/app-assets/previous-$number"
  done
  for asset in assets/packages/sqlite3.wasm assets/packages/drift_worker.js canvaskit/canvaskit.wasm; do
    check "$CASE deployment $attempt publishes $asset" \
      cmp -s "$PAYLOAD/app-assets/$VERSION/$asset" "$WEB/app-assets/$VERSION/$asset"
  done
  for entry in index.html flutter_bootstrap.js tentura-app-cache-sw.js version.json manifest.json tentura-icon-192.png; do
    check "$CASE deployment $attempt updates $entry" cmp -s "$PAYLOAD/$entry" "$WEB/$entry"
  done
done
[[ "$failures" -eq 0 ]]
