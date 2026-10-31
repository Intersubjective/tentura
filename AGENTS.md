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
- **Client versioning + gate:** user-visible client changes require a semver bump in `packages/client/pubspec.yaml`; when a release forces clients to update, raise `kDefaultMinClientVersion` in `packages/server/lib/env.dart` (see `.cursor/rules/versioning.mdc` and `DEV_GUIDELINES.md` § Client version gate).
- **A fix ships complete:** a coverage map of every issue item, a filled sibling matrix, one real-path test, and a 375×667 RU check for UI. An issue QA returned twice is diagnosed (root cause plus evidence) before the next fix. See `.cursor/rules/fix-completeness.mdc`.
- **No golden tests.** Golden/pixel-comparison tests are disabled project-wide — never write, update or restore them, even if a bead's acceptance criteria ask; use structural widget tests instead. See `.cursor/rules/no-golden-tests.mdc`.
- **Rooms are General-only — there are no item threads, with one named exception: Request Questions.** Code mentioning `thread_item_id` / `threadItemId` / `_canAccessThread` / item participants is dormant machinery kept on purpose (marked `DORMANT(item-threads)`); the DB guard `beacon_room_message_general_only_guard` rejects every non-General row except a Request's own **Questions** scope (internally the lobby: `coordination_item` kind 7, D1/#526). Questions access is the one server policy `questions_access_levels` (m0254) — never re-implement it, and never let a General-only feature reference a Questions message (DB guard `reject_questions_message_reference`). Never design other features, access rules or reviews around item threads. See #192 and `docs/features/beacon_questions.md`.
- **Web cache-buster must ship with every client version bump:** `packages/client/web/index.html`'s `flutter_bootstrap.js?v=<version>` query is a real, git-tracked source file (unlike `web/manifest.json`, which is deliberately `skip-worktree` and never needs committing) — it only gets rewritten to match `pubspec.yaml` when you actually run/build the app locally (`flutter run`/`flutter build web`; the `hook/build.dart` build hook does it, not `build_runner`). Before committing a version bump, run the app once and check `git status` for a resulting `web/index.html` diff, or hand-verify the `?v=` matches. A missed bump here means browsers keep serving a cached pre-fix JS bundle after a real fix ships — this has happened before (`git log -- packages/client/web/index.html` shows recurring catch-up `chore: sync web cache-buster` commits) and once made a landed bug fix look like it "didn't work."

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
reviewed: 2026-10-31
review due: 2026-11-07

### 0-evidence-real-path
Evidence rule (owner 2026-10-30, QA-bounce prevention). Every behaviour the commit message or verdict claims needs its own test that fails without the change. At least one test per bead runs the real path: the real transport response through the GQL mapper/repository to the cubit and widget (client), or a real Postgres pg test (server). Hand-built entities don't count. Touch, focus, keyboard, semantics, scroll and web lifecycle (bfcache, reload) are proven only by the web integration_test (scripts/run_client_integration_web_local.sh) or Playwright; a widget test alone is not evidence. Judge: an unbacked claim is not done, so answer retry and name the missing test, or human when the sandbox can't run the browser suite.

### alloy:operator:cancel-redispatch
alloy cancel <bead> leaves the bead ready, so a running scheduler re-dispatches it within seconds (tentura-giug 2026-10-21: cancelled 17:13:53, re-picked 17:13:58). To drop a bead's work, first bd close / add label manual (or alloy stop and wait), THEN cancel. alloy stop is graceful and waits for the in-flight run; a run whose bead was closed meanwhile is invisible to alloy cancel ('nothing to cancel') — find it with pstree -p <scheduler pid> and stop that process tree.

### alloy:operator:human-label-not-a-gate
The bead label 'human' does NOT stop the Alloy scheduler from dispatching a bead; only 'manual' (and status deferred/closed/blocked deps) do. When escalating a bead for an owner decision, add BOTH 'human' and 'manual' (2026-10-22: s7gl.100 was picked within a minute of the scheduler restart).

### alloy:operator:memory-embed-dirty-tree
Alloy's scheduled memory review (memory_reviewer + 'memory embed updated AGENTS.md') rewrites the managed block in AGENTS.md and leaves the tree dirty, so every in-place bead is refused until it is committed; it also files a 'Review N memory proposals' bead (alloy-memory-review label) whose run may start before you react. Handle by hand: commit the embed as chore(agents), apply/dismiss proposals with bd remember/forget, close the review bead, and if its run already started kill it via pstree -p <scheduler pid> (alloy cancel misses closed beads; see alloy:operator:cancel-redispatch). Never let the review run edit AGENTS.md or add tests (2026-10-21 giug, 2026-10-22 scxn).

### check-hints-analyzer-budget-toolchain
server test/architecture/analyzer_issue_budget_toolchain_integration_test.dart (tag toolchain) reports an extra 'server analyzer' issue when it runs in parallel with other suites and passes alone; it is excluded from 'scripts/run_tests.sh server-unit' (CI excludes toolchain too) and covered by 'scripts/run_tests.sh server-gates'. Do not treat its failure inside a big parallel run as a regression.

### check-hints-analyzer-crash
server architecture analyzer-budget tests (client_analyzer_issue_budget_test, analyzer_issue_budget_toolchain_integration_test): on this machine the Dart analyzer intermittently crashes ('analyzer did not complete … exit 255' / SIGBUS) under concurrent load, which shows up as a budget failure with count 1. Before treating it as a regression, rerun bash scripts/check-analyze-baseline.sh packages/<pkg> on its own. Only an explicit 'has N issues, baseline is M' line is a real overrun.

### check-hints-browser
browser-only tests (@TestOn('browser'), *_web_test.dart) need: flutter test --platform chrome <file>; VM run says 'No tests were found' (exit 79) — not a bug

### check-hints-flutter-per-test-timeout
client widget tests: 'flutter test --timeout' and dart_test.yaml do NOT apply to testWidgets (it passes the binding's defaultTestTimeout, 10 min, explicitly). A widget test awaiting a future that can't complete under fake async hangs 10 min. Fix: packages/client/test/flutter_test_config.dart sets defaultTestTimeout=2 min (PR #768; on local main once rebased/cherry-picked). Until then keep the wrapper timeout short for targeted runs (e.g. --timeout 8m) and read which test hung from the '[E] did not complete' line.

### check-hints-flutter-render-debug-vars
widget tests that set rendering debug hooks (debugOnProfilePaint, debugRepaintRainbowEnabled, debugPaintSizeEnabled …) must reset them INSIDE the test body; addTearDown is too late — the binding asserts 'The value of a rendering debug variable was changed by the test' before tear-downs. Widget-layer hooks like debugOnRebuildDirtyWidget are fine in addTearDown (tentura-s7gl.96).

### check-hints-force-directed-graphview-analyze
packages/force_directed_graphview is NOT under the analyze ratchet: bare 'dart analyze' there fails with ~290 pre-existing infos/warnings (tentura-s7gl.35 stopped on it). Gate it with its own 'flutter test' plus client tests (test/features/constellation), scripts/check-analyze-baseline.sh packages/client and check-custom-lints.sh packages/client; only analyze files you changed.

### check-hints-graphql-1000-debug
GraphQL error code 1000 'Something went wrong on the server' hides the real exception (GraphqlController catch-all sends it only to Sentry, never to the server log). To see it locally, temporarily print e/st in that catch in packages/server/lib/api/controllers/graphql_controller.dart, restart the server on :2080, re-run, then remove the print. 2026-10-21: it was a web JSON int vs Float TypeError (fixed 26c68649d).

### check-hints-hanging-red-tests
client red tests: a widget test that awaits data which never arrives must fail fast, not hang — wrap the await in .timeout(const Duration(seconds: 5)) or pump a bounded number of frames instead of pumpAndSettle on an endless stream; a single file running > 5 min is a hang, kill it and fix the test.

### check-hints-mr-suite-timeout
pg/mr: since 9eebee8d7 the D8 load test carries the tag 'load'. Run the routine full mr suite as 'dart test --tags mr --exclude-tags load -j 1' (30m wrapper). Run the load suite only on its own ('--tags load', 90m), never as a bead regression check.

### check-hints-no-chained-suites
Never propose one check that chains several suites with && (e.g. client-all && client-gates && server-...): it exceeds max_command_timeout and times out every iteration, burning max_iterations (tentura-x56h.27, 2026-10-26). Propose each ./scripts/run_tests.sh profile as its own check; passing ones are cached.

### check-hints-python-unittest-paths
Do not use 'python3 -I -m unittest scripts/test_x.py': -I drops the cwd from sys.path and unittest cannot import a path-named module (ModuleNotFoundError: scripts). Use 'python3 -m unittest scripts/test_x.py' from the repo root, or 'python3 -I -m unittest discover -s scripts -p test_x.py'.

### check-hints-sandbox-tmp-full
'No space left on device' on /tmp/dart_test.kernel.* during a bead's full-suite check = the run's private capped sandbox tmpfs filling (agent-filed 'MR verification exhausts temporary storage', tentura-khm7, was not-a-bug). Close such reports; consider raising sandbox.tmp_size if it recurs.

### check-hints-server-di-stale
server: run_client_integration_web_local.sh 'tentura-server did not come up' with di.config.dart 'Required named parameter ... must be provided' / 'Too few positional arguments' = stale gitignored packages/server/lib/app/di.config.dart, not a code bug. Fix: cd packages/server && dart run build_runner build --delete-conflicting-outputs, then rerun.

### check-hints-server-full-suite-no-j1
Full server suite: 'dart test --exclude-tags load' with default parallelism (~25 min). Do NOT add -j 1: only mr-tagged suites need serial (AGENTS.md: dart test --tags mr --exclude-tags load -j 1); -j 1 on the whole suite exceeds 90 min and times out (tentura-ev3z.4).

### check-hints-server-perf-flakes
server full 'dart test --exclude-tags load' has load-sensitive perf tests (constellation_apply_batch_budgets_pg_test fails whenever other PG sessions exist = tentura-qfsj; perf_recorder_probes 250ms wait; meritrank_suite_serialization 30s timeouts). On needs-human with only these failing, rerun them alone with -j1 and land by hand if the bead's own tests pass.

### check-hints-server-regression-split
server-regression (gates+unit+pg in one check) can exceed max_command_timeout and time out (tentura-kxyq.4, 2026-10-26): propose server-gates, server-unit and server-pg (TENTURA_PG_TESTS_REQUIRED=1) as three separate checks instead.

### check-hints-test-file-selection
When selecting server/client test files by grep for a check command, keep only *_test.dart files (e.g. grep -rl PATTERN test --include='*_test.dart' | xargs dart test ...). test/support/*.dart and *_pg_support.dart helpers have no main() and fail with 'Missing definition of main method' -- a broken check command, not a regression (tentura-f44b, 2026-10-29).

### check-hints-tmp-quota
Fixed at the source 2026-10-24 (tentura-lt6i): run_with_test_cleanup.sh now defaults TMPDIR to ~/.cache/tentura-test-tmp when unset, so full suites no longer hit the /tmp usrquota. 'Disk quota exceeded' load failures now mean something else filled the quota — check du /tmp and the cache dir.

### check-hints-transaction-inventory
server: every NEW transaction root (withMutatingUser / withTransaction / withMutatingRepeatableRead / withReadSnapshot call site in packages/server/lib) must get a line in packages/server/test/architecture/transaction_entry_inventory.txt ('path | Class.member | api | owner | reason'), else test/architecture/scoped_main_db_access_test.dart fails the non-pg regression. Check: cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test test/architecture/scoped_main_db_access_test.dart

### check-hints-web-e2e-bwrap
web e2e (scripts/run_client_integration_web_local.sh) inside the Alloy bwrap sandbox: Chrome's default sandbox aborts ('SUID sandbox helper ... not configured correctly', nosuid mounts). Run it with TENTURA_WEB_CHROME_NO_SANDBOX=1 (passes --web-browser-flag=--no-sandbox to flutter drive; landed in 91114ea94). A failure at browser start without the knob is not a code regression.

### hand-landing-run-server-gates
When landing a bead by hand that touched packages/server, rerun ./scripts/run_tests.sh server-gates on the final tree: a gate that passed in an earlier iteration of the run does not cover later edits (j9ab.3 put the analyzer 1 over budget, 2026-10-27).
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
