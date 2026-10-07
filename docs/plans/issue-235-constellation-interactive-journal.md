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
