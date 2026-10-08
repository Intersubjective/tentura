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
