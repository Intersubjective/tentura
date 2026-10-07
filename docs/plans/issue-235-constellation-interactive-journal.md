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
