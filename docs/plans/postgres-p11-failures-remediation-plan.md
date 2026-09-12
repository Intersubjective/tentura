# P11 PostgreSQL failure remediation plan

## Objective

Make the P11 PostgreSQL release gate pass without weakening production
authorization, migration history, or test isolation. The baseline is the valid
isolated run recorded in
[`constellation-pinning-implementation-journal.md`](constellation-pinning-implementation-journal.md):

```text
(cd packages/server && POSTGRES_DBNAME=<unique-disposable-db> dart test -t pg -j 1)
639 passed, 0 skipped, 30 failed
```

This plan fixes the remaining server runtime and harness debt exposed by that
run. Historical upgrade suites are disabled for the planned schema squash
cutover and are outside this remediation scope. This plan does not change
Constellation contracts, activate C8, bump a client version, or start P12. No
remaining failure is to be dismissed as infrastructure until its focused,
isolated reproduction has been recorded.

## Execution rules

- Use a fresh, uniquely named disposable PostgreSQL database for every focused
  packet and the final suite. Create the database, enable `pgmer2`, set
  `check_function_bodies = false` where the existing migration fixtures require
  it, apply migrations, and prove `SELECT current_database()` is the target.
- Load `.env` with the line-by-line export loop from
  `scripts/run-server-local.sh`; do not `source` it and do not print values.
  Export `POSTGRES_DBNAME` for the migration command **and** the `dart test`
  process itself.
- Run one heavy command at a time. Every PostgreSQL command uses `-j 1`; do not
  run browser, Hasura, code generation, or another test process concurrently.
- Before and after every worker, inspect task-owned Dart, analyzer, Flutter,
  test-driver, Chrome, and Cursor processes. Preserve pre-existing services and
  only terminate a task-owned process that is demonstrably stuck.
- Keep each coherent repair in a focused commit after its focused tests pass.
  Do not edit generated files. If a migration source changes, regenerate with
  `dart run build_runner build -d` in `packages/server` before its commit.

## Failure inventory and fixed ownership

| Track | Failing cases | Count | Current evidence |
|---|---|---:|---|
| Evaluation and capability behavior | `review_finalization_outcome_evidence_pg_test.dart`, `forward_band_witness_admission_integration_pg_test.dart`, `evaluation_repository_submit_atomic_pg_test.dart` | 5 | Outcome ledger 0 instead of 3; no Tier-B row; ack-tag row 0 instead of 1 |
| Authorization and deletion behavior | `beacon_hierarchy_visibility_pg_test.dart`, `user_block_repository_pg_test.dart` | 2 | Null assertion where authorization exception is required; owner/deleted Beacon constraint on user deletion |
| Disposable-database migration races | `attention_retention_pg_test.dart`, `obligation_scope_coincidence_pg_test.dart`, `forward_candidate_context_repository_pg_test.dart`, `beacon_threads_repository_pg_test.dart` | 7 | Four `migrant_db_postgresql` `RaceCondition` setup failures and dependent teardown failures |
| Hasura parity harness | `beacon_hierarchy_hasura_parity_test.dart` | 1 | Child-content authorization request times out after 30 seconds |

The counts total 15. Constellation anchor storage, field, participation, and
GraphQL PostgreSQL paths had no error in the valid run and are regression gates,
not repair targets.

## R01 — Establish focused reproduction commands and failure contracts

**Files:** `docs/plans/postgres-p11-failures-remediation-plan.md` (this plan),
`docs/plans/constellation-pinning-implementation-journal.md`; no production
source changes.

1. Build a reusable shell invocation outside the repository that follows the
   execution rules above. It must retain the complete test log and record only
   the disposable database name, not credentials.
2. Re-run each of the 10 remaining failing test files individually, serially, with
   `--chain-stack-traces`. Record the first production frame, the failing SQL
   object or assertion, and whether failure persists on a second fresh database.
3. Freeze one acceptance assertion per case before editing: outcome row count,
   authorization exception, successful Hasura response, or a completed
   disposable migration. Never replace an assertion with a broader
   `isEmpty`, timeout, or catch-all exception expectation.

**Exit gate:** every failure has a reproducible focused command and a named
owner below. A focused test that becomes green without a source change is marked
flaky and is still handled by R04/R05; it is not removed from the final gate.

## R02 — Repair evaluation and capability behavior without relaxing contracts

**Files:**

- `packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart`
- `packages/server/lib/data/repository/evaluation_repository.dart`
- `packages/server/lib/data/repository/capability_evidence_repository.dart`
- `packages/server/lib/domain/use_case/forward_band_case.dart`
- `packages/server/lib/data/repository/band_candidate_repository.dart`
- the three focused test files in the inventory

1. Trace `ReviewFinalizationCase.closeAndFinalize` from completed review through
   evaluation persistence, outcome-evidence generation, and the capability
   ledger. Establish whether the three zero-ledger failures expose a missing
   production write or a fixture that no longer satisfies the completed-review
   prerequisites. Preserve all C2 rules: non-positive values emit nothing,
   forwarder evaluations are excluded, cap ordering is deterministic, reruns
   are idempotent, and multiple observers do not nest mutating-user transactions.
2. Trace `EvaluationRepository.submitEvaluationAtomic` through the
   `beacon_evaluation_ack_tag` write. Reconcile the repository API's row-status
   contract with the test's first-submit input. Fix the transaction or the
   fixture based on the real contract; one successful first submit must leave
   the expected evaluation and ack-tag rows atomically, while updates retain
   the established replacement semantics.
3. Trace the witness-admission test from normal visibility through
   `BandCandidateRepository.candidatesFor`, `ForwardBandCase`, witness-window
   admission, capability projection, and Tier-B composition. If the fixture is
   missing a now-required admission/commitment/window fact, seed it through the
   canonical workflow. If a valid admitted witness is filtered by production
   code, repair the narrow predicate. Do not weaken block, rejection, withdrawn
   offer, already-forwarded, or content-read gates to make the test pass.
4. Add a regression assertion at each repaired boundary so zero ledger rows,
   empty Tier-B output, or missing ack tags cannot recur silently.

**Focused verification:** run these three test files serially after every
coherent fix, then run `./scripts/check-custom-lints.sh packages/server` before
committing runtime changes.

## R03 — Restore authorization and deletion error semantics

**Files:**

- `packages/server/lib/domain/use_case/help_offer_case.dart`
- `packages/server/test/data/repository/beacon_hierarchy_visibility_pg_test.dart`
- `packages/server/test/data/repository/user_block_repository_pg_test.dart`
- the production deletion/cascade source proven by the focused investigation

1. Reproduce the hierarchy-only viewer calls to `offerHelp` and `withdraw`.
   At `help_offer_case.dart` line 63, replace the null-assertion path only after
   identifying the missing repository value. A viewer without child content
   access must receive the documented `UnauthorizedException`; the repair must
   not disclose child data or change hierarchy access rules.
2. Reproduce the blocked-user deletion in the user-block test on a fresh
   database. Decide from the account-erasure/deletion contract whether the test
   seeds an impossible Beacon row or production deletion leaves an invalid
   owner reference. Fix the fixture when it is invalid; otherwise repair the
   single cascade/delete transition so `beacon_owner_or_deleted_ck` remains
   true throughout the transaction.
3. Test both permitted and denied paths, including rollback after an injected
   failure. Do not disable the constraint or replace the authorization exception
   with a generic failure.

**Focused verification:** the two files individually, then together serially.

## R04 — Eliminate disposable-database migration races at the harness boundary

**Files:**

- `packages/server/test/data/repository/attention_retention_pg_test.dart`
- `packages/server/test/data/repository/obligation_scope_coincidence_pg_test.dart`
- `packages/server/test/data/repository/forward_candidate_context_repository_pg_test.dart`
- `packages/server/test/data/repository/beacon_threads_repository_pg_test.dart`
- a new `packages/server/test/support/` helper only if the four focused
  reproductions prove the duplicated target lifecycle is the common cause

1. Use R01's chain-stack traces to identify the exact migration statement that
   raises `migrant_db_postgresql` `RaceCondition`. Confirm the target database
   names are distinct and no connection remains before `DROP DATABASE`; inspect
   `schema_version` and active sessions instead of adding blind retries.
2. If the four tests share lifecycle duplication, extract a test-only helper
   that validates database-name format, serializes one recreate/migrate/drop
   lifecycle, closes Drift and raw PostgreSQL connections in a deterministic
   order, and reports a clear setup failure. Do not create a global production
   migration retry policy.
3. If the race is a non-idempotent migration statement, repair that migration's
   transactional/idempotence behavior and add a migration-level regression
   test. Do not catch `RaceCondition` and proceed with a partially migrated
   database.
4. Make teardown conditional on successful setup so a failed `setUpAll` cannot
   hide the primary failure with `LateInitializationError`.

**Focused verification:** each file twice against separate disposable databases,
then all four in one serial command. The second run is required to prove the
race is gone.

## R05 — Make Hasura parity target the same isolated state

**Files:**

- `packages/server/test/api/beacon_hierarchy_hasura_parity_test.dart`
- existing Hasura test/startup helper or `scripts/hasura_apply_metadata.sh` only
  if its current interface can select a disposable database without exposing
  credentials

1. Prove which PostgreSQL database Hasura reads during the test and compare it
   with the disposable database seeded by the test. Record endpoint and database
   identity without printing secrets.
2. Make the test provision metadata and its JWT-compatible data source against
   that same disposable database, or give the parity harness its own isolated
   Hasura instance. Reuse the repository's existing metadata workflow; do not
   point a disposable test at the user’s long-running Hasura database.
3. Keep the current 30-second timeout. A timeout increase is not a fix. The
   failure must become a completed GraphQL response that proves a hierarchy-only
   JWT cannot read the child Beacon's content row or listing.
4. Tear down only the Hasura process/database created by the test and audit for
   dangling task-owned processes.

**Focused verification:** run this one test with its explicit Hasura setup twice
serially. Record both HTTP response body shape and clean teardown evidence.

## R06 — Integrate and re-open P11 only with complete evidence

1. Run the evaluation/capability group, authorization/deletion group, race
   group, and Hasura parity test serially.
   Fix any cross-group failure through the packet that owns its contract.
2. Run `./scripts/check-custom-lints.sh packages/server` after the last server
   source change. Run server code generation only if a migration/table/DI input
   changed; inspect generated output without editing or committing it.
3. Create a fresh unique PostgreSQL database, apply all migrations, prove
   `current_database()`, and run the complete `dart test -t pg -j 1` suite with
   that database explicitly exported to the test process. The gate is green
   only with zero failures and zero unexplained skips.
4. Repeat process cleanup/audit. Append exact commands, database proof, test
   totals, commits, and any blocked browser hardware coverage to the Constellation
   implementation journal.
5. Only after R07 is green may a separate P11 packet perform C8 versioning and
   the versioned web-artifact verification; only after that packet is accepted
   may P12 begin.

## Commit sequence

1. `fix(server): restore evaluation and capability evidence contracts`
2. `fix(server): preserve authorization and deletion invariants`
3. `test(server): stabilize disposable postgres migration lifecycle`
4. `test(server): isolate Hasura hierarchy parity`
5. `docs: record P11 PostgreSQL remediation acceptance`

Each subject is conditional on the corresponding packet passing; do not create
empty commits merely to match the list.
