# AGENTS.md — Tentura

Cross-tool entry point for AI coding agents (Claude Code, Cursor, Copilot, etc.).
This is the always-on index; depth lives in the linked rules/docs — read them only when the trigger matches.

## Project shape

Pub workspace with three packages: `packages/client` (Flutter app, package
`tentura`), `packages/server` (Dart), `packages/tentura_lints` (custom analyzer
plugin). See `DEVELOPMENT.md` and `DEV_GUIDELINES.md`.

## Rules index (read depth only when the trigger matches)

| When | Read |
|------|------|
| Exploring / "how does X work" | `.cursor/rules/search-tools.mdc` |
| Editing Dart (domain/data/ui/features) | `.cursor/rules/architecture.mdc` (+ `advanced-patterns.mdc` for base/platform/exception/mock) |
| Client UI (features/ui, design_system) | `.cursor/rules/tentura-design-system.mdc` + `docs/tentura-design-system.md` |
| GraphQL / codegen / build / DI | `.cursor/rules/codegen.mdc` |
| Procedures (real-time invalidation, V2 routing, invite, read-state, ferry scalars) | `DEV_GUIDELINES.md` |
| Product behavior / vocabulary | `docs/README.md`, `CONTEXT.md`, `.cursor/rules/terminology.mdc` |
| Verifying changes | `.cursor/rules/lint-after-changes.mdc` |
| Versioning / `MIN_CLIENT_VERSION` | `.cursor/rules/versioning.mdc` |

## Invariants (always true; most are lint-enforced)

- **Dependency direction is inward:** domain stays pure; data implements domain ports; ui → domain/data. (lints: `no_domain_to_data_or_ui_import`, `no_cubit_to_data_service_import`)
- **Repositories return domain entities**, never Ferry/Drift types. Cubits coordinating ≥2 repos inject a `*Case`. (lint: `cubit_requires_use_case_for_multi_repos`)
- **Client UI uses the design system:** no raw `Color`/`Colors.*`, `TextStyle(…)`, inline `fontSize:`, or `EdgeInsets`/`BorderRadius` from raw numbers in `features/**` / `ui/**`; use `context.tt` tokens and `TenturaText.*`. (lints: `no_inline_font_size`, `no_operational_raw_color`, `no_raw_edge_insets`, `no_raw_border_radius`)
- **Never edit generated files** (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.schema.dart`); run codegen instead.
- **Search ladder:** known path → Read; semantic → Serena MCP; then Grep/Glob.
- **Terminology alias:** user-facing **Request** / **discussion** (workspace), **Activity** / «Активность» (home nav branch; `Activity (internally: inbox)` in docs), **thread** / **General** (one conversation); internal **Beacon** (`Request (internally: Beacon)` in docs). Never introduce a `Request` domain entity. See `.cursor/rules/terminology.mdc` and `bash scripts/check-user-facing-terminology.sh`.
- **Client versioning + gate:** user-visible client changes require a semver bump in `packages/client/pubspec.yaml`; when a release forces clients to update, raise `kDefaultMinClientVersion` in `packages/server/lib/env.dart` (see `.cursor/rules/versioning.mdc` and `DEV_GUIDELINES.md` § Client version gate).
- **No golden tests.** Golden/pixel-comparison tests are disabled project-wide — never write, update or restore them, even if a bead's acceptance criteria ask; use structural widget tests instead. See `.cursor/rules/no-golden-tests.mdc`.
- **Rooms are General-only — there are no item threads.** Code mentioning `thread_item_id` / `threadItemId` / `_canAccessThread` / item participants is dormant machinery kept on purpose (marked `DORMANT(item-threads)`); the DB guard `beacon_room_message_general_only_guard` rejects non-General rows. Never design features, access rules or reviews around item threads. See #192.
- **Web cache-buster must ship with every client version bump:** `packages/client/web/index.html`'s `flutter_bootstrap.js?v=<version>` query is a real, git-tracked source file (unlike `web/manifest.json`, which is deliberately `skip-worktree` and never needs committing) — it only gets rewritten to match `pubspec.yaml` when you actually run/build the app locally (`flutter run`/`flutter build web`; the `hook/build.dart` build hook does it, not `build_runner`). Before committing a version bump, run the app once and check `git status` for a resulting `web/index.html` diff, or hand-verify the `?v=` matches. A missed bump here means browsers keep serving a cached pre-fix JS bundle after a real fix ships — this has happened before (`git log -- packages/client/web/index.html` shows recurring catch-up `chore: sync web cache-buster` commits) and once made a landed bug fix look like it "didn't work."

## Product docs

Orientation and feature specs live under [`docs/`](docs/) — start at [`docs/README.md`](docs/README.md). High-signal: [`docs/Tentura_current_status_quo.md`](docs/Tentura_current_status_quo.md), [`docs/features/beacon_room.md`](docs/features/beacon_room.md).

## Verify

Local/agent test runs **must** go through `scripts/run_with_test_cleanup.sh`.
It time-bounds the command, SIGKILLs hung descendants, and deletes
unreferenced `/tmp/flutter_tools.*` + `/tmp/dart_test.kernel.*` (those live
on a RAM tmpfs). CI does **not** use it (ephemeral runners). Do not wrap
`flutter run` or `scripts/run_client_integration_web_local.sh`.

```bash
# sweep leftovers from a killed agent, no new tests
./scripts/run_with_test_cleanup.sh --sweep-only

cd packages/tentura_lints && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/client
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- \
  flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg
# Postgres tests run in two steps. The `mr` ones also reach the MeritRank
# service, which is a single shared container every disposable database talks
# to, so they must not run in parallel with each other.
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- \
  dart test --tags pg --exclude-tags mr
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- \
  dart test --tags mr -j 1
```

> Disposable pg databases are cloned from a prebuilt template
> (`tentura_test_tpl_<registry-hash>`, see `test/support/disposable_pg_target.dart`)
> rather than migrated one by one — `migrateDbSchema` holds a **cluster-wide**
> advisory lock, and 95 test files serializing on it for a full schema build was
> the main source of load-dependent failures. The template rebuilds itself when
> the migration registry changes. Stale `tentura_test_*` databases are dropped by
> `run_with_test_cleanup.sh --sweep-only` (older than `PG_GC_MIN_AGE_MIN`,
> default 120 min, and with no live connection); it is maintenance only and
> never runs as part of a test run. `tentura_test_tpl_*` templates are kept on
> purpose and reused across runs.
>
> **Never run two wrapped suites at once.** They sweep each other's
> `/tmp/dart_test.kernel.*`, and every test file then fails to load with an empty
> "Failed to load" message that looks nothing like the real cause.
>
> Never query `pg_locks` or `pg_stat_activity` from a test without scoping to
> `current_database()` (or `datname = <own database>`): they report the whole
> cluster, and another database's schema upgrade will satisfy an unqualified
> predicate. See `test/support/pg_wait.dart` for the wait-budget rule.

Never start a bare `flutter test` / `dart test` / `dart analyze` in the
background. Default suite timeout is 45m (`--timeout`); override shorter
for a single file. Wrapper self-check: `bash scripts/run_with_test_cleanup_selftest.sh`. Full/unwritable-`TMPDIR` behaviour (tentura-ah4): `bash scripts/run_with_test_cleanup_enospc_selftest.sh`.

> Do **not** use `flutter analyze` to check `tentura_lints` rules — it does not load analyzer
> plugins and always reports them clean. Nor `dart analyze <subdir>`: plugin diagnostics only
> surface when the target is the package root. Nor Dart MCP `analyze_files`: it spawns a
> second language-server and can freeze the machine; use `ReadLints` plus
> `scripts/check-custom-lints.sh`. That script invokes the analyzer correctly and ratchets
> the count against `scripts/custom-lint-baseline.txt`.

CI (`.github/workflows/pipeline.yml`) runs the lint tests, `scripts/check-custom-lints.sh` for
both packages, `bash scripts/check-user-facing-terminology.sh`, and `flutter test` on every push
to `main`.

## Cursor Cloud specific instructions

Standard dev setup is in `DEVELOPMENT.md` and the `local-debug` skill; only the non-obvious cloud caveats are below. Flutter 3.44 lives at `/opt/flutter/bin` (on `PATH` via `~/.bashrc`). Docker, Caddy, and `jq` are pre-installed in the snapshot. The startup update script only runs `flutter pub get`; everything else (Docker daemon, infra, servers) must be started manually.

**Fast bring-up:** `sudo service docker start`, then `./scripts/dev-up.sh` (bootstraps `.env` with a real JWT keypair, starts infra, starts the Tentura API in the background if it isn't already up, applies Hasura metadata), then run the two foreground processes it prints (`run-flutter-web-local.sh`, Caddy).

- **Generated code + `.env` persist in the snapshot, not git.** `*.g.dart`/`*.gr.dart`/`*.config.dart`/l10n and repo-root `.env` are git-ignored but were generated/created during setup and live in the snapshot. Re-run codegen only after changing GraphQL/Freezed/Drift/AutoRoute/Injectable/`.arb`: `cd packages/client && flutter gen-l10n && dart run build_runner build -d` (and `dart run build_runner build -d` in `packages/server`).
- **Start Docker before infra:** `sudo service docker start` (daemon does not auto-start). Docker 29 uses `fuse-overlayfs` with `containerd-snapshotter` disabled (`/etc/docker/daemon.json`).
- **Server rejects the placeholder JWT keys.** Under `ENVIRONMENT=dev/prod`, `Env._assertJwtKeys` refuses the `.env.example` keys. Generate a real dev keypair with `./scripts/gen-dev-jwt.sh` (or `./scripts/dev-up.sh`); after rotating keys, recreate Hasura (`docker compose up -d --force-recreate hasura`) so `HASURA_GRAPHQL_JWT_SECRET` matches, else Hasura returns `invalid-jwt`.
- **QA login needs `ENVIRONMENT=dev`** (set by `dev-up.sh` / `.env.example`) plus `QA_SIMPLE_LOGIN_MODE=true` + `QA_AUTH_ENABLED=true`; QA routes 404 under the default `prod`. `access-token` is a **POST** to `/api/v2/session/access-token` and returns `access_token` (snake_case).
- **Hasura metadata must be applied** or the app shows `field 'beacon'/'invitation' not found in type: 'query_root'` on My Work / My people. `dev-up.sh` does this; standalone: `./scripts/hasura_apply_metadata.sh`.
- **Flutter web binds IPv4 via `run-flutter-web-local.sh`** (`--web-hostname=127.0.0.1`, overridable with `LOCAL_FLUTTER_HOSTNAME`). Without that it binds `::1`, which `Caddyfile.local`'s `127.0.0.1:8888` upstream can't reach → 502 on app paths.
- **Caddy needs sudo and a trusted CA for the Chrome/computerUse browser:** `sudo caddy run --config Caddyfile.local`. The Caddy local root CA is installed into the system store and the user NSS DB (`~/.pki/nssdb`) so `https://dev.lvh.me:9443` is trusted; `dev.lvh.me` is mapped to `127.0.0.1` in `/etc/hosts`.
- **UI text entry:** the Flutter web app uses CanvasKit, so DOM typing does not reach the framework — set up state via the v2 API (e.g. `beaconCreate`) and use the UI to view it (see `local-debug` skill). The landing page (`/`, plain HTML) accepts typing, so the QA "Test login" form there works (enabled via `packages/landing/config.local.js` `qaTestLogin: true`).

<!-- headroom:learn:start -->
## Headroom Learned Patterns
*Auto-generated by `headroom learn` on 2026-08-23 — do not edit manually*

### Local dev server port checks
*~52,001 tokens/session saved*
- Before running `flutter run -d web-server --web-port=8888 ...` or `./scripts/run-flutter-web-local.sh`, check whether port 8888 is already bound (`ss -ltnp | rg ':8888'` or `lsof -iTCP:8888 -sTCP:LISTEN`) — re-invoking the dev server against an already-running instance was repeated 85x in one session for ~52k wasted tokens.

### dev.tentura.io deploy proxy quirk
*~30,168 tokens/session saved*
- The prod/dev proxy (Caddy on dev.tentura.io) is sensitive to `server block without any key must be first` ordering and APP_HOST env wiring; TLS errors from `curl` against it after a Caddyfile edit usually mean the server block order broke, not a network issue — check Caddyfile block order before re-testing TLS repeatedly.

### GitHub Actions workflow validation (no gh/ruby/yq locally)
*~21,976 tokens/session saved*
- `gh`, `ruby`, and `yq` are not installed locally — don't try them for `.github/workflows/*.yml` work.
- Validate YAML syntax with `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pipeline.yml'))"`, and lint semantics with `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest .github/workflows/pipeline.yml`.

<!-- headroom:learn:end -->

<!-- alloy:memory:begin -->
reviewed: 2026-10-01
review due: 2026-10-08

### alloy:lesson:attention_receipt_missing_from_custom_types
When adding or wiring a server custom GraphQL object type, register it in the top-level list in packages/server/lib/api/controllers/graphql/custom_types.dart; a missing entry breaks runtime queries (e.g. AttentionFeed) even if the type definition exists elsewhere.

### alloy:lesson:hasura_jwt_secret_stale_after_env_key_rotation
Fixed: Hasura's JWT_SECRET was stale because .env's JWT keypair was regenerated after the Hasura container was created (compose.dev.yaml templates HASURA_GRAPHQL_JWT_SECRET from ${JWT_PUBLIC_PEM} only at container-creation time, not on restart). Ran 'docker compose -f compose.dev.yaml up -d --force-recreate hasura' and verified the container's JWT_SECRET now matches .env's current public key. This was environment drift, not a code defect. The local docker infra (postgres/hasura/meritrank/minio) is up; if you need the tentura-server itself running for the e2e, start it via scripts/run-server-local.sh (not a bare dart run, which uses compiled-in default JWT keys and would reintroduce the same class of failure).

### alloy:lesson:realtime_contract_manifest_stale_test_names
docs/contracts/realtime-entity-contract.json lists concrete test file paths per realtime kind/impact; test/architecture/realtime_entity_contract_test.dart fails if any listed path no longer exists. In tentura-617.25, landing-gate test files referenced in the manifest (tentura_rsm_landing_check_test.dart, room_message_reply_quote_landing_check_test.dart) had been renamed/consolidated to beacon_threads_case_test.dart and room_message_reply_quote_test.dart, so the contract test failed even though the bead's diff was fine. Two attempts were wasted trying to restore the old files or dismiss the failure as unrelated before the real fix (updating the manifest's file names) landed. When this test fails citing a missing file, check if the cited test was simply renamed before assuming a regression, and fix by updating the manifest's path, not recreating the file or expanding scope.

### alloy:lesson:realtime_kind_requires_contract_manifest_entry
Adding a new RealtimeEntityKind (wire kind) in packages/client also requires a matching entry in docs/contracts/realtime-entity-contract.json (wireKind, acceptedWireKinds, clientKind, genericTriggerArgs, specializedPublishers, impacts, tests). Otherwise test/architecture/realtime_entity_contract_test.dart fails; attempt #1 of tentura-gfz failed on exactly this. Run that contract test as part of targeted checks for any realtime vocabulary change. Also update all touch points: the enum wire mapping, the InvalidationService payload parse (drop the frame if extras are invalid), the dedup key, and BeaconRoomInvalidation (enum, fromRealtimeChange arm, ==/hashCode).

### alloy:lesson:release_version_bump_hardcoded_test_literal
Client release-version-bump beads (pubspec.yaml + web/index.html cache-buster + kDefaultMinClientVersion in packages/server/lib/env.dart) trip on a hidden fourth spot: packages/server/test/min_client_version_gate_test.dart's "is the next minor, not a jump that skips a real release" test hardcodes `expect(kDefaultMinClientVersion, '7.19.0')` (a literal prior version). Bumping only the three known files (pubspec, index.html, env.dart) leaves this test failing, and it was mis-diagnosed as a design defect for 2 attempts before being fixed by rewriting the assertion to compare against a helper (`_shippedClientVersion()`) that reads the version live from `../client/pubspec.yaml`, instead of a literal. How to apply: when doing a release version bump, grep server tests for the *old* client version string (e.g. `rg '7\.19\.0|7\.23\.0'` or whatever the pre-bump version is) before declaring done — any hardcoded-literal assertion of kDefaultMinClientVersion needs to become a dynamic comparison (read pubspec.yaml/index.html directly, as done in the new release_client_version_floor_test.dart) so it doesn't need re-editing on every future release.

### alloy:lesson:server_analyze_exit2_minimal_root_cause_not_shotgun_fix
In tentura-617.4, package-wide dart analyze in packages/server exited 2 due to ~2100 pre-existing info-level issues plus one warning. Across 15 attempts the agent tried to fix this by expanding scope massively (142 files touched), including an unrelated domain-to-data move of trust_maintenance_case.dart and edits to auth_middleware.dart, auth_case.dart, sentry files, and dozens of unrelated test/lint touch-ups, duplicating work already tracked in separate bug beads. The human had to manually revert the worktree back to the bead's declared 7 files. Why: the ~2100 info-level issues do not affect dart analyze's exit code by default; only the one warning did, and the actual minimal fix was a single analysis_options.yaml line (plugins_in_inner_options: ignore). Likewise a domain-purity grep hit from a pre-existing unrelated file should not be fixed by moving/editing that file mid-bead. How to apply: before broadening a fix for a failing package-wide gate, isolate whether the failure is caused by pre-existing issues unrelated to your diff, and look for a single minimal change that clears the gate rather than touching many files. If a required check reports a hit outside your bead's declared file scope, report it as a follow-up bug bead instead of editing the offending file, and never edit outside an explicitly declared file scope without stopping first to report a separate bug bead.

### alloy:lesson:web_build_check_requires_wasm_flags
In tentura-617.33, 7 attempts were wrongly judged "repair"/"retry" because `flutter build web && ... && verify_web_version_consistency.dart` failed — but that invocation is wrong. The required check must run `flutter build web --wasm --pwa-strategy=none --dart-define=ENV=test --dart-define-from-file=env/test.env` (matching CI), then `dart run tool/trim_web_deploy_artifact.dart`, `apply_versioned_web_assets.dart`, and `generate_wasm_preload_artifacts.dart` (which populates build/web/app-assets/<version>/main.dart.wasm+.mjs and refreshes manifest.json/wasm-preload-manifest.json) before `verify_web_version_consistency.dart` will pass — a plain `flutter build web` produces artifacts the wasm-preload manifest checker rejects. Filed as tentura-270 (the required-check command definition itself still lacks --wasm) but not yet fixed at the tooling level. How to apply: for any client bead touching user-visible UI (pubspec.yaml patch bump + web/index.html cache-buster), when running/asked to run the web-build gate, use the full wasm pipeline above wrapped in `./scripts/run_with_test_cleanup.sh --timeout 20m --`, not a bare `flutter build web`. If the check still fails after that, it's likely a real defect, not a stale-artifact false negative.

### alloy:lesson:worktree_dev_scripts_pin_compose_project_and_sync_env
Tentura local dev scripts run from an Alloy worktree hit two footguns. (1) compose.dev.yaml uses fixed container_name values, so bare `docker compose up -d` in a worktree creates a project named after the checkout dir and fails with 'container name /minio is already in use'. Fix: `COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-tentura}" docker compose up -d` (respect a caller override; the script already skips compose when :8080/healthz is healthy). (2) packages/client/env/local-web.env is gitignored and absent in fresh worktrees. Run `scripts/sync-client-local-config.sh` and then `scripts/resolve_local_web_config.sh --check-only` before `flutter run`, mirroring run-flutter-web-local.sh. Scope stays script-local, so no pubspec bump or index.html cache-buster is needed for a dev-script-only change. dev-up.sh and run_client_integration_web_local.sh share the same footgun and were left unfixed (follow-up). Script behaviour can be tested with scripts/test_run_realtime_multiclient_web_local.sh, which copies the script into a scratch root and stubs docker, flutter, curl and the helper scripts. It logs calls and asserts the compose project name and the env file's existence at flutter time. Verification traps: a fresh worktree needs build_runner run first, or `dart test --exclude-tags pg` fails with ~138 load errors from missing generated files. The full client `flutter test` timed out at both 45m and 60m for a shell-only change, so do not spend verifier budget on it. Use the targeted shell test plus the server non-pg run.
<!-- alloy:memory:end -->

<!-- alloy:memory-review:ptl:begin -->
- **tentura-layout-pub-workspace-packages-client-flutter-run**: applied
- **tentura-tests-always-wrap-flutter-test-dart-test**: applied
<!-- alloy:memory-review:ptl:end -->
