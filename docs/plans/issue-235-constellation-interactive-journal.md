# Issue #235 — Interactive constellation: execution journal

Plan: [`issue-235-constellation-interactive-implementation-plan.md`](issue-235-constellation-interactive-implementation-plan.md).
Architecture: [`issue-235-constellation-interactive-architecture.md`](issue-235-constellation-interactive-architecture.md) (rev 9).

Each unit appends `## UNIT Uxx — complete|partial|blocked — <ISO date>`.

## Baseline

Recorded 2026-10-07 on `main` before any #235 change. All runs wrapped in `scripts/run_with_test_cleanup.sh`, serial.

| Suite | Command (from package dir) | Result |
|---|---|---|
| CT: client constellation + graph | `flutter test test/features/constellation test/features/graph -j 1` (`packages/client`) | 714 passed, 0 failed |
| PT: `force_directed_graphview` | `flutter test` (`packages/force_directed_graphview`) | 122 passed, 0 failed |
| ST: server constellation (non-pg) | `dart test -x pg test/api/controllers/graphql/constellation_anchor_test.dart test/domain/constellation test/domain/entity/constellation_anchor_domain_test.dart test/domain/use_case/constellation_field_case_test.dart test/data/repository/constellation_request_row_timestamptz_test.dart -j 1` (`packages/server`) | 75 passed, 0 failed |

### Custom lints (`scripts/check-custom-lints.sh`)

| Package | Total | Baseline file | Breakdown |
|---|---|---|---|
| `packages/client` | 24 | 24 | `no_raw_edge_insets` 17, `no_raw_border_radius` 7 |
| `packages/server` | 0 | 0 | — |

pg tests (`-x pg`) are excluded locally; benchmark numbers for N = 100/300/600 are added by U01.

## UNIT U00 — complete — 2026-10-07

Created this journal with the baseline above and linked the three #235 docs from `docs/README.md`. No code changes.

## UNIT U01 — partial (part 1/2: fixture and benchmark) — 2026-10-07

Added `test/features/constellation/fixtures/synthetic_field.dart` (`syntheticConstellationField(size:, seed:)`: N people + N requests, tier-1/2 trust edges, ~10% anchored people and requests, fixed default seed) and the `bench`-tagged `test/features/constellation/bench/constellation_field_bench_test.dart`, which writes `packages/client/build/bench/constellation_field_baseline.json` (gitignored). Run with `flutter test --tags bench <file>` (exclude from broad runs with `-x bench`). Timeline spans, long-task detector and perf HUD are part 2.

### Baseline (I4 reference)

`flutter test` VM, headless widget binding, 1200×800 surface, 30 drag frames pumped at 16 ms; numbers are wall-clock on the dev machine (not profile web), so use them as a relative reference only.

| N | compose ms | layout ms | drag frame ms (avg) |
|---|---|---|---|
| 100 | 13.6 | 34.6 | 19.9 |
| 300 | 2.5 | 99.7 | 25.7 |
| 600 | 3.7 | 162.0 | 31.8 |

(N=100 compose includes JIT warm-up.)

## UNIT U45 — partial (part 1/2: measured cold cost and call budget) — 2026-10-07

Measured on MeritRank 0.12.0 + `postgres-tentura` v0.9.1 (local compose), database `tentura_perfsynth` (V≈1000, 89 065 MR edges). Procedure: `SELECT mr_reset(); SELECT meritrank_init();` (empty peer cache), then one `mr_mutual_scores(viewer, '')` per viewer, timed inside a `DO` block; every call was a single RPC attempt (`mr_rpc_attempts()` delta 1). Each viewer's second (warm) call is listed for reference.

| Viewer | Rows | Cold first read | Warm repeat |
|---|---|---|---|
| `Uf00000001729` | 985 | 525.9 ms | 23.3 ms |
| `Uf00000000100` | 1005 | 514.9 ms | 13.9 ms |
| `Uf00000000336` | 1026 | 31.1 ms | 1.6 ms |
| `Uf00000002384` | 988 | 489.7 ms | 20.5 ms |
| `Uf00000001446` | 991 | 24.4 ms | 2.5 ms |
| `Uf00000002488` | 985 | 12.4 ms | 2.1 ms |

Worst cold first read: 0.53 s (peers missing from the cache are sampled on demand).

For reference, on 0.11.x the same read cost 5–7 s when the walk cache was below the working set.

Chosen: `MERITRANK_RECV_TIMEOUT_MSEC=10000` (a 10 s whole-call budget, roughly 19 times the worst measurement above and above the old dense 7 s cost), identical in `compose.dev.yaml`, `compose.prod.yaml` and the CI `pipeline.yml`. It replaces 60000, which let a silent peer hold a worker's DB connection for about a minute. Part 2 (`statement_timeout`, degraded-vs-empty visibility, blackhole test) is not done here.

## UNIT U04 — complete — 2026-10-07

Added pure `ClockPort`, `OpIdPort` and `WakeUpPort`/`WakeUpHandle` (`lib/domain/port/`) with dev/prod adapters in `lib/data/service/` (`DateTime.now`, UUID v4, one-shot cancellable `Timer`) and Mockito test bindings (`lib/data/service/mock/infrastructure_port_mocks.dart`), plus `ConstellationAccountPort` and `features/auth/domain/constellation_account_adapter.dart` (delegates to `AuthCase.currentAccountChanges`, like `AttentionAccountAdapter`, all environments). Deterministic `FakeClockPort` / `FakeWakeUpPort` live in `test/support/`. Codegen via `build_runner`.

**Acceptance adaptation (DI smoke).** The full `Environment.test` GetIt container has never been initialisable in a plain `flutter test` (no test did it before): eager singletons such as `AuthCase` are registered before their `order: 1` test mocks, and the drift database needs a native path_provider plugin. Making it loadable would mean changing registration kinds/order of unrelated features (FCM, closure, beacon write/image, app update, home, database), which an earlier attempt did and which is out of scope; those edits were reverted. Instead `test/app/di/constellation_infrastructure_ports_di_test.dart` follows the `forward_candidate_context_di_test.dart` precedent: it asserts on the generated `di_current.config.dart` that each infrastructure port gets its mock for `{_test}` and its real adapter for `{_dev, _prod}`, and that `ConstellationAccountPort` → `ConstellationAccountAdapter(AuthCase)` and `AuthCase` are registered without an environment restriction.

## UNIT U09 — partial — 2026-10-07

Part 1/2 adds `ConstellationFieldStoreCase` and `ConstellationFieldStoreState` alongside the existing cases, without moving callers. The read store follows the account port independently of leases, combines lease/browser visibility, coalesces refreshes with the existing debounce/spacing policy, performs one catch-up FULL, and merges FULL read order independently of anchor revision. `ConstellationProjectionParams` is a Freezed value for context and normalized membership filters (both switches are non-null booleans with default-off values). A separate params-binding generation advances on rebinding; FULL single-flight selection and FULL/ANCHORS response adoption use it, so the original A response remains obsolete after A → B → A. Account generation still changes only on account replacement or logout.

Added gated regressions for FULL and ANCHORS across both filter and context A → B → A transitions, asserting obsolete responses produce no emit; also checked equivalent params do not refresh or emit. Before the fix, the two filter regressions failed on emit counts (18 existing tests passed). The FULL regression keeps the new response pending while the obsolete response completes, independently exercising the binding guard rather than FULL read-sequence ordering.

Verification is in progress. All runs are serial through `scripts/run_with_test_cleanup.sh`. The sandbox makes the installed Flutter SDK read-only and denies loopback sockets, so ordinary `flutter test` cannot reach assertions; native Flutter tester plus `test_core`'s direct runner executes the unchanged test declarations/assertions with ENV=test and the test env file. Freezed output is generated by the cached build-runner executable because `dart run` attempts an unavailable pub.dev advisory lookup. No generated files are hand-edited.

Part 2 retains caller migration, removal of `ConstellationFieldCase`, single composition and preflight wiring. The current GraphQL protocol pins context server-side; this change binds context locally without changing the wire API. No user-visible client change or release version bump is required. Git/task tracking and the whole-client suite remain with Alloy.

## UNIT U09 — complete (part 2/2) — 2026-10-08

The client `ConstellationFieldCase` is deleted. `ConstellationFieldStoreCase` (now an injectable singleton) owns the read side: the cubit holds a `StoreLease`, forwards screen visibility to it, sets membership filters on it, and composes **once** per applied store snapshot (`_applyLoadedField`, keyed on snapshot identity) through an injected `ConstellationPresentationComposer`. The FULL read no longer composes. The read half of `ConstellationAnchorCase` (realtime/catch-up subscriptions, `refreshAnchors`, `syncMembershipFilters`, `refreshSignals`) moved to the store. Its write half and confirmed cache stay until U21. `preflightRequestAction` reads `store.current` and issues no FULL.

**Hang root cause (the 45/90-minute acceptance timeouts).** `ConstellationCubit.close()` awaited `_storeSub.cancel()`. A broadcast subscription with no `onCancel` returns the shared root-zone null future, so the rest of `close()` resumed outside the caller's zone. Inside `testWidgets` (fake async) the state controller's done event then sat in a FakeAsync microtask queue that nothing flushed, so `await cubit.close()` in a widget-test body never returned. The bench test and `constellation_app_bar_test.dart` both did this, each hanging until the wrapper timeout. Production was never affected: a real zone has no unflushed queue. Fix: the cancel is not awaited, since there is no cleanup to wait for.

**Behaviour fix.** On a reconnect catch-up, the anchor case used to issue its ANCHORS read at once. The store debounced it like any realtime hint (220 ms, plus 2 s spacing), so after reconnect `syncPending` stayed set for up to 2 s (`constellation_anchor_cubit_test` "offline recovery…"). A catch-up now dispatches its one FULL immediately. If a read is already in flight it queues one more, because that read may have missed the gap.

**Tests.** The migrated tests keep every assertion; a normalized `expect` diff per file shows only formatting changes, except in `constellation_anchor_case_test.dart`, whose read tests moved onto the store. That file's direct confirmed-cache tests (equal-revision refresh, older-revision discard, stale FULL `adoptConfirmedProjection`, account switch accepting a lower revision) are restored next to the store versions, because that cache is still live. `constellation_post_webs_test` "realtime coalesces…" relied on the removed `realtimeRefreshMinInterval: Duration.zero`; it now drives the store's fixed 2 s spacing with `FakeClockPort`/`FakeWakeUpPort`. `constellation_realtime_refresh_test` passes its fake-async clock to the store. The store fixture calls the cubit constructor directly (it used `Function.apply`). Gate-style checks (file absent, no legacy name) were dropped. The durable invariants (no use case composes; UI composes only through the injected composer) are kept as `test/architecture/constellation_composition_ownership_test.dart`.

**Verification** (serial, wrapped): `test/features/constellation` 561 passed, 1 skipped (pre-existing VM-service skip), 1m37s; `test/features/graph` + `test/architecture` + `test/features/post_view` 365 passed; `check-analyze-baseline` client 2085 (baseline lowered from 2098); custom lints 24 (baseline 24); full client suite 5155 passed, 2 skipped in 4m18s (its one failure was the architecture test file renamed mid-run, which then passed on its own).


## UNIT U28 — partial — 2026-10-08

Part 1/2 (`tentura-s7gl.29`): graph-package `pauseTransitions()` preserves displayed geometry and unfinished destinations; `resumeTransitions()` restarts from that geometry without counting paused time. Accepted layouts whose publication was drained while frozen retain their destinations until resume, provided their topology generation and ticket remain current. Every queued controller publication checks its generation, topology revision, layout ticket/outcome and freeze state. `animateTo(targets, {skip})` and accepted-layout transitions interpolate only distances greater than 2 px from displayed positions; skipped nodes stay at their displayed positions. A scene-controller destination update preserves the layout ticket and supplies final positions for direct animation. The package default transition duration was already zero; no global 350 ms default remains to remove here.

**Test correction.** The existing `test/layout_transition_test.dart` required a transition for one-iteration force-layout jitter below 2 px, conflicting with U28's threshold. Its fixture now uses deterministic destinations with a move over 2 px; every assertion remains intact. The nine new acceptance tests were not edited.

**Verification** (wrapped and serial): the literal acceptance command could not run because the installed Flutter SDK cache is read-only in this sandbox; a writable SDK attempt also encountered read-only telemetry state. A temporary native Flutter runner compiled the unchanged test mains and ran them through `test_core` with assertions enabled and the VM service disabled: acceptance 9/9; layout transitions 1/1; controller 13/13; scene layout lifecycle 3/3; scene controller 13/13 (39 passed, zero skipped). Logs: `/tmp/tentura-u28-final.log`, `/tmp/tentura-u28-final-runner.compile.log`. Scoped analyzer output matched a temporary HEAD-source baseline exactly (42 existing diagnostics, zero introduced); logs `/tmp/tentura-u28-analyze-before.log` and `/tmp/tentura-u28-analyze-final.log`. `git diff --check` passed. No whole suite, tracking commands, branch changes or commits: Alloy owns those steps. Part 2 (scene revision, algorithm identity, client tap resolver) remains outside this task.


## UNIT U28 — partial — 2026-10-08

Part 1/2 retry (`tentura-s7gl.29`): refresh the existing pending-layout position capture on each animation tick, preserving progress made after the layout request. Acceptance and pause retain that displayed geometry while preserving the accepted destinations; resume measures its >2 px threshold from that geometry. Keeping this capture also handles algorithms that emit an intermediate frame before their terminal frame.

Added a delayed-layout regression: start a transition, request layout, advance animation, accept layout, pause before queued publication, drain the callback, and resume. It asserts no frozen position jump/publication/camera change, retained destinations, no extra layout request, and an exactly-2-px move excluded from the resumed tween. The regression failed before the fix (displayed x=200 reset to request-time x=150). Corrected `graph_view_p1_remediation_test.dart`'s fixture: one iteration becomes zero relayout iterations (`(1 * 0.1).toInt()`), so it cannot exercise the required >2 px tween. Ten iterations and a bounded wait for acceptance make the original assertions meaningful; no assertions removed or weakened.

**Verification** (serial, wrapped): all 156 tests in all 16 graph-package test files passed, including all 10 transition/publication tests, zero skipped. The literal Flutter CLI command is still blocked by its read-only SDK cache. Used the existing temporary native Flutter runner, compiling the test mains with assertions enabled and running each file serially through `test_core`, with the VM service disabled. Full log: `/tmp/tentura-u28-retry-full-final.log`; runner and manifest: `/tmp/tentura-u28-retry-validation/`. Source analyzer diagnostics match the previous attempt's baseline (42, zero introduced); the new regression adds no diagnostics. Analyzer log: `/tmp/tentura-u28-retry-analyze-final.log`. `git diff --check` passed. No tracking commands or git mutations; Alloy owns landing. Part 2 remains outside scope.

### U28 part 1 analyzer repair — blocked — 2026-10-08

No implementation or test changes this iteration. The required analyzer command is provably incorrect: `set -e` exits on Dart's warning status 2 before evaluating its count assertions; with clean analyzer output, `pipefail` makes the zero-match error `grep` exit 1 before those assertions as well. A clean-output reproduction returned 1. Correcting this task's check must retain its error and issue-count assertions while handling normal analyzer statuses and zero matches, as `scripts/check-analyze-baseline.sh` already does. The check is supplied by Alloy rather than stored in a repository test, so its definition was not edited here.

The literal command also encounters the installed Flutter SDK's read-only cache. Invoking the actual cached Dart executable through the cleanup wrapper completed analysis: all of `lib` has **178 issues (0 errors, 13 warnings, 165 infos)**, not 42. An isolated temporary HEAD-source package produced exactly the same diagnostics after normalizing line numbers: zero introduced or removed. The prior 42 count covers only `controller.dart` and `scene_controller.dart`; applying it to all of `lib` changes the verification scope. No baseline was raised and no existing diagnostics were suppressed or changed. Logs: `/tmp/tentura-u28-fourth-analyze-before.log`, `/tmp/tentura-u28-fourth-analyze-head.log`; comparison and clean-output check evidence: `/tmp/tentura-u28-fourth-validation/analyzer-evidence.txt`.

**Focused verification** (wrapped, serial): all 15 current tests in `transition_pause_publication_test.dart` passed, zero skipped, using the existing native Flutter runner with assertions enabled. No full suite, tracking commands, or git mutations were run. Alloy must resolve the check definition and its intended baseline scope before this required gate can pass.


## UNIT U28 — partial — 2026-10-08

Part 1/2 analyzer repair (`tentura-s7gl.29`) completes this iteration's required zero-error check. Removed unused private controller helpers and imports, removed redundant non-null assertions after null checks, and made the existing dynamic generic arguments explicit. The pause/resume, threshold and publication behavior is preserved. No analyzer settings or baselines changed; tests edited: none in this iteration.

**Verification** (wrapped, serial): the required analyzer command's Bash body runs unchanged with the installed cached Dart executable on `PATH`, and exits 0 with `lib analyze: no errors`. Full-lib diagnostics are now **161 infos, zero warnings and zero errors**, down from 178 issues (13 warnings, 165 infos). Comparing diagnostics with the pre-edit output, ignoring source coordinates, confirms **zero introduced and 17 removed**. Log: `/tmp/tentura-u28-fifth-required-analyze.log`.

The Flutter CLI cannot write its telemetry session file in this sandbox, so focused tests ran through the installed native Flutter engine and `test_core`, with assertions enabled and unchanged test mains: transition/pause/publication **15**, controller **13**, layout transition **1**, scene rendering **5**; **34 passed, zero skipped**, wrapped command exit 0. Log: `/tmp/tentura-u28-fifth-native-tests.log`. `git diff --check` passed. No full suite, tracking commands or git mutations ran. U28 part 2 remains outside scope.

## UNIT U28 — complete — 2026-10-08

Part 2/2 (`tentura-s7gl.64`): `GraphSceneController` maintains a monotonic scene revision captured in each snapshot and exposed by `GraphController.sceneRevision`. Reads preserve the revision; committed scene changes advance it. The client tap resolver compares the painted scene and camera revisions, accepting current label frames while rejecting stale geometry. `ConstellationCubit` caches its layout algorithm by `state.graphRevision`, so fixed-viewport rebuilds retain algorithm identity and do not request another layout. Client version and the tracked web cache-buster both advance to **7.33.5**. This retry retains that focused implementation already present in the checkout.

**Test correction.** The task-authored `constellation_scene_revision_interaction_test.dart` fixtures explicitly supplied four empty `peers`/`edges` arguments despite those fields' `@Default([])` declarations. These redundant arguments introduced four analyzer diagnostics and violated the plan's mandatory lint-baseline constraint: the required gate failed at **2089 > 2085**. Removed only those arguments; fixture values, all assertions and all three test cases remain unchanged. No implementation or analyzer baseline was changed in this retry.

**Verification** (wrapped and serial): `scripts/check-analyze-baseline.sh packages/client` completed with **2085 <= 2085**, exit 0, using the existing temporary writable Flutter SDK/cache, suppressed telemetry and `analyze --no-pub`. Comparing diagnostic messages before and after shows no introduced diagnostics. `scripts/check-custom-lints.sh packages/client` also exited 0 (**0 reported custom diagnostics <= baseline 24**); its baseline was left intact. Logs: `/tmp/tentura-u28-part2-client-baseline-final.log`, `/tmp/tentura-u28-part2-custom-lints-final.log`.

The two focused Flutter CLI runs (with `--no-pub`) reached the test loader but could not bind its loopback socket (`127.0.0.1`, `Operation not permitted`), before any assertion ran. Compiled both current test mains with assertions enabled, `ENV=test` and `env/test.env`, then executed them serially through the native Flutter engine and `test_core` direct runner with the VM service disabled: graph scene revision **1/1**, client scene interactions **3/3**, **4 passed, zero skipped**, both wrapped commands exit 0. Logs: `/tmp/tentura-u28-part2-graph-native-final.log`, `/tmp/tentura-u28-part2-client-native-final.log`; CLI restriction evidence: `/tmp/tentura-u28-part2-graph-cli-final.log`, `/tmp/tentura-u28-part2-client-cli-final.log`. `git diff --check` passed.

**Deviations and follow-ups.** The normal Flutter CLI test commands remain blocked by sandbox socket policy; Alloy should rerun them in its verification environment. No whole suite, tracking commands, branch changes, staging or commits were run. The user's explicit instruction that Alloy owns verification and git overrides the executor contract's commit step; Alloy owns the focused commit and full-suite verification.
