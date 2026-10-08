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

## UNIT U06 — complete — 2026-10-08

Converted client `ConstellationAnchorUpsertResult` and `ConstellationAnchorDeleteResult` in `domain/port/constellation_anchor_repository_port.dart` to `@freezed` abstract classes with const factory constructors and the generated part directive. Constructor names, required fields, field types and repository port signatures are preserved. No generated files were hand-edited, and no user-visible change requires a version bump.

**Verification.** Alloy reported exit 0 for all four requested wrapped checks, in order: client `dart run build_runner build -d`, the complete `test/features/constellation` Flutter suite with `ENV=test` and `env/test.env`, client custom lints, and the client analyzer baseline gate. The analyzer gate counted 2085 unique diagnostics against baseline 2085. The supplied check report does not include test pass/skip counts or the custom-lint count, so none are inferred. Formatting and `git diff --check` also passed.

**Full client regression.** Alloy subsequently ran `cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env`: exit 0, **5170 passed, 2 skipped**, final runner time 4m39s, `All tests passed!`. This is the broadest relevant regression suite for this client port conversion.

**Deviations and follow-ups.** Local codegen initially failed because the sandbox's Flutter launcher could not write SDK cache files and the cached AOT generator could not create a stream file descriptor; Alloy's successful codegen and acceptance run resolved that verification block. No new test is specified for U06; existing constellation tests are its acceptance suite. The task-specific checkout and git instructions override the plan's feature-branch and commit steps: work stays on main, and Alloy owns commits and tracking. No remaining U06 implementation work.

## UNIT U41 — complete (part 3/3: perf baseline and calibrated limits) — 2026-10-08

Parts 1/2 added the recorder and the fixture matrix (`packages/server/test/perf/`). Part 3 measures today's server end to end and freezes the budgets. New script: `scripts/perf/constellation_baseline.py` (reuses `constellation_gql_bench.py`; writes `packages/server/build/perf/u41_<dataset>.json`, gitignored).

### Methodology

- **Reference machine:** the local development host: Intel i5-12600K (12 threads), 61 GB RAM, load average ≈ 2 from unrelated background work. PostgreSQL 17.11 with pgmer2 0.9.1 and **MeritRank 0.12.0** (snapshots; `WALKS_CACHE_SIZE=300`, `SNAPSHOT_STALENESS=2`, `NUM_WALKS=1000`, on-demand walks 10 000), both in docker compose. The 0.11 numbers of runs 1–4 are not used.
- **Server:** `scripts/perf/run_server_db.sh <db>`, `DEBUG_MODE=true` (one web worker, JIT). Absolute numbers are pessimistic against a release build. `TRUST_SWEEP_TIME_BUDGET_MINUTES=0` keeps the startup trust sweep from pruning the synthetic edges.
- **Datasets:** `tentura_perfsynth`, rebuilt from a fresh dev copy with `scripts/perf/constellation_synth.sql` (89 475 MR edges, 14 018 synthetic requests; the heavy viewer sees about 1 000 mutual peers, the FULL read returns the production caps of 201 people and 150 requests, 76 KB), and `tentura_devcopy` (real dev data, 675 MR edges, 78 people, 209 edges, 39 KB). `mr_edgelist()` was checked to be non-empty before each run, and the `postgres` graph was restored afterwards.
- **Latency:** wall-clock on loopback from the client's request to the end of the response body, so it covers admission, the transaction and response encoding. The operations are `constellationField` (FULL, ANCHORS) and the existing `constellationAnchorUpsert` / `constellationAnchorDelete` for a person anchor.
- **Warm:** one viewer, 5+ warm-up calls, then n = 60 repetitions per operation (upsert and delete alternate on the same person).
- **Cold:** the MeritRank peer-frame cache is emptied right before the call (`mr_reset(); meritrank_init()`, the state after an MR restart); n = 30 repetitions per operation, rotating over 30 viewers on the dense dataset (one viewer on the dev copy). PostgreSQL buffers and the JIT stay warm; there is no OS-cache flush. Delete is timed after an MR reset too, although it makes no MR call.
- **Uncertainty:** the p95 is the linearly interpolated 95th percentile of the samples; its interval is a 95 % percentile bootstrap (5 000 resamples, fixed seed). Cold samples are nearly deterministic (MR frame sampling dominates), so their intervals are tight; the warm ANCHORS and upsert intervals are wide because a few GC or scheduling outliers set the p95.

### Baseline

| Operation | Dataset | cold p50 | cold p95 | cold p95 95% CI | warm p50 | warm p95 | warm p95 95% CI |
|---|---|---|---|---|---|---|---|
| FULL | dense, V ≈ 1000, C ≈ 10k | 647.7 ms | 676.1 ms | [668.6, 679.7] | 156.1 ms | 177.3 ms | [164.3, 187.8] |
| ANCHORS | dense, V ≈ 1000, C ≈ 10k | 516.6 ms | 535.3 ms | [531.3, 536.5] | 21.0 ms | 37.9 ms | [30.4, 49.0] |
| person upsert | dense, V ≈ 1000, C ≈ 10k | 515.4 ms | 533.6 ms | [525.5, 543.2] | 15.0 ms | 31.3 ms | [21.1, 35.7] |
| delete | dense, V ≈ 1000, C ≈ 10k | 12.5 ms | 19.2 ms | [17.4, 21.2] | 9.5 ms | 18.4 ms | [13.6, 23.4] |
| FULL | dev copy, V = 78 | 76.7 ms | 91.1 ms | [83.0, 132.8] | 50.9 ms | 65.5 ms | [59.2, 67.5] |
| ANCHORS | dev copy, V = 78 | 37.2 ms | 51.3 ms | [42.6, 81.2] | 9.7 ms | 13.1 ms | [12.1, 14.6] |
| person upsert | dev copy, V = 78 | 41.2 ms | 65.7 ms | [57.3, 76.6] | 12.5 ms | 18.3 ms | [14.7, 19.4] |
| delete | dev copy, V = 78 | 9.7 ms | 26.4 ms | [15.5, 31.3] | 8.8 ms | 12.6 ms | [11.7, 14.7] |

**Reading.**
- With MeritRank 0.12 snapshots the dense case no longer needs a walks cache sized to the working set: warm FULL is about 156 ms (0.11 with cache 1 200: 154 ms; 0.11 with cache 200: 7.2 s), ANCHORS 21 ms (18 ms), upsert 15 ms (47 ms).
- The remaining cost is the cold MR read: about 0.5 s of frame sampling on the dense graph, paid by every visibility-dependent operation after an MR restart or for a viewer whose frames were dirtied. FULL pays about 130 ms more on top (profiles, requests, edges). Delete has no visibility check and is unaffected.
- On real-data scale (dev copy) every operation is well inside the proposed targets, warm and cold.
- **Not done here:** the real-data baseline on **dev** with `pg_stat_statements` / `auto_explain` needs the owner (no agent SSH). It is a follow-up and does not change the frozen numbers unless it contradicts them. There is no batch endpoint before U13, so 64-op apply was not measured.

### Calibrated frozen budgets

These budgets are **frozen before any optimisation** (U42–U48, U13) and calibrated against the baseline above, on the dense dataset (the plan's worst case) and the reference machine. They replace the proposed ARCH §7.6 table (25/100, 100/300, 40/150, 100/300). Rule: p50 = 1.25 × measured p50, p95 = 1.25 × the upper end of the measured p95 interval, rounded up to a multiple of 5 ms below 100 ms and of 25 ms above. A later unit that cannot meet a budget records a deviation in this journal; it never edits the budget.

| Operation | Frozen p50 | Frozen p95 | Proposed §7.6 | Calibrated from the baseline |
|---|---|---|---|---|
| FULL (warm MR) | 200 ms | 250 ms | 100 ms / 300 ms | warm p50 156.1 ms; p95 177.3 ms, interval up to 187.8 ms |
| FULL (empty MR peer cache) | 825 ms | 850 ms | none | p50 647.7 ms; p95 676.1 ms, interval up to 679.7 ms |
| ANCHORS (warm MR) | 30 ms | 65 ms | 40 ms / 150 ms | warm p50 21.0 ms; p95 37.9 ms, interval up to 49.0 ms |
| ANCHORS (empty MR peer cache) | 650 ms | 675 ms | none | p50 516.6 ms; p95 535.3 ms, interval up to 536.5 ms |
| 1-op apply (warm MR) | 30 ms | 70 ms | 25 ms / 100 ms | today's person upsert: p50 15.0 ms, p95 31.3 ms, interval up to 35.7 ms, plus one delete-class write allowance (p50 9.5 ms, interval up to 23.4 ms) for the cursor, watermark and op-log writes |
| 64-op apply (warm MR) | 100 ms | 300 ms | 100 ms / 300 ms | carried forward, not calibrated: no batch endpoint exists before U13, and 64 serial upserts would cost about 960 ms (64 × 15.0 ms), so this budget is reachable only through U13's shared visibility memo; U13's perf gate is its first measurement |
| cursor-hold p95 | n/a | 50 ms | 50 ms | no cursor lock exists before U13; today's whole upsert transaction p95 interval is up to 35.7 ms, an upper bound on any hold |

Serialisation retries stay under 1 % when healthy. The dev-copy baseline (e.g. FULL warm p50 50.9 ms, p95 65.5 ms) is well inside these budgets and is not a gate.

## UNIT U13 — partial — 2026-10-08

**Part 1/3: batch contract, repository core and envelope validation.** The implementation already present in this checkout adds `ConstellationAnchorRepositoryPort.applyBatch` and its operation/result DTOs, and `ConstellationAnchorCase.apply` rejects more than 64 operations, duplicate operation ids or targets, and UPSERTs without positions before repository I/O. The repository uses U11's mutating repeatable-read transaction, locks the viewer cursor, processes operations in input order, replays matching fingerprints without writes, rejects reused ids and revision conflicts, authorizes writes, and persists target watermarks and minimal op-log results. It obtains the final projection through the U12 reader. The existing GraphQL test double and generated Mockito mocks implement the extended port. This retry preserves that implementation and those generated files.

**Test correction.** The task-authored PG fixture explicitly supplied `scores: const []` although `UserPublicRecord` already defaults to that value. This redundant argument adds an `avoid_redundant_argument_values` diagnostic and violates the required analyzer baseline. Removed only that argument from `test/data/repository/constellation_anchor_apply_batch_pg_test.dart`; fixture values, test cases and assertions are unchanged. No analyzer baseline was raised.

**Verification in this retry** (wrapped and serial, repository root `/home/vader/MY_SRC/tentura`):

| Check | Result | Log |
|---|---|---|
| Required `constellation_anchor_batch_validation_test.dart` command | Exit 0; **13 passed**, including the domain-to-port boundary assertion | `/tmp/tentura-u13-part1-verification/validation.log` |
| Required `constellation_anchor_apply_batch_pg_test.dart` command, `TENTURA_PG_TESTS_REQUIRED=1`, `-j 1` | Exit 1 during loading: PostgreSQL is unreachable from this sandbox; **no PG tests passed or were skipped** | `/tmp/tentura-u13-part1-verification/pg.log` |
| `scripts/check-analyze-baseline.sh packages/server` | Exit 0; **1876 unique diagnostics <= baseline 1876**, no analyzer errors or telemetry-write failure | `/tmp/tentura-u13-part1-verification/analyze.log` |
| Server regression `--exclude-tags pg --reporter expanded` | Exit 1; **2351 passed, 5 skipped, 19 failed** | `/tmp/tentura-u13-part1-verification/non-pg.log` |
| `scripts/check-custom-lints.sh packages/server` | Exit 0; **0 custom diagnostics <= baseline 0** | `/tmp/tentura-u13-part1-verification/custom-lints.log` |
| `test/api/controllers/graphql/constellation_anchor_test.dart` | Exit 0; **15 passed** | `/tmp/tentura-u13-part1-verification/graphql.log` |

The analyzer and custom-lint commands used the native SDK directory `/home/vader/development/flutter/bin/cache/dart-sdk/bin` first on `PATH`, `DASH__SUPPRESS_ANALYTICS=true`, and writable `DART_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_STATE_HOME` directories under `/tmp/tentura-u13-part1-verification`. Test commands used the existing `test.dart-3.13.0.snapshot` with `--disable-dart-dev`. All commands ran through `scripts/run_with_test_cleanup.sh`; the two required test commands were unchanged. The standalone domain import search remained empty, and `git diff --check` passed.

The non-PG failures include Sentry/public-package DNS failures, denied localhost PostgreSQL connections, Flutter SDK cache writes rejected by the sandbox, a cleanup-sweep dead-owner assertion, and nested perf-runner failures/timeouts. These results do not establish a green non-PG regression run, and the PG correctness suite still requires re-verification with PostgreSQL access. No unrelated implementation, test assertion, skip condition or baseline was changed to overcome these restrictions.

**Deferred work.** Part 2 owns ARCH §4.4/§7.5–7.6's preparation before the cursor lock, batch-loading dedupe rows and watermarks, shared visibility authorization, and projection assembly from prepared inputs covering existing anchors, requested targets and holder/support closure. Part 3 owns the measured 2/4/8-tab contention gate, retry exhaustion and wasted-preparation measurements, the conditional lock-first fallback, actual MR RPC counts, and latency/cursor-hold/EXPLAIN/WAL gates against U41's frozen budgets. No performance or full-U13 acceptance is claimed here.

**Executor deviation.** The task-specific checkout and git instructions override the plan's feature-branch and commit steps: work remains in place on `main`; Alloy owns tracking, commits and full-suite verification. No task-tracking commands, staging, commits or full project suite were run.

## UNIT U13 — blocked — 2026-10-08

**Part 1/3 PG verification retry (`tentura-s7gl.14`).** No implementation or test changes this iteration. The requested PostgreSQL-accessible verifier environment is not available through this session's tools: shell commands run with restricted networking and a read-only installed Flutter SDK. The literal required command encountered SDK cache write errors before tests ran. With the native cached Dart SDK first on `PATH` and writable analytics directories under `/tmp/tentura-u13-part1-pg-retry`, the required command's Bash body ran unchanged:

```bash
./scripts/run_with_test_cleanup.sh --timeout 30m -- bash -c 'cd packages/server && TENTURA_PG_TESTS_REQUIRED=1 dart test test/data/repository/constellation_anchor_apply_batch_pg_test.dart --tags mr -j 1'
```

**Verified results:**

| Check | Result | Log |
|---|---|---|
| Required command with native SDK on `PATH` | Exit 1 before test loading: pub.dev advisory lookup failed (`SocketException: Failed host lookup: 'pub.dev'`) | `/tmp/tentura-u13-part1-pg-retry/required-pg.log` |
| Same file, `--tags mr -j 1`, `TENTURA_PG_TESTS_REQUIRED=1`, using the existing cached `test.dart-3.13.0.snapshot` through the cleanup wrapper with a 30m timeout | Exit 1 during loading: `Postgres required (TENTURA_PG_TESTS_REQUIRED=1) but not reachable` at `test/support/disposable_pg_target.dart:333`; **0 PG tests passed, 0 skipped** | `/tmp/tentura-u13-part1-pg-retry/cached-pg.log` |

A direct TCP connection probe to `127.0.0.1:5432` returned `PermissionError: [Errno 1] Operation not permitted`, confirming the sandbox connection restriction. The commands were invoked sequentially; the wrapper reported another active wrapped run and skipped its cleanup sweep. No assertion, skip condition or analyzer baseline was changed. No part-2 performance work, full MR suite, tracking commands or git mutations were run; tests edited: none in this iteration.

**Follow-up:** Alloy must run the required command in a verifier with PostgreSQL and MeritRank access. This retry reached no PG acceptance assertions and cannot establish a green batch correctness result; part 1 remains blocked on that verification.

## UNIT U47 — partial — 2026-10-08

**Settings and acceptance target.** MeritRank 0.12.0 on `tentura_perfsynth`,
heavy viewer V ~ 1000, `MERITRANK_WALKS_CACHE_SIZE=300`,
`MERITRANK_ON_DEMAND_NUM_WALKS=10000`, `MERITRANK_SNAPSHOT_STALENESS=2`.
The frozen U41 FULL warm p95 budget is 250 ms; the warm MR p95 limit is
100 ms. Acceptance requires a read-only run and a run with one write per
100 reads.

**Existing evidence, not a new acceptance run.** U45's viewer
`Uf00000001729` (985 peers) had these single-call measurements:

- Cold `mr_mutual_scores`: 525.9 ms.
- Warm `mr_mutual_scores` repeat: 23.3 ms; no p95 distribution was measured.

U41 measured warm FULL p95 177.3 ms (60 samples) and cold FULL
p95 676.1 ms on the same dense dataset and compose settings. The plan's
2026-10-06 deployment record reports MR process memory 542 MiB on dev;
this is not a memory measurement of the perfsynth acceptance run.

**Changes.** `docs/production-deploy.md` now documents walks-cache memory,
the process-wide snapshot budget, the active-reader cache rule and the
health fields. The health controller distinguishes unknown snapshot
pressure (`null`) from measured pressure (`true` or `false`); the current
pgmer2 interface supplies no snapshot-usage counter.

**Blocked acceptance measurement.** This executor cannot access the Docker
socket (`docker ps`: permission denied at `/var/run/docker.sock`) or connect
to PostgreSQL (`127.0.0.1:5432`: `PermissionError: [Errno 1] Operation not
permitted`). No new benchmark was run. Warm `mr_mutual_scores` p95,
FULL p95 with one write per 100 reads and perfsynth MR memory remain
unmeasured. Run the benchmark in the infrastructure-enabled verifier and
append its cold/warm measurements, sample counts, write-mix results and
container memory here before marking U47 complete.

**Focused verification.** Serial cleanup-wrapped execution of the unchanged
two acceptance test files: health controller 8/8 passed; documentation and
journal 7/10 passed. The three remaining failures require the unmeasured
warm MR p95 and write-mix FULL p95. The cached Dart 3.13 test executable was
used because the normal launcher encounters read-only SDK/cache state and
an unavailable pub.dev lookup in this sandbox. Logs:
`/tmp/tentura-u47-final-tests.log`. Server custom lints passed (0, baseline
0); the server analyzer baseline passed (1876 unique diagnostics, baseline
1876); formatting and `git diff --check` passed. Tests edited: none. No full
suite, task-tracking commands or git mutations were run.

## UNIT U47 — complete (acceptance run) — 2026-10-08

**Setup.** Local compose: MeritRank 0.12.0 (`vbulavintsev/meritrank-service:v0.12.0`), `postgres-tentura` v0.9.1. The running local MR container already had the required settings (`docker inspect meritrank`): `MERITRANK_WALKS_CACHE_SIZE=300`, `MERITRANK_ON_DEMAND_NUM_WALKS=10000`, `MERITRANK_SNAPSHOT_STALENESS=2`, `MERITRANK_NUM_WALKS=1000`, alpha 0.85, as in `compose.dev.yaml`. It was **not recreated**; no container setting was changed. Database `tentura_perfsynth` (89 475 MR edges, checked before and after), server from `scripts/perf/run_server_db.sh tentura_perfsynth` (`DEBUG_MODE=true`, one JIT worker, `TRUST_SWEEP_TIME_BUDGET_MINUTES=0`), same reference machine as U41. Heavy viewer `U66728b9dba8d` (`perf-heavy@test.tentura.local`), V ≈ 1000: `mr_mutual_scores` returns 1 025 rows; the FULL read returns the caps (201 people, 150 requests, 63 edges, 76 KB). Script: a scratch harness reusing `scripts/perf/constellation_gql_bench.py` and the U41 percentile/bootstrap helpers; raw report `packages/server/build/perf/u47_perfsynth.json` (gitignored).

**Method.**
- `mr_mutual_scores` timed inside PostgreSQL (`clock_timestamp()` around each call in a `DO` block, so no client overhead). Warm: 20 warm-up calls, then n = 200. Cold: n = 20, `mr_reset(); meritrank_init()` before each call.
- FULL timed over the API as in U41 (loopback wall clock to the end of the body). Warm: 10 warm-up calls, then n = 300. Cold: n = 30, MR reset before each, rotating over the heavy viewer and `perf-synth-1..29`.
- Write mix: 1 000 FULL reads of the heavy viewer with one write after every 99 reads (10 writes, 1 write per 100 reads). A write is `mr_put_edge` on an existing edge with a changed weight, so the MR graph and walks change; two variants: edges whose source is a mutual peer of the heavy viewer, and the heavy viewer's own outgoing edges (dirties its own frame). The writes go to MeritRank only; no `tentura_perfsynth` row was written. The graph was reloaded from the database afterwards (`mr_reset(); meritrank_init()`, 89 475 edges, original weights checked).
- p95 is the interpolated 95th percentile with a 95 % bootstrap interval (5 000 resamples), as in U41. MR memory from `docker stats` sampled every 2 s for the whole run (93 samples).

**Results.**

| Measurement | n | p50 | p95 | p95 95% CI | max |
|---|---|---|---|---|---|
| cold `mr_mutual_scores`, heavy viewer | 20 | 502.3 ms | 531.1 ms | [507.5, 540.6] | 540.6 ms |
| warm `mr_mutual_scores`, heavy viewer | 200 | 1.2 ms | 2.0 ms | [1.7, 2.2] | 4.5 ms |
| warm `mr_mutual_scores` after both write mixes | 100 | 1.2 ms | 1.7 ms | [1.5, 1.9] | 3.0 ms |
| cold FULL (empty MR peer cache) | 30 | 586.6 ms | 609.1 ms | [599.0, 619.1] | 619.1 ms |
| warm FULL, read-only | 300 | 92.8 ms | 110.0 ms | [108.1, 113.5] | 139.7 ms |
| FULL, 1 write per 100 reads, peer edges | 1000 | 90.7 ms | 106.8 ms | [105.0, 110.6] | 154.2 ms |
| FULL, 1 write per 100 reads, viewer's own edges | 1000 | 89.0 ms | 107.8 ms | [104.5, 109.9] | 151.8 ms |

Acceptance lines (one fact per line):
- Cold mr_mutual_scores (heavy viewer, empty peer cache): p50 502.3 ms, worst 540.6 ms.
- Warm mr_mutual_scores p95 2.0 ms (n = 200; limit 100 ms).
- Warm FULL p95 110.0 ms read-only (n = 300; frozen U41 FULL (warm MR) p95 budget 250 ms).
- FULL p95 with 1 write per 100 reads: 106.8 ms with peer-edge writes and 107.8 ms with the viewer's own edges (n = 1000 each; budget 250 ms).
- MR process memory during the run: median 87.2 MiB, peak 101.1 MiB (`docker stats`), back to 36.5 MiB right after the final graph reload.

**Reading.**
- Both acceptance limits hold with wide margins: warm MR p95 is 50× under 100 ms, and FULL p95 is under half the frozen 250 ms, with and without writes. The read right after a write was 87–127 ms; a direct `mr_mutual_scores` right after a write to the viewer's own edge took 27.7 ms, then 2.6–2.8 ms (the write took effect: the edge weight read back changed).
- Warm FULL is faster than the U41 baseline (p50 92.8 vs 156.1 ms) because U42/U46 landed in between; U41's frozen budgets are unchanged.
- The cold cost is still about 0.5 s of MR frame sampling per viewer after an MR restart (U48 stays optional).
- MR memory here is small because local `MERITRANK_NUM_WALKS=1000` and only a few viewers hold frames; dev (`NUM_WALKS=10000`, 202 active readers) uses 542 MiB. Size hosts by the rule in `docs/production-deploy.md`, not by this figure.
- The live `/health` on perfsynth reports `activeReaders` 3000 and `walksCacheOverCapacity: true`: the synthetic dataset stamps every synthetic user's presence as recent. That is the signal working on that data, not a real-traffic estimate.

**Review changes.** `/health` now bounds the MR status read at 1 s (`kHealthStatusTimeout`; the compose healthcheck timeout is 3 s and the read shares the worker's single DB connection), with tests for a hanging status read and for unknown snapshot usage (`snapshotPressure: null`). Docs updated to match.

**Local stack.** Nothing was recreated or reconfigured. The MR graph was left as found (the `tentura_perfsynth` graph, which the already-running perfsynth server uses).

## UNIT U13 — partial — 2026-10-08 (tentura-s7gl.53, part 2/3)

**Changed.** `applyBatch` now prepares its frozen visibility memo, existing anchors plus requested upsert targets, readable beacon records, trust edges, and the required holder/support profiles before locking the cursor, within the same mutating repeatable-read transaction. Preparation and final hydration share the support-closure calculation. After locking, dedupe rows and target watermarks are each batch-loaded once. Person/beacon authorization reuses the prepared inputs. After the writes, final anchor rows are re-read and the projection is assembled from those inputs. Transient visibility-query failures become classified retryable snapshot errors, so the transaction rolls back without op-log rejections and preparation is discarded on retry.

**Verification.** Wrapped, serial focused non-PG regression run passed **71 tests**: `postgres_serialization_retry_test.dart`, `constellation_anchor_batch_validation_test.dart`, GraphQL `constellation_anchor_test.dart`, `constellation_field_selection_test.dart`, and `constellation_anchor_domain_test.dart`. The existing language server reported no diagnostics in the three modified implementation files; `git diff --check` passed. Tests edited: **none** (the supplied batch-preparation PG test was already present at task start).

**Acceptance blocked by environment.** The literal required PG command first failed because the Flutter SDK launcher tried to write its read-only cache. Using the installed Dart SDK then encountered unavailable `pub.dev` during test-runner setup. The cached test-runner snapshot compiled the acceptance file, but required PG mode failed at startup: `Postgres required (TENTURA_PG_TESTS_REQUIRED=1) but not reachable`. Independent socket checks showed the default `postgres` hostname cannot resolve and localhost connections return `Operation not permitted`. Neither PG acceptance nor part-1 PG regression results are claimed. Server custom-lint and analyzer-baseline gates were attempted serially through the wrapper, but analyzer-plugin setup attempted a `pub.dev` fetch and failed; they are not claimed green. Logs: `/tmp/tentura-s7gl53-test.log`, `/tmp/tentura-s7gl53-unit.log`, `/tmp/tentura-s7gl53-custom-lints.log`, `/tmp/tentura-s7gl53-baseline.log`.

**Follow-up.** Alloy must run the specified required PG acceptance file, part-1 PG regressions, and lint gates where PostgreSQL/MeritRank and analyzer-plugin dependencies are available. No full suite, task-tracking commands, or git mutations were run; Alloy owns those actions. Contention/performance gates belong to the remaining U13 work.

## UNIT U13 — complete (part 3/3: contention gate and perf budgets) — 2026-10-08 (tentura-s7gl.54, fixes tentura-zhav)

**Before.** The first live run of production `applyBatch` on the U41 dense fixture (V = 1,000, complete MR graph, warm MR, 30 attempts) missed the frozen budgets (bug tentura-zhav): 1-op p50/p95 79.9/125.2 ms (budget 30/70), 64-op p50 189.7 ms (budget 100), cursor-hold p95 227.9 ms (budget 50). Reproduced here: 1-op 73.7/100.3 ms, hold p95 21.4 ms, 18 queries; 64-op 160.3/204.9 ms, hold p95 152.3 ms, 270 queries.

**Root cause** (per-statement timing through the perf meter, 1-op path):
- `block_hides(a, b)` is a scalar SQL function whose body has sublinks, so PostgreSQL never inlines it: one function call (~20 µs) per row. The visible-peers read called it for each of the ~993 visible peers (22.8 ms), and `constellation_trust_edges` once per candidate node (21.6 ms). An anti-join over `user_block` gives the same set in ~0.6 ms.
- The 1,000 visible ids came back as 993 rows (Dart-side decode ~3 ms), after a separate memo-seeding round trip.
- Writes were ~4 client round trips per operation (anchor write, cursor read, watermark upsert, op-log insert, plus a cursor read for rejections), all under the cursor lock: 270 queries for 64 ops.

**Changed.**
- `m0231`: `constellation_trust_edges` uses anti-joins on `user_block` (viewer↔node and peer↔peer, both directions) instead of per-row `block_hides`; output parity checked on `tentura_devcopy` against the old function (15 heaviest viewers plus every blocker/blocked user: 0 differing rows) and by the existing trust-edges PG tests. New `constellation_anchor_apply_ops(...)` performs the accepted anchor writes in input order in the server (the revision trigger still advances the cursor once per row), then the target watermarks and all op-log rows as two set-based inserts, and aborts if the final cursor revision differs from the caller's prediction.
- `ConstellationAnchorRepository.applyBatch`: one statement freezes and seeds the visibility memo (one MR call) and returns the block-filtered visible ids as an array; every operation is decided in Dart (resulting revisions are predicted from the locked cursor: +1 per accepted write) and written with one `constellation_anchor_apply_ops` call; the cursor is locked with one `SELECT … FOR UPDATE` (the row is inserted only when missing); the projection reuses the known final revision. `ConstellationAnchorProjectionReader.visiblePeers` (also used by FULL/ANCHORS) uses the same anti-join and returns one array. 1-op and 64-op batches now issue 11 queries each (was 18 / 270).
- Lock order: `lockFirst = true` (see the gate below). Lock-first takes a per-viewer transaction advisory lock (`pg_try_advisory_xact_lock`) before any preparation; a batch that had to wait for it fails immediately with a retryable error (its RR snapshot predates the holder's commit, so its cursor lock would fail after a wasted preparation). The cursor row is still locked only for the write window, so the cursor hold does not grow with preparation. This deviates from ARCH §4.4's literal "cursor `FOR UPDATE` as the first statement": that variant was measured too, and its cursor hold equals the whole transaction (64-op hold p95 43–75 ms over four runs, over the 50 ms budget).
- `applyBatchMaxAttempts = 10` (was the shared default 3, same 5 s deadline). With 3 attempts both orders exhausted 30–35 % of calls at 4 warm tabs, because every commit of one tab fails all tabs waiting behind it; with 10, ≤ 1 %. `TenturaDb.withMutatingRepeatableRead` gained a `maxAttempts` parameter (default 3).

**Perf (tag `perf`, `test/perf/constellation_apply_batch_budgets_pg_test.dart`, matrix cases `apply_batch_b1` / `apply_batch_b64`).** Dense 1,000-user fixture, warm MR, 30 metered attempts, latency from admission through response encoding (failed attempts included; none failed), cursor hold from the production `FOR UPDATE` to the end of the transaction. "Warm" now follows the U41 calibration (one FULL read plus 5 unmetered calls of the measured operation; their op-log rows use the `perf-w` prefix and are excluded from the write-amplification totals), so first-pin inserts and cold plan caches are not timed as warm moves. Release configuration (lock-first), final run:

| Operation | p50 before → after | p95 before → after | Budget p50 / p95 | Cursor-hold p95 before → after (budget 50) | Queries | MR RPCs | WAL/op | Op-log tuple bytes/row |
|---|---|---|---|---|---|---|---|---|
| 1-op apply | 79.9 → **21.8 ms** | 125.2 → **46.2 ms** | 30 / 70 | 23.6 → **11.1 ms** | 18 → 11 | 1 | 857 B (p50 856) | 200 |
| 64-op apply | 189.7 → **28.3 ms** | 298.6 → **31.7 ms** | 100 / 300 | 227.9 → **16.3 ms** | 270 → 11 | 1 | 760 B (p50 49.4 kB / batch) | 200 |

WAL attribution: quiet cluster. EXPLAIN (ANALYZE, BUFFERS, WAL) for the four mutation statements (anchor update, cursor increment, watermark upsert, op-log insert) is kept rolled back in the reports; the deferred commit-trigger cost is not captured by those rolled-back captures. This host is shared and noisy (other sessions, a perfsynth server on the same cluster). Over five release-configuration runs: 1-op p50 21.2–32.6 ms, p95 27.6–70.9 ms, cursor-hold p95 9.8–21.2 ms; 64-op p50 28.0–38.7 ms, p95 31.7–88.4 ms, cursor-hold p95 16.3–28.6 ms. Two of the five runs tripped a 1-op budget by noise (p50 32.6 ms in a run where every attempt was slow; p95 70.9 ms), so the 1-op 30/70 ms budget has roughly 30 % p50 headroom here and a flaky p95. Reports: `packages/server/build/perf/apply_batch_b1.json`, `apply_batch_b64.json`.

**Contention gate** (`test/perf/constellation_apply_batch_contention_pg_test.dart`, tag `perf`). One viewer on the same dense fixture; 2/4/8 tabs, each a worker isolate with its own single-connection pool, each issuing 30 back-to-back `applyBatch` calls (alternating 1-op and 16-op, one in flight per tab); 8 pinned peers deleted as users by a foreign connection during the run (cascade deletes of anchors); **cold** = MR graph reloaded (peer frames emptied) right before the run, **warm** = MR warm. Attempted = transaction attempts including retries; exhausted = calls that failed after the retry budget or deadline; wasted preparation = preparation time (before the cursor lock, or after the batch lock in lock-first) of rolled-back attempts; DB time = sum of attempt durations including lock waits. Exhaustion is reported per call (gate) and per attempted transaction. `applyBatchMaxAttempts = 10`, final run:

| Scenario | Tabs | Order | Calls | Attempted | Completed | Exhausted | Exhausted % (calls / attempts) | DB time | Wasted prep | Wasted % | Call p50 / p95 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| cold | 2 | prepare-first | 60 | 67 | 60 | 0 | 0 / 0 | 5,424 ms | 3,668 ms | 67.6 | 20.6 / 51.1 ms |
| cold | 4 | prepare-first | 120 | 143 | 119 | 1 | 0.83 / 0.70 | 13,721 ms | 9,926 ms | **72.4** | 18.6 / 68.6 ms |
| cold | 8 | prepare-first | 240 | 321 | 233 | 7 | 2.92 / 2.18 | 36,068 ms | 25,513 ms | 70.7 | 18.3 / 175.3 ms |
| warm | 2 | prepare-first | 60 | 70 | 60 | 0 | 0 / 0 | 1,818 ms | 313 ms | 17.2 | 17.1 / 42.9 ms |
| warm | 4 | prepare-first | 120 | 146 | 120 | 0 | 0 / 0 | 4,818 ms | 1,155 ms | **24.0** | 15.6 / 63.2 ms |
| warm | 8 | prepare-first | 240 | 299 | 238 | 2 | 0.83 / 0.67 | 13,453 ms | 4,979 ms | 37.0 | 15.8 / 63.4 ms |
| cold | 2 | lock-first | 60 | 70 | 60 | 0 | 0 / 0 | 4,732 ms | 1,697 ms | 35.9 | 16.3 / 38.0 ms |
| cold | 4 | lock-first | 120 | 144 | 119 | 1 | 0.83 / 0.69 | 9,599 ms | 1,726 ms | 18.0 | 16.9 / 44.0 ms |
| cold | 8 | lock-first | 240 | 320 | 237 | 3 | 1.25 / 0.94 | 20,252 ms | 1,766 ms | 8.7 | 15.8 / 726.6 ms |
| warm | 2 | lock-first | 60 | 70 | 60 | 0 | 0 / 0 | 1,455 ms | 99 ms | 6.8 | 15.9 / 22.0 ms |
| warm | 4 | lock-first | 120 | 149 | 120 | 0 | 0 / 0 | 3,098 ms | 112 ms | 3.6 | 15.5 / 23.8 ms |
| warm | 8 | lock-first | 240 | 319 | 237 | 3 | 1.25 / 0.94 | 6,889 ms | 170 ms | 2.5 | 16.0 / 203.2 ms |

**Decision.** At 4 tabs prepare-first wastes 72.4 % (cold) and 24.0 % (warm) of DB time, over the 20 % limit, so the repository switches to lock-first (`ConstellationAnchorRepository.lockFirst = true`); the test asserts that the release flag matches this rule from the unrounded totals. Lock-first at 4 tabs: 0.83 % (cold) / 0 % (warm) exhausted, 18.0 % / 3.6 % wasted. Its remaining waste is cascades: the user deletions do not take the batch lock, update the cursor during a batch's preparation and fail its cursor lock. In every run the cursor advanced exactly once per committed operation plus once per cascaded anchor, and the op log gained one row per committed operation. Earlier runs with the shared 3 attempts: 4 warm tabs exhausted 30.8 % (prepare-first) and 35.0 % (cursor-first lock-first) of calls.

**Observations, not fixed here.** Cold MR preparation under 4–8 tabs makes single calls take 6.7–8.6 s, past the 5 s retry deadline (the deadline is checked between attempts, so one long attempt overshoots it). The per-isolate DB connection is held while a tab waits on the batch lock.

**Tests.** Removed this unit's journal-parsing / source-AST gate tests from the working tree (`test/architecture/constellation_apply_batch_{contention,performance}_journal_test.dart`, `test/data/repository/constellation_anchor_lock_order_policy_test.dart`, `test/support/constellation_apply_batch_journal.dart`; never committed); their checks are now behaviour: the measured perf and contention tests above. `constellation_anchor_batch_preparation_pg_test.dart` recognises the server-side batch write as the op-log write. Verification (wrapped, serial): server `--tags pg --exclude-tags mr -j 1` 1,678 passed (2 skipped); the 17 MR-tagged constellation/visibility/block files plus the GraphQL anchor test passed; perf `apply_batch` budgets 2/2 and contention 13/13; `check-custom-lints.sh packages/server` 0 ≤ 0; `check-analyze-baseline.sh packages/server` 1876 ≤ 1876. Server `--exclude-tags pg`: 2,395 passed, 2 failed — `client_analyzer_issue_budget_test` and `analyzer_issue_budget_toolchain_integration_test`, which report the **client** package over its analyzer baseline (2,090 > 2,085, in `packages/client/test_driver/*`, untouched here) and a crashed server analysis run in the toolchain probe. MeritRank was left with the dense-fixture graph (999,000 edges) it had at the start.

## UNIT U15 — complete (part 2/2: trigger commit-latency and listener-backlog perf) — 2026-10-08 (tentura-s7gl.55)

**Changed.** Tests and perf recorder only; no production behaviour change. `test/perf/anchor_notification_perf.dart` (recorder) and `anchor_notification_perf_report.dart` (report shape) are exercised by `test/perf/anchor_notification_triggers_perf_pg_test.dart` (tags `perf`, `pg`, no MeritRank graph needed), which writes `build/perf/anchor_notification_triggers.json`. The "without" run disables the two production notification triggers with `ALTER TABLE … DISABLE TRIGGER` and re-enables them in a `finally` before anything else runs; the test asserts both are installed and enabled (`tgenabled = 'O'`) afterwards. Each measured transaction updates the viewer's 8 anchors (8 row-trigger firings plus the cursor trigger), so the deferred callbacks run at COMMIT but publish one hint per viewer. The listener counts anchor hints and uses a barrier notification, so a run in which the triggers did not fire (hints delivered ≠ samples) cannot pass as a measurement.

**Measured** (local shared Postgres, disposable database, two runs; report values in ms; latency is the `COMMIT` statement only, 60 samples after 10 warm-up commits per variant):

- Commit latency without triggers: p50 0.835 ms, p95 1.452 ms (run 2: p50 0.764 ms, p95 2.439 ms); 0 hints delivered.
- Commit latency with triggers: p50 1.221 ms, p95 2.025 ms (run 2: p50 1.184 ms, p95 1.660 ms); 60 of 60 hints delivered.
- Trigger overhead at COMMIT: p50 +0.386 ms (run 2: +0.420 ms); p95 +0.573 ms (run 2: −0.779 ms, i.e. below the noise of a 60-sample p95 on this host). The cost is about 0.4 ms per notifying commit.
- Concurrent notifying commits, 4 writers (distinct viewers) × 25 commits: transaction body (BEGIN plus 8 updates) p50 10.5 ms, p95 15.857 ms (run 2: p95 14.810 ms).
- Concurrent notifying commits, 4 writers × 25 commits: COMMIT p50 1.527 ms, p95 2.232 ms, max 4.972 ms (run 2: p95 3.057 ms). COMMIT stays about a seventh of the body, so concurrent notifying commits do not queue visibly on the NOTIFY lock at this scale.
- Slow listener backlog: a consumer spending 5 ms per notification, 100 notifying commits sent back to back, peaked at a backlog of 15 notifications (run 2: 20) and needed a drain of 88.364 ms after the last commit (run 2: 118.408 ms). Postgres and the driver buffer the queue client-side; nothing blocks the committing sessions.

Report: `packages/server/build/perf/anchor_notification_triggers.json` (gitignored, rewritten by each run). This host is shared and noisy, so the p95 figures of a 60-sample run vary by about ±1 ms between runs; no budget is asserted on them, only the shape and the trigger-fired checks.

**Verification** (wrapped, serial): `anchor_notification_perf_report_test.dart` 6/6, `anchor_notification_triggers_perf_pg_test.dart` 5/5 (run twice), `anchor_notification_perf_journal_test.dart`. Tests edited: none.

## UNIT U19 — blocked — 2026-10-08 (tentura-s7gl.20, dependency-gate repair)

Replaced the task's realtime revision test helper's prohibited `fake_async` import with native async stream collection. The helper awaits source closure and service disposal, which flushes pending batches, and collects the entire output stream. All existing test cases and assertions are preserved; delivery tests now await the helper. This test-only repair is necessary because the task explicitly requires the test file to contain no `package:fake_async` reference. The existing implementation from earlier attempts was unchanged.

Verification: the exact no-`fake_async` grep gate passed; formatting and `git diff --check` passed. Wrapped targeted analysis of the seven listed test and implementation paths passed with `--no-fatal-infos` (7 infos, no errors or warnings). Analysis used the installed compiled Flutter tool and `--no-pub` because the SDK launcher writes to a read-only cache and dependency resolution needs unavailable network access. Wrapped realtime tests could not load: the standard launcher failed writing `engine.stamp`, and the compiled-tool attempt failed binding `127.0.0.1` (`Operation not permitted`). Runtime test count: 0; the apply wire test was not rerun after this environment block. Wrapped custom lints were also blocked during analyzer-plugin setup: `dart pub upgrade` could not reach `pub.dev`, so no lint-baseline result is claimed. Alloy must rerun runtime and lint verification in its permitted environment. No commits or full suites were run.

## UNIT U19 — partial — 2026-10-08 (tentura-s7gl.20, verification-record repair)

**Implementation and prior verification.** The existing schema, generated apply operation, direct V2 routing, repository/result mapping, realtime field kind and revision decoding were retained. Alloy's supplied verdict for attempt 4 records subsequent successful targeted runtime tests, analyzer-baseline verification and codegen checks; these supersede the preceding entry's runtime block for that verified run. They are prior Alloy results, not new runs in this iteration, and the supplied verdict does not give test counts. Tests edited in this iteration: **none**. No implementation, baseline or assertion changes were made, and no task-tracking commands or git mutations were run.

**Required custom-lint run.** Ran `./scripts/run_with_test_cleanup.sh --timeout 15m -- ./scripts/check-custom-lints.sh packages/client` serially. The normal launcher failed on the read-only Flutter SDK cache. Retrying with the installed Dart binary reached analysis but failed writing analytics state. A final wrapped run with analytics suppressed and a temporary writable analyzer cache exited **0**, reporting **2085** analyzer issues (the checked-in analyzer baseline is **2085**) and **0** custom violations against baseline **24**. However, its log also reports `An error occurred while executing an analyzer plugin` and a failed `dart pub upgrade` because `pub.dev` is unreachable. The plugin did not initialize, so that exit code and zero count are **not successful custom-rule verification**. The baseline was not changed. Log: `/tmp/tentura-u19-custom-lints-offline.log`. `git diff --check` passed.

**Blocking defect and remaining limit.** `scripts/check-custom-lints.sh:70` checks only the analyzer exit status, then counts matching diagnostics; a nonfatal plugin-setup failure consequently produces a false successful zero count. This existing verification-script defect is outside U19 and was not fixed or worked around. Work stopped under the task's out-of-scope-defect rule. Alloy must obtain a genuine wrapped custom-lint result with the plugin loaded in its permitted environment before marking this verification complete; no new runtime or codegen pass is claimed here. No full suite or commits were run.


## UNIT U20 — partial — 2026-10-08 (tentura-s7gl.21)

**Changed.** Added Freezed `PlacementOp` (upsert/delete), `PlacementSlot`, `PlacementTargetState`, and `PlacementOutboxState` in `domain/entity/placement_outbox.dart`. Added the pure `desiredAnchorProjection` overlay in `domain/placement_overlay.dart`: latest pending intent wins over in-flight intent, unresolved upserts/deletes overlay confirmed anchors, and server revision plus authorized projection records are preserved. The separate unsaved target set considers both slots and covers rejected intent, commit uncertainty with attempts >= 3, and in-flight duration strictly greater than one second.

**Timing contract.** `PlacementSlot.inFlightSince` is an optional dispatch timestamp, absent before dispatch. Projection receives a required `now` value rather than reading a clock; an in-flight slot without a timestamp has no elapsed-time cue. This supplies the fake-clock timing contract exercised by the existing task tests without introducing Flutter or I/O into domain code.

**Verification.** Ran the required wrapped entity-test command; the Flutter launcher failed writing to the read-only SDK cache. A wrapped serial retry using the installed Flutter tool snapshot reached both task test files but failed before executing tests because the sandbox rejects the localhost server socket required by `FlutterTesterTestDevice.start` (errno 1). Tests passed: **0; not executed**, not an assertion failure. Wrapped filtered build_runner codegen succeeded, writing the Freezed output; generated files were not edited by hand. Formatting and `git diff --check` passed. Wrapped custom-lint checks reached analysis and reported **2085 issues**, matching the client baseline, with no diagnostics in either new source file, but failed because analyzer-plugin setup cannot reach `pub.dev`. Retrying with the existing local plugin cache had the same setup failure; custom-rule verification remains blocked. Logs: `/tmp/tentura-u20-lints.log`, `/tmp/tentura-u20-lints-cached.log`. Analyzer-baseline gate result is recorded below after its run.

**Handoff.** Implementation is ready for Alloy to run the two focused tests and lint verification in an environment with the required permissions. Tests edited: **none**. No full test suite, task-tracking commands, or git mutations were run; Alloy owns those steps.

**Analyzer-baseline gate.** The wrapped `check-analyze-baseline.sh packages/client` invocation failed before analysis (exit 69): Flutter attempted dependency resolution and could not reach `pub.dev`. Log: `/tmp/tentura-u20-analysis.log`. The separate completed analysis in the custom-lint runs reported 2085 issues, but this does not establish a successful baseline-gate or custom-plugin run. These verification limits remain for Alloy.


## UNIT U21 — complete (part 1/3: placement core) — 2026-10-08 (tentura-s7gl.22)

**Changed files.** `packages/client/lib/features/constellation/domain/use_case/constellation_placement_case.dart` adds `ConstellationPlacementCase`: `place` and `unpin`, per-target in-flight/latest-pending slots, a single-request flush loop, and batches capped at 64 operations cut only at cluster boundaries. Unsent superseded targets are removed from older clusters. Acknowledgements settle by `clientOpId` through `ConstellationFieldStoreCase.settle`, which publishes the confirmed projection after slot settlement without an ANCHORS fetch; the store change is in `packages/client/lib/features/constellation/domain/use_case/constellation_field_store_case.dart`. `packages/client/test/features/constellation/constellation_placement_case_test.dart` covers one apply/zero ANCHORS reads, unpin, reordered acknowledgements, cluster boundaries above 64 queued operations, single-flight dispatch, and unsent supersession. This completion-record iteration changes only this journal and preserves the existing implementation and tests. Tests edited this iteration: **none**.

**Verification.** The supplied prior-attempt record reports five checks exiting **0** (two targeted, two lint, one regression), with acceptance confirmed by its judge; that record does not provide test counts or exact commands. This iteration reran the required placement test file through `scripts/run_with_test_cleanup.sh --timeout 5m`, using the cached Flutter tool snapshot, `--no-pub`, `ENV=test`, and `env/test.env`. It exited **1** before executing any tests: Flutter could not bind its test-server socket at `127.0.0.1` (`Operation not permitted`, errno 1). Current-run test count: **0 executed**, so the earlier passing results are reported as supplied evidence, not independently reproduced here. `git diff --check` passed after the journal append. No full suite or new lint run was performed for this documentation-only iteration.

**Deferred / handoff.** Part 2 owns commitUnknown retry/backoff through `WakeUpPort`, reconnect jitter, promotion rules, and account-generation stale-response handling. Part 3 owns deleting the write half of `ConstellationAnchorCase`. The current core records transport failures as commitUnknown but does not claim the deferred retry/lifetime behavior. Alloy must rerun the targeted check in an environment allowing Flutter's localhost socket and owns full verification, task tracking, and git. No commit or task-tracking command was run, per the task's executor override.

## UNIT U21 — blocked — 2026-10-08 (tentura-s7gl.22, codegen-check repair)

**Preserved implementation.** No implementation or test changes were needed or made in this iteration. The existing placement core, atomic store settlement, behavioral tests, and part 2–3 deferrals above remain intact. Tests edited this iteration: **none**.

**Required check blocker.** Before codegen, `git diff --quiet` already exited **1** for exactly the four intended U21 files: the journal, field store, placement case, and placement tests. No generated Dart files are tracked. Consequently, the supplied unqualified `git diff --exit-code` rejects the required implementation and journal edits themselves; it cannot pass in this unstaged checkout while preserving the task diff. Staging, committing, or discarding that diff would violate the executor override assigning git to Alloy. The check was not changed, bypassed, or weakened.

**Verification this iteration.** The literal wrapped `dart run build_runner build -d && git diff --exit-code` check exited **1** before generation because the Flutter launcher could not write its read-only SDK cache (`engine.stamp.tmp` / `engine.realm`); log: `/tmp/tentura-u21-codegen-check.log`. A separate wrapped invocation through the cached Dart binary exited **1** during dependency resolution because `pub.dev` was unreachable; log: `/tmp/tentura-u21-codegen-cached.log`. SHA-256 comparisons confirmed neither attempt changed any of the four tracked source files. The exact cached-tool placement-test command exited **1** while binding its localhost test-server socket (`Operation not permitted`, errno 1), with **0 tests executed**; log: `/tmp/tentura-u21-placement-check.log`. No successful codegen or runtime verification is claimed for this iteration. No full suite, task-tracking commands, staging, or commits were run.

**Handoff.** Alloy must establish the validation baseline through its own git workflow and rerun the unmodified codegen check with SDK-cache/network access, then rerun the focused placement test with localhost sockets permitted. This iteration changes only this verification record.


## UNIT U43 — partial — 2026-10-08 (tentura-s7gl.44, part 1/3 complete)

Global `constellation_field` markers with empty recipients now advance an isolate-local dirty generation. Broadcasts coalesce for `CONSTELLATION_FIELD_BROADCAST_WINDOW_SECONDS` (default 30 seconds), send payload-free hints to every authenticated socket, and yield after batches of 100 sockets. Markers arriving during a broadcast remain dirty for the next window; router disposal cancels pending work. Explicit-recipient hints retain their existing behavior.

Verification: the supplied cached-runner check passed both added tests; the complete relevant websocket protocol file passed all 40 tests, both through the cleanup wrapper with a 3-minute timeout. Custom-lint and analyzer-baseline checks were attempted serially but exited 1 because plugin setup could not reach pub.dev and Dart telemetry attempted to write a read-only SDK user-state file. Analyzer output contained no new diagnostics in the changed implementation paths (the existing recipient-loop `prefer_foreach` diagnostic moved to line 133); the analyzer baseline gate was not established. `git diff --check` passed. Tests edited: none. Server single-flight, DB scheduling/admission, full-suite verification and git operations remain with the later units/Alloy.

Analyzer-gate repair: recipient session collection now uses `Set.addAll`, and the hierarchy query's constant validation exception uses `const`. These behavior-preserving implementation changes remove two analyzer infos without editing tests or raising the baseline. The wrapped server analyzer-baseline gate passed at 1876 unique issues (baseline 1876), using the cached Dart SDK with `--suppress-analytics` to avoid read-only launcher-cache and telemetry writes; log: `/tmp/tentura-u43-analyze-fixed.log`. The supplied focused cached-runner command passed both broadcast tests again; log: `/tmp/tentura-u43-tests-repair.log`. The serial wrapped custom-lint check exited 1 because analyzer plugin setup could not reach pub.dev; log: `/tmp/tentura-u43-custom-lints-repair.log`. `git diff --check` passed. Tests edited: none.

Perf-tag regression repair: corrected the missing `mr` isolation tag and its comment in `test/perf/anchor_notification_triggers_perf_pg_test.dart`. The failing exclusion guard requires `perf`, `pg`, and `mr` so timing-sensitive suites stay out of ordinary PG runs; this was incorrect test metadata, and no assertions were changed. The perf runner still selects the Postgres-only phase from the fixture's `createPgmer2Extension` requirement. The two relevant perf guard/runner files passed all 37 tests through the cleanup wrapper (log: `/tmp/tentura-u43-perf-tag-repair-ci.log`). Verification used the cached SDK, refreshed dependency metadata offline without changing the lockfile, and set `CI=true` to suppress Dart telemetry writes to the read-only home directory. The supplied broadcast acceptance command passed both tests again (log: `/tmp/tentura-u43-broadcast-tag-regression.log`). Formatting and `git diff --check` passed. Tests edited: `packages/server/test/perf/anchor_notification_triggers_perf_pg_test.dart` (tag and comment only). Full-suite verification and git operations remain with Alloy.
