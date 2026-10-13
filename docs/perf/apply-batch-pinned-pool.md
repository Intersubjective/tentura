# applyBatch with the pinned pool flag on (tentura-ev3z.21)

Measured 2026-10-13 on the local machine, disposable pg target, 1000 visible
users, dense trust, warm, 30 attempts per case. Test:
`packages/server/test/perf/constellation_apply_batch_scoped_pool_report_pg_test.dart`
(budget variant: `constellation_apply_batch_scoped_pool_budgets_pg_test.dart`).
The case runs through the production scoped `MainDbPool` with capacity 4, as
dev runs it (`DRIFT_TRANSACTION_PINNED_POOL_ENABLED=true`, `POSTGRES_MAXCONN=4`).

| batch | latency p50 | latency p95 | budget |
|-------|-------------|-------------|--------|
| 1-op  | 9.2 ms      | 44.6 ms     | p50 30 ms |
| 64-op | 15.9 ms     | 55.4 ms     | p95 100 ms |

## poolDiagnostics (ms)

| batch | lease wait p50/p95/max | admission wait p50/p95/max | lane busy p50/p95/max |
|-------|------------------------|----------------------------|-----------------------|
| 1-op  | 0.18 / 0.79 / 33.5     | 0 / 0 / 0                  | 8.9 / 29.1 / 43.5     |
| 64-op | 0.15 / 0.65 / 26.8     | 0 / 0 / 0                  | 15.4 / 54.0 / 58.6    |

Dominant cause: `serialised-lane`. Lane time is the work itself (cursor hold
6 / 14 ms p50); lease and admission waits are negligible, so there is no
queueing at the pool.

## Does the ~25x slowdown reproduce?

Not on the current scoped `MainDbPool`: both cases meet the same budgets as
the raw-pool test with the flag on and MAXCONN=4. The earlier 753 ms / 630 ms
figures came from the pre-scoped pinned-pool path; that was replaced by scoped
main-DB access (e02023617 and the follow-ups ev3z.22/.23), which removed the
slowdown. I did not measure the old path again, so that attribution rests on
the change history, not on a fresh A/B. No decision to turn the flag off on dev
is needed from this data. Dev should still be spot-checked after deploy, since
this measurement is local and on an idle machine.
