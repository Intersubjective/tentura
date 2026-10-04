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
reviewed: 2026-10-04
review due: 2026-10-11

### alloy:lesson:bead_cites_renamed_test_file_check_git_log_and_fix_docs
Bead acceptance criteria and plan docs (e.g. docs/plans/post-implementation-steps.md) can name test files that were renamed/removed on main (a1707d683 renamed drift_create_all_migrated_pg_test.dart to drift_images_create_table_on_migrated_pg_test.dart). When a required check fails with "file not found/failed to load" for a cited test, run `ls`/`git log --diff-filter=R` for the current name before touching code; then fix the stale reference in the plan doc and report the bead criteria as stale (human updates acceptance). Related: new migrations (m0209) make sibling pg tests fail with "column beacon.kind does not exist" against a stale cached/template DB until migrated — rerun serially before editing code. A broad regression run failing on one pg test right after adding a migration is usually this, not a regression. Also: hard-coded latest-migration literals in tests (m0199 'registry reaches 0208') should use migrationsForTesting.last.version.

### alloy:lesson:client_custom_lint_use_tentura_top_bar_for_new_screens
New client screens (e.g. PostViewScreen in tentura-brd4.34 / C2a) must use the design-system top bar, not a plain Material `AppBar`. A plain AppBar trips the `use_tentura_top_bar` custom lint and raises the client count in scripts/custom-lint-baseline.txt (26 to 27), so the required `check-custom-lints.sh packages/client` check fails. That cost one repair attempt. Use the Tentura top bar widget from the start and run the custom lints early. Other C2a facts: BeaconKindRepository (@lazySingleton) caches beacon.kind per id. The host route resolves the kind through a FutureBuilder and shows a loading Scaffold meanwhile. Request keeps its providers, and Post gets PostViewCubit, ThreadsCubit and ThreadHostCubit(capabilities: RoomCapabilities.post()). The new GraphQL document needs build_runner output under post_view/data/gql/_g/, and `git diff --exit-code` on it should be clean. The Post route test uses a fake whose Request-only methods throw. Also run test/features/beacon_view/, which the acceptance criteria name. The full client suite (about 4400 tests, about 6 minutes) passed.

### alloy:lesson:codegen_freshness_check_content_not_mtime
Never assert generated-code freshness by comparing file mtimes (File.lastModifiedSync): build_runner skips rewriting outputs whose content is unchanged ("same"/"wrote 0 outputs") and git checkouts don't preserve mtimes, so the check false-fails after any unrelated schema.graphql edit and is random on fresh clones. Use a content-based check instead. In tentura-sae, packages/client/test/support/gql_codegen_freshness.dart (findStaleGqlCodegen) parses each .graphql document and schema.graphql with package:gql and compares operation, variable and field names plus root-field arguments against the generated *.ast/.data/.req/.var.gql.dart, and requires all four outputs to exist. It returns problem strings, so it is testable with temp-dir fixtures. Pin both directions in a dedicated test (correct output accepted whatever the mtimes; mismatched output rejected even with fresh mtimes), plus a source-grep guard that the consumer test no longer calls lastModifiedSync. Test-only change, so no pubspec bump. Full client flutter test (about 12 min) is the regression check.

### alloy:lesson:new_v2_mutation_must_not_resolve_di_in_constructor
A new V2 GraphQL mutation class (e.g. MutationPost in packages/server/lib/api/controllers/graphql/mutation/) must not call GetIt.I<UseCase>() in its constructor or field initializers. `mutationsAll` is evaluated in non-DI tests such as mutation_beacon_people_test ("mutationsAll contains MarkBeaconPeopleSeen"), so an eager lookup fails there with "not registered". Take an optional injected use case in the constructor and resolve it lazily in a getter (`_injected ?? GetIt.I<X>()`). Related gotchas from tentura-brd4.13: (1) Upload args via InputFieldUpload.fieldNullable arrive as null when unset, so the Upload input type and optional list/string args need null-tolerant validate/deserialize overrides. (2) A new custom GraphQL result type must be registered in custom_types.dart. (3) Adding a ctor dependency or port method to BeaconRoomCase or BeaconRepositoryPort means regenerating the *.mocks.dart files with build_runner and updating the repository mock. (4) In pg tests that use real dispatch, recipients must be mutually visible, or the "not mutually visible" case fails on setup rather than on the code under test.

### alloy:lesson:pg_notify_test_clear_race_use_drain_barrier
Realtime pg tests that LISTEN on entity_changes and call `notifications.clear()` after seeding are racy: NOTIFY messages from seed writes can arrive after the clear and contaminate later assertions (full serial suite fails, single-file run passes; tentura-7tlr, also seen in tentura-brd4.10). Fix in the test harness, not production: use packages/server/test/support/pg_notification_recorder.dart. PgNotificationRecorder wraps the channel stream; `drain(sendBarrier:)` sends a unique `{entity:'barrier', id:token}` pg_notify on the writer connection and waits (10s timeout) until the barrier is observed on the listener, then clears messages. Replace every `notifications.clear()` with drain, including in tearDown. Cover it with a pure unit test using a StreamController, plus a pg test that fires a burst of 50 notifies and drains. When the broad regression check fails only on test/min_client_version_gate_test.dart (U18c, kDefaultMinClientVersion 7.27.0 vs client 7.25.0, tracked as tentura-4io7), that is out of scope for a test-flake bead; cite it rather than fixing it. The deleted tentura_5gq architecture test is not a gate (removed in a1707d683).

### alloy:lesson:pg_test_slow_setup_belongs_in_setupall_and_cross_process_lock_dir_fixed_path
In the tentura-j0q landing bead (trial merge tentura-acz), the full wrapped pg suite (`dart test --tags pg --exclude-tags mr`) was flaky for two real reasons.

1. Pg tests that did recreate/migrate/seed and drop/close inside the timed test body (30s) timed out under load. This hit review_obligation_backfill_pg_test.dart and settlement_kind_constraint_pg_test.dart. Move that work into setUpAll and tearDownAll, and keep only the assertions in the test body.

2. IsolatedHasuraSession's cross-process port-claim lock dir must not derive from Directory.systemTemp. Nested landing runs set a private TMPDIR, so they get a separate lock namespace and the Hasura port race (18080–18280) comes back. Use a fixed shared path (`/tmp/tentura_hasura_ports`, with systemTemp only on Windows).

Bookkeeping added on top as a lock-in, after the real fixes:
- a tentura_<bead>_landing_check_test.dart plus a pg acceptance probe;
- the AGENTS.md HTML marker;
- the agents_alloy_memory_olc_landing_tail.txt fixture;
- a new path list in the fx7 landing test.

Checks:
- Run the literal acceptance command first, and run wrapped suites serially.
- If a wrapped run passes but exits non-zero, check for a full /tmp before editing code.
- Nested landing tests must skip themselves when TENTURA_U6E_NESTED_SUITE, CI or TEST_TARGET=server is set.

### alloy:lesson:realtime_kind_requires_contract_manifest_entry
Adding a new RealtimeEntityKind (wire kind) in packages/client also requires a matching entry in docs/contracts/realtime-entity-contract.json (wireKind, acceptedWireKinds, clientKind, genericTriggerArgs, specializedPublishers, impacts, tests). Otherwise test/architecture/realtime_entity_contract_test.dart fails; attempt #1 of tentura-gfz failed on exactly this. Run that contract test as part of targeted checks for any realtime vocabulary change. Also update all touch points: the enum wire mapping, the InvalidationService payload parse (drop the frame if extras are invalid), the dedup key, and BeaconRoomInvalidation (enum, fromRealtimeChange arm, ==/hashCode).

### alloy:lesson:worktree_dev_scripts_pin_compose_project_and_sync_env
Tentura local dev scripts run from an Alloy worktree hit two footguns. (1) compose.dev.yaml uses fixed container_name values, so bare `docker compose up -d` in a worktree creates a project named after the checkout dir and fails with 'container name /minio is already in use'. Fix: `COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-tentura}" docker compose up -d` (respect a caller override; the script already skips compose when :8080/healthz is healthy). (2) packages/client/env/local-web.env is gitignored and absent in fresh worktrees. Run `scripts/sync-client-local-config.sh` and then `scripts/resolve_local_web_config.sh --check-only` before `flutter run`, mirroring run-flutter-web-local.sh. Scope stays script-local, so no pubspec bump or index.html cache-buster is needed for a dev-script-only change. dev-up.sh and run_client_integration_web_local.sh share the same footgun and were left unfixed (follow-up). Script behaviour can be tested with scripts/test_run_realtime_multiclient_web_local.sh, which copies the script into a scratch root and stubs docker, flutter, curl and the helper scripts. It logs calls and asserts the compose project name and the env file's existence at flutter time. Verification traps: a fresh worktree needs build_runner run first, or `dart test --exclude-tags pg` fails with ~138 load errors from missing generated files. The full client `flutter test` timed out at both 45m and 60m for a shell-only change, so do not spend verifier budget on it. Use the targeted shell test plus the server non-pg run.
### alloy:lesson:check-hints-plain-name-quoting
Quote `flutter test --plain-name` values containing spaces, for example `--plain-name='wire mapping of Post fields'`. Otherwise the shell passes extra words as separate arguments and Flutter may treat them as nonexistent test paths. Keep local test runs wrapped with `scripts/run_with_test_cleanup.sh`.
<!-- alloy:memory:end -->

<!-- alloy:memory-review:ptl:begin -->
- **tentura-layout-pub-workspace-packages-client-flutter-run**: applied
- **tentura-tests-always-wrap-flutter-test-dart-test**: applied
<!-- alloy:memory-review:ptl:end -->

<!-- alloy:memory-review:xcct:begin -->
- **check-hints-dead-landing-gate-tests**: dismissed. The named landing-check files and the two named companion tests are absent from the current checkout. The proposed permanent exclusion is obsolete; retain the existing verification requirements.
- **check-hints-mr-suite-drift**: dismissed. The cited test files exist, but their presence does not establish the claimed current failures or their cause. A historical failure count does not justify indefinitely excluding the full MR suite. Retain the existing serial MR verification requirement and evaluate failures from actual check output.
- **check-hints-plain-name-quoting**: applied. Shell quoting preserves a test name containing spaces as one argument; the durable instruction is recorded above.
<!-- alloy:memory-review:xcct:end -->
