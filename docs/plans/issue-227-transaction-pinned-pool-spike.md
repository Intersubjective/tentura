# Issue #227 spike: transaction-pinned Drift pool (WORKAROUNDS §4)

Status: spike / experimental prototype. No production switch.

## Design

Drift issues BEGIN / COMMIT / SAVEPOINT / RELEASE as ordinary
`session.execute()` calls through its `QueryExecutor`, and `Pool.execute`
returns the pooled connection after every statement. With
`maxConnectionCount > 1` a nested `RELEASE SAVEPOINT` or `ROLLBACK TO SAVEPOINT`
can land on a different backend and raise Postgres `25P01`
(no active transaction). The workaround is `maxConnectionCount: 1`.

The prototype opt-in is `Env.driftTransactionPinnedPoolEnabled`, read from
`DRIFT_TRANSACTION_PINNED_POOL_ENABLED`. It is default off (false). Only when
it is true does `pgPoolSettings` honor `POSTGRES_MAXCONN`
(`pgMaxConnectionCount`) instead of forcing one connection, and only then does
`TenturaDb` select `_TransactionPinnedPgDatabase`, a Drift `DelegatedDatabase`
whose `SupportedTransactionDelegate` leases one pooled connection per
transaction (`Pool.withConnection` + `Connection.runTx`, i.e. COMMIT and
ROLLBACK run on the leased backend). Nested transactions run as savepoints
(`SAVEPOINT` / `RELEASE` / `ROLLBACK TO`) on that same lease, and statements
outside a transaction keep using the ordinary pool. With the flag off the
existing `_PinnedPoolSession` path is unchanged.

## Risks

- Nested transactions: every nested savepoint must reuse the outer lease; a
  lease released early reproduces 25P01.
- Zone-based mutating-user context: `TenturaDb.withMutatingUser` stores the
  actor in a zone and sets a GUC on the leased session. Zones that escape the
  transaction would run on an unpinned connection with no actor; the actor GUC
  must be cleared on rollback so a reused session never leaks it.
- LISTEN connection: LISTEN/NOTIFY needs a dedicated, separate long-lived
  connection outside the pool; it must never be a pooled lease.
- Limitation: pool exhaustion if transactions hold leases while awaiting
  other pooled queries (a hazard under a small `maxConnectionCount`).

## Test results

- `test/transaction_pinned_pool_env_test.dart`: Env default off, explicit
  true honors capacity, `DRIFT_TRANSACTION_PINNED_POOL_ENABLED` read in a
  fresh process: passed.
- `test/data/database/transaction_pinned_pool_pg_test.dart` (all scenarios,
  also the runtime opt-in one with the env var set): passed. With the flag
  off and two connections (maxConnectionCount: 2, two-connections pool) the
  nested-savepoint scenario reproduces `25P01`; with the executor enabled
  the same scenario passes, as do 2 and 3 concurrent transactions that
  overlap on separate backends, each with its own `withMutatingUser` actor,
  and an outer rollback that clears writes and actor context.
- Side finding: `withMutatingUser` threw its actor-mismatch `StateError`
  synchronously; it is now `async` so the error arrives as a failed Future.

## Flag-off verification

With the flag off (the default) the pool stays at one connection, identical to
today. Full PG suite with the flag unset
(`run_with_test_cleanup.sh --timeout 30m -- dart test --tags pg --exclude-tags mr -j 1`):
`All tests passed!` (+1700, ~3 skipped), no failures and no flakes. The
nested-savepoint pg test reproduces 25P01 with the flag off (current executor,
`maxConnectionCount=2`) and passes with the flag on. The `mr`-tagged suite
carries unrelated schema drift (bead tentura-3dvk) and was not part of this run.

## Recommendation

No-go for enabling in production yet; go for further evaluation. The
prototype works in the scenarios above, but pool exhaustion under long
transactions, the dedicated LISTEN connection, and per-statement
`statement_timeout` behavior need load testing before any switch.
