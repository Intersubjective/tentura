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
| Fixing an issue, QA FAIL or bug; writing its bead or brief | `.cursor/rules/fix-completeness.mdc` |
| Versioning / `MIN_CLIENT_VERSION` | `.cursor/rules/versioning.mdc` |

## Invariants (always true; most are lint-enforced)

- **Dependency direction is inward:** domain stays pure; data implements domain ports; ui → domain/data. (lints: `no_domain_to_data_or_ui_import`, `no_cubit_to_data_service_import`)
- **Repositories return domain entities**, never Ferry/Drift types. Cubits coordinating ≥2 repos inject a `*Case`. (lint: `cubit_requires_use_case_for_multi_repos`)
- **Client UI uses the design system:** no raw `Color`/`Colors.*`, `TextStyle(…)`, inline `fontSize:`, or `EdgeInsets`/`BorderRadius` from raw numbers in `features/**` / `ui/**`; use `context.tt` tokens and `TenturaText.*`. (lints: `no_inline_font_size`, `no_operational_raw_color`, `no_raw_edge_insets`, `no_raw_border_radius`)
- **Never edit generated files** (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.schema.dart`); run codegen instead.
- **Search ladder:** known path → Read; semantic → Serena MCP; then Grep/Glob.
- **Terminology alias:** user-facing **Request** / **discussion** (workspace), **Activity** / «Активность» (home nav branch; `Activity (internally: inbox)` in docs), **thread** / **Discussion** «Обсуждение» (one conversation; the built-in thread, internally General — never General / «Общее» in user-facing copy); internal **Beacon** (`Request (internally: Beacon)` in docs). Never introduce a `Request` domain entity. See `.cursor/rules/terminology.mdc` and `bash scripts/check-user-facing-terminology.sh`.
- **Client versioning + gate:** user-visible client changes require a semver bump in `packages/client/pubspec.yaml`; when a release forces clients to update, raise `kDefaultMinClientVersion` in `packages/server/lib/env.dart` (see `.cursor/rules/versioning.mdc` and `DEV_GUIDELINES.md` § Client version gate). **Cloud-agent / PR-author branches leave the version lines untouched** — the lander bumps once at merge (avoids rebase conflicts).
- **A fix ships complete:** a coverage map of every issue item, a filled sibling matrix, one real-path test, and a 375×667 RU check for UI. An issue QA returned twice is diagnosed (root cause plus evidence) before the next fix. See `.cursor/rules/fix-completeness.mdc`.
- **No golden tests.** Golden/pixel-comparison tests are disabled project-wide — never write, update or restore them, even if a bead's acceptance criteria ask; use structural widget tests instead. See `.cursor/rules/no-golden-tests.mdc`.
- **Rooms are General-only — there are no item threads, with one named exception: Request Questions.** Code mentioning `thread_item_id` / `threadItemId` / `_canAccessThread` / item participants is dormant machinery kept on purpose (marked `DORMANT(item-threads)`); the DB guard `beacon_room_message_general_only_guard` rejects every non-General row except a Request's own **Questions** scope (internally the lobby: `coordination_item` kind 7, D1/#526). Questions access is the one server policy `questions_access_levels` (m0254) — never re-implement it, and never let a General-only feature reference a Questions message (DB guard `reject_questions_message_reference`). Never design other features, access rules or reviews around item threads. See #192 and `docs/features/beacon_questions.md`.
- **Web cache-buster is assigned at build time:** committed `packages/client/web/index.html` keeps `flutter_bootstrap.js?v=0.0.0-dev`; `pubspec.yaml` is the release version source. After `flutter build web`, run the post-build tools in pipeline order; `tool/generate_wasm_preload_artifacts.dart` stamps the resolved version (plus `WEB_BUILD_ID` when set) into `build/web` entry points. Verify with `dart run tool/verify_web_version_consistency.dart build/web`. See `.cursor/rules/versioning.mdc`.
- **Upgrading Flutter re-opens #808:** the web build forces single-threaded skwasm (`kForceSingleThreadedSkwasm`, `packages/client/hook/build/versioned_web_assets.dart`) to dodge an upstream FreeType race on 3.47.0. After any Flutter version change, run `bash scripts/check_skwasm_single_thread.sh` and follow the comment on that constant to re-test multi-threaded skwasm.
- **Upgrading Flutter re-checks #746:** `Dockerfile.builder` patches Flutter 3.47.0 with the unmerged upstream fix flutter/flutter#192724 (flutter/flutter#195316, null check in `flushSemantics`). After any Flutter version change, run `bash scripts/check_flutter_semantics_patch.sh` and follow `scripts/flutter_patches/README.md` (drop the patch once Flutter has the fix).

## Product docs

Orientation and feature specs live under [`docs/`](docs/) — start at [`docs/README.md`](docs/README.md). High-signal: [`docs/Tentura_current_status_quo.md`](docs/Tentura_current_status_quo.md), [`docs/features/beacon_room.md`](docs/features/beacon_room.md).

## Verify

Local/agent test runs **must** go through `scripts/run_with_test_cleanup.sh`.
It time-bounds the command, SIGKILLs hung descendants, and deletes
unreferenced `/tmp/flutter_tools.*` + `/tmp/dart_test.kernel.*` (those live
on a RAM tmpfs). CI does **not** use it (ephemeral runners). Do not wrap
`flutter run` or `scripts/run_client_integration_web_local.sh`.
Inside the Alloy bwrap sandbox (nosuid mounts) Chrome's setuid sandbox aborts;
run the web e2e runner with `TENTURA_WEB_CHROME_NO_SANDBOX=1` to pass
`--web-browser-flag=--no-sandbox` to `flutter drive` (off by default).

**Preferred: `scripts/run_tests.sh <profile>`** — memory-aware `-j`, tag runs
that load only the tagged files, and the right timeout, all through the
wrapper. Profiles: `server-files <files>`, `server-affected`, `server-unit`,
`server-pg`, `server-mr`, `server-gates`, `server-regression`,
`client-files <paths>`, `client-affected`, `client-all`, `client-gates`.
Iterate with `*-files` / `*-affected`; run `server-regression` (or
`client-gates` + `client-all`) once before landing; never `perf` / `load` in a
routine run. Wrapped runs queue machine-wide (one at a time). Policy and
measurements: [`docs/testing-resource-profile.md`](docs/testing-resource-profile.md).

**Agents: run anything that may take over ~15 min detached, then poll it in
bounded waits.** Whole profiles count (`client-all`, `server-pg`,
`server-regression`), and so does any run that may sit in the queue. Your
prompt cache expires while you block inside one long command. Every return from
a bounded wait is a new turn, and that turn keeps the cache warm:

```bash
id=$(scripts/test_job.sh start -- scripts/run_tests.sh client-all)
scripts/test_job.sh wait "$id"   # ≤20 min; exit 3 = still running → call wait again
```

When the run ends, `wait` exits with the run's exit code and prints the log
tail. A job nobody waits on for 45 min is killed as abandoned. Self-check:
`bash scripts/test_job_selftest.sh`.

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
# Wrapped runs put their disposable databases in the RAM-backed
# `postgres-test` container (127.0.0.1:5433, `docker compose up -d
# postgres-test`) whenever it is up and the caller set no POSTGRES_HOST/
# PORT/DBNAME; TENTURA_TEST_PG=shared keeps them in `postgres` (SSD).
# Postgres tests run in two steps. The `mr` ones also reach the MeritRank
# service, which is a single shared container every disposable database talks
# to, so they must not run in parallel with each other. The D8 load suite
# (`load` tag) runs a 1,000-session publication burst that outlasts the
# wrapper timeout, so the routine `mr` run excludes it; run it on its own.
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- \
  dart test --tags pg --exclude-tags mr
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- \
  dart test --tags mr --exclude-tags load -j 1
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 90m -- \
  dart test --tags load -j 1
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
> **Wrapped runs queue machine-wide** (`flock` on `~/.cache/tentura-tests.lock`):
> overlapping suites used to sweep each other's kernels (every file then fails
> to load with an empty "Failed to load") and oversubscribe RAM. A second run
> logs `queued behind another test run` and waits; do not bypass it with
> `--no-lock` unless the run is alone.
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

CI (`.github/workflows/pipeline.yml`) runs on every push to `main`, but only what the push can
affect (`scripts/ci_changes.py`, diffed against the last green run): a package's analyzer
gate (`scripts/check-analysis.sh` — both gates from one analyzer pass), tests and build run
when it changed; its tests tagged `repo-files` (they read docs, scripts, workflows or the
other package — `scripts/check_repo_files_tags.py` enforces the tag) also run when anything
outside it changed. Agent docs (`AGENTS.md`, `.cursor/`, `.claude/`) reach only the lint
shard. Client and server (non-pg) tests run as a few bundled entrypoints
(`scripts/gen_test_bundles.py`, CI only — a file that leaks process-wide state goes in
`test/bundle_exclude.txt`); client tests run on three shards and pg tests on six, packed by
measured per-file duration (`scripts/ci_select_tests.py --balance`, weights in
`scripts/ci_test_durations.json` — refresh with `scripts/ci_test_durations.py update --run <id>`
when shards drift apart; a stale file only costs balance). Manual
dispatch runs everything. Pull requests into `main` get the same selection minus the web
build, server image, deploy and pg shards — add the `ci:full` label for the pg shards and
every package's full suite — and must pass the required `PR checks` status to merge.

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
reviewed: 2026-11-07
review due: 2026-11-14

### 0-evidence-real-path
Evidence rule (owner 2026-10-30, QA-bounce prevention). Every behaviour the commit message or verdict claims needs its own test that fails without the change. At least one test per bead runs the real path: the real transport response through the GQL mapper/repository to the cubit and widget (client), or a real Postgres pg test (server). Hand-built entities don't count. Touch, focus, keyboard, semantics, scroll and web lifecycle (bfcache, reload) are proven only by the web integration_test (scripts/run_client_integration_web_local.sh) or Playwright; a widget test alone is not evidence. Judge: an unbacked claim is not done, so answer retry and name the missing test, or human when the sandbox can't run the browser suite.

### alloy:lesson:cascade_batch_barriers_before_generation_lock
Cascade block batches must acquire all required per-user block barriers in sorted order before the first INSERT. Each INSERT's trigger locks visibility_trust_generation; acquiring another barrier afterward can deadlock with Post forwarding holding that barrier shared while waiting for the generation row. Preserve #941 ordering: hierarchy → per-user barrier → per-Post lock. Prove the fix with a deterministic two-session PostgreSQL test that reproduces SQLSTATE 40P01 when only the fix is removed, then passes with it; retain the existing lock-order tests.

### alloy:lesson:deploy_hosts_no_rsync
deploy.sh and anything run on the dev/prod VPS (Debian base) must use only coreutils/findutils/tar/cp/mv/find. The hosts have no rsync (verified on dev.tentura.io with `command -v rsync`). Under `set -euo pipefail` a missing rsync aborts the deploy mid-publication, after app-assets are moved and before the entry files are published (tentura-g71a.9). The judge and tests passed because the CI sandbox has rsync, so green checks do not prove host compatibility. Make scripts/test_deploy_web_asset_publication.sh run deploy.sh with a PATH that lacks rsync (or a shim that exits 127) in both dev and prod modes. Web publish order: new app-assets/<ver>/ first, then prune stale root files (excluding app-assets/ and the entry files, compared against the staged tree), then entry files last, then prune_app_assets (keep the newest APP_ASSETS_KEEP). Never edit the live ./web in place from the archive; stage it first. The deploy action now scp's the repo Caddyfile, so a deploy also brings new routes to the host. Check landing fonts, /invite, sign-in and push-action in the post-deploy QA smoke. Web assets such as the Drift worker and sqlite3.wasm must be resolved through ui_web.assetManager, never through root literals or getWebAppVersion(), which reads the latest root version.json and not the running build's.

### alloy:lesson:field_flag_inaccessible_placeholder_nullable_and_perf_record
Adding a per-item flag (e.g. has_unread) to the Field read (tentura-xdle.1): (1) Landing regressions came from pin/access placeholder rows, which the viewer cannot read. The flag must be NULL there (nullable in server custom_types and in client schema.graphql). Also gate any Questions authorization by "scope exists", or placeholder/no-scope rows throw. Run constellation_anchor_tombstone_pg_test and constellation_pin_blocks_and_access_placeholders_pg_test early, because they only show up in server-affected. (2) Reuse the Request-card SQL (request_unread_message_count / post_unread_sql / room_unread_sql) instead of writing a third copy of the unread rule. The pg test asserts the SQL statement count with test/support/query_counter.dart. (3) For the "no slower than 10%" acceptance, the judge rejected the first attempt until the before/after numbers were recorded. Record them in the bead notes (docs/plans/issue-235-...measurements.md) and commit the raw reports docs/measurements/field-unread-{parent,current}.json. The parent is measured from a detached git worktree of HEAD (never a /tmp copy of the checkout), on tentura_perfsynth with 20 warmups and 200 samples, using tool/field_unread_read_benchmark.dart. Measure both FULL and Requests-refresh. Result here: FULL +6.4%, statement count unchanged. In-place bead: no pubspec or index.html bump. The 5-check verifier budget ran out on green evidence and was accepted.

### alloy:lesson:new_graphql_query_field_checklist_and_reader_inventory
Refinement from tentura-l9k5.4 (personFieldItems, sibling of fieldSearch). Iteration 2 was again spent only on the missing transaction_entry_inventory.txt line for the new reader method (FieldSearchReader.readPersonItems, withReadSnapshot). The earlier lesson already said to add it up front. When adding a second method to an existing reader, add its inventory line in iteration 1 too. A new reader method needs a new line even when the class already has one. Per-bucket counts, the cursor page and the readability filter belong in one withReadSnapshot so they agree. Cursor shape: base64Url(json [activityAt ISO, id]), decoded and validated in the resolver (empty or over-long id and unparseable dates throw ArgumentError). Keep the bucket as a String arg mapped to an enum with a throwing default. Mirror the new types and the query_root field in client schema.graphql. Do not bump the client version in in-place beads.

### alloy:lesson:publish_split_pending_marker_and_precheck
Post publish split (tentura-qw5q, #941): tx1 (lockForPostMutation: policy, publishDraft, lifetime) commits status; tx2 (lockForPostDelivery, no hierarchy lock) does forward, createMessage, setPostRootMessage. 'Open with null post_root_message_id' is the durable delivery-pending marker; no pending table. Retries (_postForPublication returns the entity; _publishedResult only when open and root set) skip tx1 and run tx2 with the retry's own recipients. Because tx1 commits before the forward, refusals that used to roll back the whole publish (recipient not mutually visible, blocked, forward policy) must be pre-checked inside tx1 without writing. ForwardCase.checkPostForward does that and the forward repeats the checks under the Post lock. Two server-pg tests (post_case_publish_pg_test 'fails the whole call when a recipient is not mutually visible', post_case_publish_without_...) only failed in the full server-pg run, not in the targeted new test, so run full server-pg after any transaction-boundary change. The old single-commit unit test fixture (attachment_transaction_boundary) must be reshaped into status/delivery commit phases rather than weakened. The concurrency pg test pauses the fan-out with a test-only AFTER INSERT trigger on beacon_participant in a disposable DB, uses one single-connection TenturaDb per actor, and scopes pg_locks queries by key, pid and current database oid (see pg_test_migration_lock_contention). Test seams go through a PostLockPort wrapper (publishLock param on PostPublishHarness.build), not a parallel pipeline. In-place bead: no pubspec/index.html bump.

### alloy:lesson:realtime_hint_drops_check_sql_trigger_and_open_sheet
When a live push (realtime hint) never reaches other open clients, trace all three hops before touching the client cubit. (1) The Postgres trigger function notify_entity_change: in tentura-3tqd.3 a single CASE expression made the room_poll/room_seen hint fail on every call, so nothing was sent. Fix it with a NEW migration (m0281), never by editing a shipped one. (2) Fan-out scope: the Request author has no participant row, so recipients must be added deliberately (author plus every admitted member, never outsiders). (3) The client: a modal sheet sits under the root navigator, outside the room's providers, so it will not follow cubit updates. Wrap it in BlocBuilder(bloc: cubit) and pass RoomState into the row builders, not the cubit. Test evidence that worked: a pg test with a pg_notification recorder that asserts recipients, and a wire-harness client test where the socket frame goes through the real GraphQL mapping. Verify the baselines go red on a clean HEAD, using git worktree add --detach with a trap (a check does this). For the full server pg regression run only `scripts/run_tests.sh server-pg`. Never run a bare `dart test --tags pg`, which grew an 18 GB kernel dir on the RAM tmp and was killed. Name the specific pg files for targeted checks. Do not touch pubspec.yaml or web/index.html in in-place feature beads; the manager bumps once at push.

### bead-authoring-no-commit-line
When filing beads for Alloy, never write 'Commit: fix(...): ...' in the description: sandboxed agents read it as an order, try to git commit, hit a read-only .git and park the bead as needs-human (j9ab.2, 2026-10-27). Alloy makes the commit itself.

### ci-pg-job-two-step-selection
CI test-pg job (.github/workflows/pipeline.yml) runs TWO commands: (1) TENTURA_TEST_PG_POOL_SIZE=1 dart test --tags pg --exclude-tags mr,multi-connection, then (2) dart test --tags multi-connection --exclude-tags mr -j 1. test-server runs dart test --exclude-tags pg. So: any test that needs Postgres (even a meta test that spawns a pg test) MUST carry the pg tag or test-server fails; tests that size their own pool carry multi-connection and run serially (-j 1: they assert admission latency/RSS and interfere in parallel). Before pushing, run both pg commands locally, not just the changed files (a first CI run of ev3z.27 failed on exactly this). Use absolute path to scripts/run_with_test_cleanup.sh when a script cd's into packages/server.
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
