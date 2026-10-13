# Scoped main-DB self-deadlock audit (2026-10-13)

Source: a read-only codex gpt-6.1-sol (high) audit after the hang in `openForwarding`, which e02023617 introduced and 3e2eb8b82 fixed. Root cause of that hang: each repository had its own `TenturaDb.scoped(pool)` handle, and Drift matches a zone transaction only to the instance that opened it, so a savepoint opened by handle B was invisible to handle A. Line references are as of e02023617.

Read-only audit completed. No files modified or tests run. Database-core references below use **commit `e02023617`**, because `tentura_db.dart` changed during the audit.

**The largest exposure is reachable nested savepoints combined with separate `TenturaDb` handles sharing one pool.** The nesting sites below are verified; additional hangs are inferred from the reported executor-routing failure, not reproduced here.

## A. Ranked findings

### 1. High — active operations open savepoints inside an existing transaction

Drift 2.34.3’s statement-based transaction executor holds the **parent executor’s lock until the child transaction finishes**. If a statement in the child resolves to that parent, the child waits for a lock that it must itself release.

Also, **`requireNew: false` does not mean “join the existing transaction”** when the executor supports nested transactions: Drift still opens a savepoint.

These are the active compositions I found:

| Boundary | Reachable call path and likelihood | Fix |
|---|---|---|
| [beacon_repository.dart:789](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/beacon_repository.dart:789), also `:832` | `publishDraft` and `publishChildDraft` explicitly nest `withTransaction` inside `withMutatingUser`. They create savepoints even when called standalone. Root publication is also wrapped by `BeaconCase` at `:341`; child publication by `BeaconChildCreateCase` at `:303`. **High exposure.** | Remove the redundant inner boundary. Keep one actor mutation transaction. |
| [beacon_repository.dart:698](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/beacon_repository.dart:698) | `recordBeaconStatusTransition` opens a transaction inside cancellation, deletion, closure, reopening and erasure transactions. In particular, closure finalization reaches it from the worker. **High exposure across several features.** | Provide an explicitly transaction-bound implementation; standalone callers can use a joining wrapper. |
| [inbox_repository.dart:159](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/inbox_repository.dart:159) | `ForwardCase.cancel` opens `runAction` at `:121`, then calls `markForwardCancelledForRecipient` at `:134`. Its first inner statement sets a transaction-local GUC. **High exposure whenever an eligible forward is cancelled.** | Join the existing transaction; retain the GUC and update in that transaction. |
| [user_block_repository.dart:36](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/user_block_repository.dart:36), also `:105`, `:173` | Block, unblock and promotion-to-direct are called inside `UserBlockCase` units of work at `:88`, `:116`, `:134`. Each repository method opens another boundary. **High exposure.** | Separate transaction-bound bodies from standalone entry points; join for these use-case calls. |
| [user_repository.dart:211](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/user_repository.dart:211), also `:385`, `:907` | Invited signup is wrapped by `AuthCase` at `:166` or `CredentialAuthCase` at `:156`; the repository opens another transaction. Existing-account invite acceptance wraps `bindMutual` through `InvitationCase._acceptAndRecord` at `:388`. **High exposure on invite acceptance.** | Join the caller’s unit of work while preserving atomic invitation claiming and account creation. |
| [beacon_hierarchy_command_repository.dart:376](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/beacon_hierarchy_command_repository.dart:376) | `markPromotionPublished` is called at `BeaconChildCreateCase:711` inside child publication. **Conditional exposure: promotion publication.** | This boundary has a reason to remain: conflict handling needs recovery from a failed SQL statement. Use an **explicit savepoint API**, with verified inner-executor routing, rather than removing recovery semantics. |

The same explicit double nesting exists in [coordination_item_repository.dart:49](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/coordination_item_repository.dart:49), `:115`, `:159`, `:202`, `:381`, `:503`, `:622`: create, status update, accept, redirect, draft publication, published-item update and blocker publication. **I found no active production mutation callers for these methods.** Treat them as dormant exposure; this does not justify enabling item threads.

### 2. High — many normal use cases depend on ambient mutation recognition

The shared entry is [mutating_unit_of_work.dart:20](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/mutating_unit_of_work.dart:20), `:22`, reached through [transactional_attention_case.dart:18](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/transactional_attention_case.dart:18).

The following compositions should join the ambient transaction. If ambient recognition is lost, they instead enter the incident’s unintended-savepoint path:

| Operation | Inner mutation boundary |
|---|---|
| Beacon updates, state callbacks, plan-copy duplication, deletion | [beacon_repository.dart:219](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/beacon_repository.dart:219), `:338`, `:440`, `:506`, `:566`, `:577` |
| Forward delivery; forwarding nested inside Post publication | [forward_edge_repository.dart:115](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/forward_edge_repository.dart:115). `PostCase:108` calls `ForwardCase.forward` at `:125`, which itself enters `runAction` at `ForwardCase:254`. |
| Help offering and withdrawal | [help_offer_case.dart:120](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/help_offer_case.dart:120), `:402` → `BeaconRepository:577`, `HelpOfferRepository:29`, `:63`, `CommitmentRepository:52` |
| Acceptance, decline, removal and commitment release | [coordination_repository.dart:139](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/coordination_repository.dart:139), `:169`, `:193` → further room mutation boundaries at `BeaconRoomRepository:1253`, `:1336` |
| Directed room messages, baton messages, reactions, current-line updates, steward promotion, message deletion/editing | [beacon_room_repository.dart:892](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/beacon_room_repository.dart:892), `:1202`, `:1365`, `:1391`, `:1416`, `:1448`, `:1659`, `:1682`, `:2061`, `:2087`, under `BeaconRoomCase`/`RoomBatonCase` transactions |
| Invite seed attestation | [invite_seed_attestation_case.dart:122](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/invite_seed_attestation_case.dart:122) → `CapabilityEvidenceRepository:215` |
| Reopening plan obligations | [plan_attention_case.dart:191](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/plan_attention_case.dart:191), called inside `ClosureCase`’s existing transaction at `:293` |

**Likelihood:** these are ordinary production paths, but nesting itself is valid when joining and executor routing work correctly.

**Fix:** make transaction identity **pool-scoped and executor-specific**, shared by all handles using that pool. Record the innermost executor explicitly. Actor, transaction ownership and isolation checks must use the same authoritative context. Establish a clear distinction between “join a unit of work” and “create a savepoint.”

### 3. High — direct-block cleanup enters the wrong actor scope

[ user_block_case.dart:88](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/user_block_case.dart:88) opens a unit of work as `blockerId`. Its cleanup processes offers in **both directions** at `:202` and `:206`.

For the blocked person’s offer, it then calls:

- [user_block_case.dart:227](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/user_block_case.dart:227): `CommitmentRepository.record(actorUserId: offererId)` without `mutatingUserId`.
- [user_block_case.dart:235](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/user_block_case.dart:235): `HelpOfferRepository.withdraw(userId: offererId)`, which opens a mutation as that offerer at `HelpOfferRepository:63`.

**Effect:** with ambient recognition working, this throws an actor-mismatch `StateError`. With recognition lost, it can open an unintended nested transaction and encounter the same routing hang.

**Likelihood:** concrete, reachable when the blocked person has an active offer on the blocker’s Request.

**Fix:** distinguish the historical event actor from the transaction’s initiating actor. Pass `mutatingUserId: blockerId` to commitment recording, and give withdrawal an explicit transaction-actor override or transaction-bound body. Preserve event attribution separately.

### 4. Medium — ad-hoc adapters amplify any root-handle routing fault

I found these repository constructions using an existing database handle:

- [beacon_repository.dart:593](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/beacon_repository.dart:593): `PostLockRepository`.
- [author_invite_repository.dart:113](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/author_invite_repository.dart:113), `:116`: Post and hierarchy lock repositories.
- [user_repository.dart:161](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/user_repository.dart:161): Post lock during invited signup.
- [closure_repository.dart:40](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/closure_repository.dart:40), `:57`, `:1212`: trust ledger, hierarchy lock and capability evidence repositories.
- [constellation_anchor_projection_reader.dart:45](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/constellation_anchor_projection_reader.dart:45), [constellation_field_snapshot_reader.dart:164](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/constellation_field_snapshot_reader.dart:164): field repositories inside an existing snapshot/mutation.
- [attention_capture_settlement_repository.dart:15](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_capture_settlement_repository.dart:15): sweep adapter.

**These constructions do not themselves create another pool.** Their safety depends on the supplied root handle resolving to the current transaction executor.

Lock adapters deserve particular attention: if misrouting acquires another connection, a row/advisory lock can wait for the caller’s own transaction. PostgreSQL sees a blocked second backend, while the application waits for it before committing the first.

**Likelihood:** active lock and closure paths; conditional on routing failure.

**Fix:** inject ports or shared lock primitives instead of constructing repositories to avoid DI ordering. Ensure those adapters accept the authoritative transaction-capable database facade. An ad-hoc-construction lint is useful, but fixing executor routing remains essential.

### 5. Medium — scheduler/admission re-entry can consume its own budget

[constellation_db_scheduler.dart:68](/home/vader/MY_SRC/tentura/packages/server/lib/data/service/constellation_db_scheduler.dart:68) uses `pool.admission`. Its `run` at `:86` takes an admission slot. A database scope then independently takes another at [tentura_db.dart:234](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/tentura_db.dart:234).

Consequences:

- Scheduler → DB scope can double-admit the same work.
- Existing DB scope → scheduler can wait for capacity already held by its caller.
- FULL → FULL on the shared admission cannot start because `maxHeavy` defaults to **1**, even if the pool has spare connections.
- At concurrency 1, any same-admission re-entry waits on itself.

**This is a bounded self-wait:** admission deadlines are 250 ms for interactive/refresh and 1 s for FULL. Pool acquisition is also normally bounded by `connectTimeout`; default pool size is 4. Neither explains an infinite executor-lock wait by itself.

**Likelihood:** latent in the compatibility API. I found no production `scheduler.run` callers; constellation repositories accept but ignore the scheduler parameter. Production pool-backed admission also does **not** enable the extra reserved interactive slot.

**Fix:** make the compatibility scheduler carry work metadata only, leaving admission to the connection scope; alternatively reuse an explicit admission ticket. Guard actual admission acquisition against same-admission re-entry.

### 6. Medium — worker lifecycle sweeps reach nested boundaries, but the worker does not hold a surrounding lease

[task_worker_case.dart:500](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/task_worker_case.dart:500) awaits tasks sequentially at `:505`; there is no worker-wide main-DB connection scope.

The significant exposure is:

[closure_finalize_sweep_case.dart:39](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/closure_finalize_sweep_case.dart:39) → `ClosureFinalizeCase.finalize` → [closure_finalize_case.dart:128](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/closure_finalize_case.dart:128) → `BeaconRepository.recordBeaconStatusTransition:698`, which creates a savepoint.

**Likelihood:** regular expiration work. A hang there stalls subsequent tasks in the sequential worker loop.

The other examined sweeps release candidate-query leases before per-item work. In particular:

- Bud anchor inheritance applies each viewer’s anchor separately, then marks completion.
- Attention capture settlement and trust publishing use `withWorkContext`, which holds **metadata, not a lease**.
- Capability-cell GC, block cascade/release, deadline and plan sweeps use bounded statements/transactions rather than an outer lease awaiting a fresh unit of work.

**Fix:** address the nested lifecycle boundary from finding 1 and add a worker regression covering finalization through the real ports.

### 7. Low/currently latent — transaction metadata has two gaps

**Isolation recognition:** [tentura_db.dart:364](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/tentura_db.dart:364) checks the mutating context before entering repeatable read. A plain `withTransaction`/Drift transaction has no such marker. [tentura_db.dart:406](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/tentura_db.dart:406) also enters a read snapshot without checking existing isolation/access mode.

With correct routing, incompatible nesting generally produces a PostgreSQL transaction-mode error; with broken routing it can hang before reaching that error. I found no active production path nesting anchor repeatable-read work inside a read-committed mutation.

**Cross-pool nesting:** connection and mutation contexts each occupy one zone value. A hypothetical **pool A → pool B → pool A** chain hides A’s retained scope behind B’s value and can reacquire A. Auth has a separate one-connection pool, but I found no current production cycle of this form.

**Fix:** track contexts by pool identity, with a transaction stack per pool. Validate isolation/access mode for **every** transaction, including plain and read-only transactions.

**`Future.wait` audit:** DB fan-outs occur at [band_candidate_repository.dart:42](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/band_candidate_repository.dart:42), `BeaconForwardGraphCase:54`, `BeaconInvolvementCase:51` and `BeaconHelpOffererForwardPathCase:68`. I found no active caller wrapping those fan-outs in a transaction. Parallel reads sharing the correct executor are not inherently deadlocking; the risk would be a branch acquiring another lease or resolving to a locked parent.

## B. Ranked prevention recommendations

Sizes below are rough **additional lines, including focused tests**.

| Rank | Recommendation and implementation sketch | Value / cost | Would catch `e02023617`? |
|---|---|---|---|
| **1** | **Runtime ownership guards.** In `tentura_db.dart`, maintain per-pool lease and innermost-transaction contexts containing executor identity, actor, isolation, scope ID and entry stack. Before executing a statement, assert it targets the innermost executor. Guard **actual acquisition** in `MainDbPool` and `MainDbScopeAdmission`, not calls that legitimately reuse a scope. Test/debug errors should include expected/actual executor and entry stacks. Guard escaped closed scopes too. **250–450 lines.** | Highest value; medium cost. Diagnoses the fault at its source. | **Yes**, the executor guard catches the reported path. A lease-only guard catches only the reacquisition variant. |
| **2** | **Real PostgreSQL ownership regression matrix.** Extend `mutating_unit_of_work_scoped_pg_test.dart` with **two `TenturaDb.scoped(pool)` handles**, real repositories and nested savepoints. Verify PID, transaction ID, actor GUC, nested rollback, outer rollback and single admission/lease ownership. Cover `openForwarding`, publication, cancellation and worker closure finalization. Add actor mismatch and incompatible-isolation cases across handles. **250–400 lines.** | Very high value; low-to-medium cost. | **Yes**, when exercising the failing composition. Existing probe tests at `:425` give the UOW and both repositories the same DB instance. |
| **3** | **Test timeout around Drift executor waits.** Add a test-only `QueryInterceptor` covering `ensureOpen`, SQL methods, commit and rollback; install it around root, leased and nested executors. Drift’s private lock has no configurable wait timeout. A scoped operation deadline is needed as well for waits before executor dispatch. On expiry, record diagnostics and abort/close the owning physical connection; do not merely abandon a `Future.timeout`. Files: `test/support/`, scope construction in `tentura_db.dart` or a test hook. **150–250 lines.** | High value; medium cost. | **Yes**, turns the hang into a prompt failing test. |
| **4** | **Pool-size-1 CI mode.** Add an explicit test pool override in `disposable_pg_target.dart` and the shared test-env helpers; run functional PG tests with pool/admission concurrency 1 and short deadlines. Audit fixtures that override pool settings, otherwise the mode is ineffective. Keep intentional overlap/sizing tests in their normal multi-connection mode. Files: test support and `.github/workflows/pipeline.yml`. **60–120 lines.** | High value; medium cost and extra CI time. | **Yes for a reached reacquisition path.** Executor-lock hangs still require a watchdog. Admission re-entry fails by deadline rather than deadlocking forever. |
| **5** | **Reviewed transaction-entry inventory.** Add an AST-based architecture test enumerating transaction roots, joining wrappers and explicit savepoints, with owner/reason for each exception. Extend `scoped_main_db_access_test.dart` and existing attention-boundary inventories. Require explicit review when an entry point changes. **120–220 lines.** | Good value; relatively low cost. | **Would flag the ownership change for review, not prove the bug.** Existing source-pattern tests do not establish executor correctness. |
| **6** | **Per-test watchdog with independent diagnostics.** Before the test runner’s hard timeout, dump the active scope/transaction stacks and query `pg_stat_activity` through a separate admin connection, scoped to the test database. Include PID, state, transaction age, wait event, last query and blocking PIDs. For actual suspended Dart stacks, use a test worker with VM-service access; `StackTrace.current` only captures the watchdog’s stack. Terminate the worker after diagnostics through the existing cleanup wrapper. **200–350 lines.** | High diagnostic value; medium-to-high cost. | **Yes as a timeout failure**, and would expose the `SAVEPOINT s1` idle backend. |
| **7** | **Disposable-DB SQL timeouts.** Set test-only `idle_in_transaction_session_timeout`, `statement_timeout` and optionally `lock_timeout`, using database-local defaults or a shared test connection initializer. Apply after migration setup and account for fixture `onOpen` overrides. Avoid cluster-wide role changes. Files: `disposable_pg_target.dart`, test pool settings. **40–90 lines.** | Cheap useful backstop; incomplete coverage. | **Statement timeout: no** for the reported Dart wait. Idle timeout terminates the idle backend, but **may leave the Dart lock wait unresolved**. Combine with rank 3/6. |
| **8** | **Custom transaction/construction lints.** Add rules under `packages/tentura_lints/lib/src/rules/`, register in `lib/main.dart`, and add analyzer tests. Forbid data-adapter construction in domain use cases; require annotations/allowlisting for repository-to-repository construction. Flag transaction APIs lexically nested in transaction callbacks unless explicitly designated savepoints. AST element resolution is preferable to class-name suffix matching. **250–450 lines.** | Useful structural prevention; higher cost, limited interprocedural reach. | **Not reliably alone.** The incident crosses UOW/repository calls and depends on runtime zones. A broader rule would flag some hazardous compositions above. |

The strongest pre-landing gate is **the executor-identity guard plus the cross-handle PostgreSQL regression**, backed by a Dart timeout. Pool size 1 adds useful coverage; SQL timeouts and lints are supporting controls.

During the audit, the concurrent agent added `tentura_db_shared_pool_savepoint_pg_test.dart`, using separate outer/repository handles. That addresses the missing test shape; I did not run it or verify its result.