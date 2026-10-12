# DB pipeline baseline: queue time vs SQL time (tentura-ev3z.8)

Baseline for step 1 of
[server-db-concurrency-architecture-review.md §7](../plans/server-db-concurrency-architecture-review.md):
how much of a request's time is spent waiting (admission + pool acquire) and
how much in SQL, read off the Sentry spans the server now emits. Later steps
(scoped DB access, one admission queue) are compared against these numbers.

Raw per-request rows: [`db-pipeline-baseline.json`](db-pipeline-baseline.json).

## Spans and tags

| Span `op` | Covers | Emitted by |
|---|---|---|
| `db.admission.wait` | `ConstellationDbScheduler.run` enqueue → admitted (or refused after the queue deadline: error status) | `constellation_db_scheduler.dart` |
| `db.pool.acquire` | wait for the pool connection, child of `db.transaction` | `tentura_db.dart` |
| `db.transaction` | outermost transaction, BEGIN → COMMIT/ROLLBACK (pin → unpin) | `db_pipeline_trace.dart` |
| `db.sql` | one statement (SQL text, never arguments), child of its transaction | `DbSpanInterceptor` |
| `db.retry.backoff` | sleep between attempts of `withPostgresBoundedRetry` | `postgres_serialization_retry.dart` |
| `db.cancel.drain` | after a server-cancelled (57014) statement until the connection is rolled back and released | `db_pipeline_trace.dart` |

Tags: `graphql.operation` (from the request), `work.class` (admission span:
`full` / `refresh` / `apply`), `isolate`, and `db.backend_pid` on
`db.transaction`. One V2 request therefore reads, in a Sentry trace, as
`db.admission.wait` → `db.transaction` { `db.pool.acquire`, `db.sql` … }.
`request_db_pipeline_trace_pg_test.dart` pins this shape against a real
Postgres for both the pinned-session and the per-transaction-lease modes.

## Method

`scripts/perf/db_pipeline_baseline.sh` (tool: `packages/server/tool/db_pipeline_baseline.dart`).

* **Dataset:** throwaway copy of `tentura_perfsynth` (3,348 users, 89,433
  trust edges, 14,245 Requests; ~1,000 visible peers per viewer), MeritRank
  reloaded for it (`mr_reset(); meritrank_init()`), copy dropped afterwards.
* **Code under test:** the production paths, in one isolate on one database,
  through the real `sentryRequestTracing` middleware (one trace per request):
  `ConstellationFieldCase` → `ConstellationFieldRepository` (FULL) via
  `ConstellationDbScheduler.fromEnv` (max 2 concurrent, 10 s queue deadline);
  `ConstellationAnchorRepository.applyBatch`; `SessionRepository` lookup on a
  second `TenturaDb`, as the `@Named('auth')` one. Not exercised: HTTP/GraphQL
  framing, Hasura, the publisher, LISTEN/NOTIFY.
* **Mixed load, 120 s per configuration:**
  * screen-open burst: 8 FULL reads for distinct viewers at once, every 15 s
    (64 reads over 40 dense viewers, so most are a viewer's first read);
  * anchor drags: 2 sessions, each 15 `applyBatch` calls 100 ms apart, then a
    1.5–3 s pause (~990 writes);
  * auth refresh: one session lookup every 500 ms (240).
* **Configurations:** `pinned-session` (flag off, 1 connection; the code's
  default) and `lease-pool-4` (`DRIFT_TRANSACTION_PINNED_POOL_ENABLED=true`,
  4 connections; dev's setting).
* **Metrics per request**, from its finished trace: *queue* = Σ
  `db.admission.wait` + Σ `db.pool.acquire`; *SQL* = Σ `db.sql`; *tx lifetime*
  = Σ `db.transaction`; *outside* = total − admission − tx lifetime (not in any
  span: Drift's executor-lock wait before BEGIN in pinned mode, plus handler
  non-DB work). Percentiles are per operation over requests (linear
  interpolation); p50/p95 of different columns are not additive.

## Result (2026-10-12, ms, p50 / p95)

Host: i5-12600K (16 threads), Postgres 17.11 and MeritRank in local Docker,
nothing else running.

### pinned-session (1 connection)

| Operation | n | total | queue | admission | acquire | outside | SQL | of which visible-set SQL | tx lifetime | stmts |
|---|---|---|---|---|---|---|---|---|---|---|
| ConstellationField (FULL) | 64 | 286.1 / 1853.9 | 177.8 / 1342.0 | 174.0 / 1341.4 | 0.4 / 7.1 | 13.6 / 76.7 | 59.5 / 125.0 | 14.1 / 77.2 | 64.1 / 118.2 | 14 / 14 |
| ConstellationAnchorsApply | 994 | 6.9 / 39.9 | 0.8 / 2.3 | 0.1 / 0.2 | 0.7 / 1.9 | 0.3 / 0.8 | 3.7 / 14.9 | 0 | 6.5 / 29.4 | 8 / 8 |
| AuthRefresh (auth DB) | 240 | 2.7 / 8.8 | 0.7 / 2.0 | 0 | 0.7 / 2.0 | 0.3 / 0.8 | 0.7 / 2.4 | 0 | 2.4 / 8.0 | 1 / 1 |

### lease-pool-4 (4 connections)

| Operation | n | total | queue | admission | acquire | outside | SQL | of which visible-set SQL | tx lifetime | stmts |
|---|---|---|---|---|---|---|---|---|---|---|
| ConstellationField (FULL) | 64 | 152.9 / 231.7 | 102.0 / 176.0 | 102.0 / 176.0 | 0.1 / 0.2 | 1.4 / 2.6 | 52.1 / 63.1 | 2.5 / 5.7 | 52.5 / 72.1 | 14 / 14 |
| ConstellationAnchorsApply | 989 | 5.0 / 22.2 | 0.2 / 0.5 | 0.0 / 0.1 | 0.2 / 0.4 | 0.2 / 0.5 | 2.8 / 12.7 | 0 | 4.8 / 21.5 | 7 / 8 |
| AuthRefresh (auth DB) | 240 | 2.3 / 7.6 | 0.2 / 0.4 | 0 | 0.2 / 0.4 | 0.2 / 0.6 | 0.7 / 2.5 | 0 | 2.1 / 7.0 | 1 / 1 |

No request was refused (queue deadline never hit), none failed.

### Reading

* A FULL read is queue-bound, not SQL-bound: admission wait is 62 % of its p50
  (178 of 286 ms) and 72 % of its p95 (1,342 of 1,854 ms) with one connection,
  against ~52–60 ms of SQL. Four connections cut p95 total from 1.85 s to
  0.23 s; the 8-wide burst still waits behind the scheduler's 2 concurrent
  slots (admission p50 102 ms), so that limit, not the pool, is what remains.
* Pool acquire is negligible in both modes for this load (p95 ≤ 7.1 ms): the
  waiting happens in admission, and — in pinned mode — in the executor lock
  (`outside`: FULL p50 13.6 / p95 76.7 ms against 1.4 / 2.6 with the pool).
  That lock wait has no span of its own yet; it is visible only as the gap.
* Anchor writes and auth refresh are SQL-dominated and short (p95 ≤ 40 ms);
  anchor p95 total is 40 → 22 ms with the pool.
* The visible-set SQL (MeritRank RPC) is cheap here (p50 14 / 2.5 ms): the
  MeritRank service already held the graph and its per-viewer frames warm
  after the first read. This run says nothing about cold or restarted MR.

## Caveats

* One isolate, one process, loopback Postgres on a fast desktop CPU; the dev
  host has 2 vCPU. Absolute numbers will not transfer, the queue/SQL split and
  the pinned vs. pool ratios are the baseline.
* Synthetic bursts of 8 at a fixed cadence, not a recorded production mix. n
  is 64 for FULL, so its p95 is the 4th-worst sample: treat it as ±30 %.
* An earlier run of the same tool (before the `outside` column existed) gave
  the same picture: FULL p95 total 1,862 ms pinned / 238 ms pool (here 1,854 /
  232), anchor p95 63 / 22 ms (here 40 / 22), so run-to-run spread on p95 is
  well above 1 % for the writes in pinned mode.
* The Sentry spans themselves cost a few clock reads and, per traced transaction,
  one `SELECT pg_backend_pid()` round trip (per pin in pinned mode) that is
  not part of any span; it is in `total`.
* Not measured (matrix items left for later steps): warm/cold MR epoch
  publication, external row lock, slow/unavailable MR, client abort, 2 web
  isolates, publisher and Hasura reads.
