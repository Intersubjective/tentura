# Typed trust source graphs — review record

Historical critique and resolution record for [`typed-trust-source-graphs-plan.md`](typed-trust-source-graphs-plan.md). The plan body is the only normative document; everything here is preserved verbatim for audit purposes and **must not** be treated as instructions.

- Appendix A: independent critique of rev 1 (2026-07-19).
- Appendix B: rev 2 resolution of Appendix A.
- Appendix C: incorporation of correction patch 1 (rev 3).
- Rev 3 review verdict + product sign-offs: the review that produced rev 4.

---

## Appendix A — Independent critique (subagent review)

_Reviewed 2026-07-19 by a separate agent; the plan body above was not modified._

Verification notes: every `file:line` claim below was checked against the working tree on 2026-07-19. Cross-checked sources: `m0088.dart`, `m0114.dart`, `m0109.dart`, `m0014.dart`, `m0019.dart`, `m0058.dart`, `m0063.dart`, `_migrations.dart`, the `migrant_db_postgresql-0.3.0` gateway source, `user_trust_edge_repository.dart`, `evaluation_repository.dart`, `evaluation_case.dart`, `forward_case.dart`, `resolve_forward_parent_edge.dart`, `attention_expiry_sweep_case.dart`, `task_worker_case.dart`, `app.dart`, `env.dart`, `.env.example`, `hasura/metadata.json`, and the two pg tests named in §11. The plan's "verified current state" (§1) is largely accurate; the defects below are in the plan's own design, not its inventory.

### Blockers

1. **Advisory-lock exhaustion and multi-hour lock retention in `trust_rebuild_effective_all` / `meritrank_sweep`** — §4.6 takes `pg_advisory_xact_lock` per pair and §4.7's `trust_rebuild_effective_all` loops **every distinct pair in one function call, i.e. one transaction** (`SELECT meritrank_sweep(...)` from §9.3 is a single-statement transaction). Transaction-scoped advisory locks are only released at commit, and they consume slots from the shared lock table sized by `max_locks_per_transaction × (max_connections + max_prepared_transactions)` (default ≈ 64 × 100). A sweep over ~10k+ pairs will fail with "out of shared memory / You might need to increase max_locks_per_transaction", and until it fails it serializes **all** concurrent evidence writes touching any swept pair. The m0114 history is the precedent warning: `trust_recompute_all` was deliberately converted from a per-row loop to one set-based UPDATE for exactly this class of problem (`m0114.dart:498-530`). Evidence: plan §4.6 (`PERFORM pg_advisory_xact_lock(...)`), §4.7 loop; `m0114.dart:505`. Recommendation: drive the sweep from Dart in small per-pair (or per-subject) transactions, or drop the advisory lock in favor of ordered row locking on the `effective` row (`INSERT … ON CONFLICT DO UPDATE` already serializes writers per pair); if advisory locks stay, the sweep must commit in batches.

2. **Re-review double-emission violates spec AC 23 ("successful and unsuccessful evidence cannot both be emitted for the same request and pair")** — the codebase has a re-scaffold flow: `evaluation_case.dart:215-237` calls `deleteReviewScaffoldingForBeacon` (which **deletes the `beacon_review_window` row**, `evaluation_repository.dart:342-355`) and then `insertReviewWindow` with `status = 0`. A second `closeBeaconReviewWindow` therefore passes the window-status guard and runs the §8.2 pipeline again. The ledger unique index keys on `(trust_context, source_type, request_id, subject, object)` — **`source_type` differs between the positive and neutral events**, so a pair that got `successful_request_forward_path` in the first finalization and classifies as unsuccessful in the second gets `unsuccessful_request_forward` inserted and applied: both event types now exist for the same `(request, pair)`, and the source bins double-count the episode. The plan's "double-guarded idempotency" (decision 11) only protects identical re-finalizations. Evidence: plan §3 decision 4/11, §4.4 index, §8.1 step 6; `evaluation_case.dart:233`, `evaluation_repository.dart:352-354` (window row deleted, not status-flipped). Recommendation: before emitting, exclude any pair that already has **either** auto-forward source type for this `request_id` in the ledger (one indexed lookup), or narrow the unique index to `(trust_context, request_id, subject, object)` filtered to the two automatic forward source types; and state explicitly what re-review is supposed to mean for forward learning (see open questions).

### Major

3. **Decision 7 discards spec attribution priorities 2–3 on a misapplied rationale** — spec §Stage 1 mandates the order "explicit user attribution → reliable recorded parent attribution → opened-via → equal fallback". The plan drops `recorded_parent` and `opened_via` entirely and jumps from explicit to equal fallback. The cited justification (spec §Later forwarding episodes, "do not silently attribute the new decision to the old source") addresses **reusing a stale snapshot after new inbound forwards appear**, not first-decision provenance. When the client supplies `parentEdgeId` it is validated as the sender's own inbound edge (`resolve_forward_parent_edge.dart:17-27`) — i.e., it is precisely the opened-via signal the spec says "may be considered sufficiently reliable" and that the plan itself trusts enough to preselect in the UX (§7.3 `isSuggestedSource`). Net effect: every multi-inbound sender who skips the prompt collapses to equal fallback, discarding recorded causal signal the spec explicitly ranks above fallback. Evidence: plan §3 decision 7, §7.2; spec §Backward propagation attribution order. Recommendation: persist an `opened_via`-method attribution row when the forward carries a validated client-supplied `parentEdgeId` (weight 1 for that decision, superseded by any explicit answer), or re-justify the cut honestly as a v1 scope decision with telemetry to measure the fallback rate — the current rationale reads as a spec citation that does not support the conclusion.

4. **Deadlock-prone lock ordering between the sweep and finalization** — the writer sorts touched pairs (§5.3 step 3, "sorted, for deterministic lock order") but `trust_rebuild_effective_all` iterates `SELECT DISTINCT subject, object` **without ORDER BY** (§4.7), so the sweep acquires the same advisory locks in planner-dependent order while holding all previously acquired ones (Blocker 1). Two multi-lock transactions with inconsistent acquisition order is the textbook deadlock recipe; the 1-minute `TaskWorkerCase` cadence plus `closeExpiredWindows` batching makes the overlap window real. Evidence: plan §4.7 vs §5.3; `task_worker_case.dart:88-97`. Recommendation: `ORDER BY subject, object` in every multi-pair loop, and keep multi-pair transactions short (also resolved by fixing Blocker 1).

5. **Availability regression: one failed `mr_put_edge` now aborts the whole finalization (and the whole expiry-sweep batch)** — today `applyEvidenceInTransaction` wraps each item in a savepoint and swallows failures (`user_trust_edge_repository.dart:47-64`), so a MeritRank outage degrades to lost evidence, not failed closes. The §5.3 writer specifies no savepoints; a single `trust_rebuild_effective_edge` publish failure aborts `closeBeaconReviewWindow` entirely — rolling back evaluation finalization — and `AttentionExpirySweepCase.runDue` wraps **all** due beacons in one outer `runAction` transaction (`attention_expiry_sweep_case.dart:26-45`), so one bad pair wedges every expired review window until the MeritRank engine recovers. The plan even relies on same-transaction abort as a correctness feature (§4.6 note) without acknowledging the blast radius. Recommendation: keep savepoint-per-item semantics in the writer, or (better) decouple publication: rebuild effective rows in-transaction but drain `mr_put_edge` from a post-commit outbox with retry; spec §Effective-edge rebuild only requires `prev_published_weight` not to advance before successful publication, which an outbox satisfies.

6. **User deletion silently destroys forwarding ancestry and leaves stale MeritRank edges — unaddressed** — `beacon_forward_edge.sender_id/recipient_id` are `ON DELETE CASCADE` and `parent_edge_id` is `ON DELETE SET NULL` (`m0014.dart:26-31`). Deleting one mid-chain user deletes their edges; all child edges become parentless non-author edges, which decision 9 classifies as rootless → the **entire downstream subtree** silently loses eligibility (no positive, no `no_effect`, no integrity error — the plan's cycle/integrity defense never fires because the data is "valid"). `forward_decision_attribution` rows CASCADE away with the parent edge (§4.4), further degrading surviving commitments to fallback. Separately, `user_trust_edge` rows CASCADE on user deletion (`m0088.dart:19-22`) — including `effective` rows — while the corresponding `mr_*` edge survives until a manual full refresh, violating spec §Effective-edge rebuild "MeritRank must not retain stale edges". The plan discusses none of this. Recommendation: document deleted-user semantics as accepted lossy behavior or log an integrity warning when a DAG loses author-rootedness through orphaned parents; call `mr_delete_edge` (or schedule a refresh) from the user-deletion path.

7. **No rollback procedure and no true upgrade-path test** — m0122 is irreversible (PK widened, `trust_apply_evidence` dropped, legacy `prev_sent_weight` zeroed) and phases 1–3 are declared one atomic release (§14), yet the plan contains no rollback runbook, and spec §Required tests / Migration explicitly demands "rollback preserves the old combined state". The §11 `trust_migration_test.dart` hand-inserts **post-migration-shaped** rows — it never executes m0122 against a populated pre-m0122 database, so the one migration that rewrites production data ships untested on real upgrade data (§4.9's "restore or hand-insert pre-m0122 shape in a scratch schema" is hand-waving: after m0122 runs in CI, the pre-shape cannot exist in `public`). Recommendation: add (a) a documented backup-before-deploy + restore rollback procedure, and (b) a pg test that builds the pre-m0122 shape in a scratch schema, runs the m0122 statement list against it verbatim, and asserts weight preservation and row counts.

8. **`trust_context_config.half_life_seconds` is a data-corruption trap the plan wires in without warning** — stored `s_*` values are *inflated at write time* using the half-life in force at that moment (§4.5; `m0114.dart:625-634`). If an operator later changes a context's `half_life_seconds`, §4.6 deflates the historically-inflated sums with the **new** exponent — every existing accumulator is silently reinterpreted (not rescaled: distorted, because inflation and deflation exponents no longer cancel). Spec §Reconfiguration lists "source half-life changes" as needing only an effective rebuild, which is mathematically wrong under VSIDS inflation, and the plan copies the assumption while adding the very knob (nullable column, admin UPDATE) that triggers it. Evidence: plan §3 decision 3, §4.2, §4.6; spec §Applying source evidence. Recommendation: v1 should make the column read-only-NULL (or omit it) and document that a half-life change requires a re-anchoring migration (deflate all bins to `now` under the old half-life, reset `anchor_at`, then switch); at minimum flag it in the migration doc-comment and the design doc.

### Minor / nits

9. **§1.6 mischaracterizes the migration runner** — "do not rely on the runner's transactional semantics" is backwards: `migrant_db_postgresql` 0.3.0 executes the version insert **and all statements of one migration inside a single `runTx` transaction** (gateway source, `_apply`). Consequences the plan gets wrong in both directions: (a) §4.1's `set_config(..., true)` suppression is *guaranteed* to cover the whole of m0122, not "best-effort/harmless if separate"; (b) a failed statement rolls back the version row, so per-statement idempotency is defense-in-depth, not a correctness requirement. Fix the two comments so implementers don't design for a partial-application scenario that cannot happen.

10. **m0122 runs a full-table rewrite under one ACCESS EXCLUSIVE window** — PK drop/create rebuilds the index, the effective-materialization INSERT doubles row count, and the legacy UPDATE rewrites every legacy row, all in one startup transaction while the trigger-storm GUC (correctly) suppresses notify. Fine at current scale; note the startup-downtime implication and that `ADD CONSTRAINT ... CHECK` also takes a full validation scan.

11. **§4.9 sanity formula is wrong** — after `trust_apply_source_evidence('personal', …, 'good', 3, …)` the effective weight is `(+1×3)/(5+3) = 0.375` (personal multiplier is **1.0**); the plan's `3*0.2*3/(5+3*0.2)` applies the *forward* multiplier to a *personal* event and misplaces the utility factor. Cosmetic, but it is exactly the kind of "expected value" an implementing LLM will copy into a test assertion.

12. **`user_trust_edge_object_idx` already exists** (`m0114.dart:812`); §4.1 re-creates it — harmless dead statement, drop it.

13. **GUC restore sets `''` where the setting was previously unset** (§4.5 `COALESCE(_prev_suppress, '')`) — harmless because `notify_relationship_change` tests `= '1'` (`m0114.dart:442`), and it faithfully copies the m0114 wart, but a comment should say the empty string is deliberate.

14. **Personal-vote replay protection rests entirely on the amount-diff check** — `request_id NULL` events bypass the ledger unique index (§3 decision 4); `_setVoteAmountCore` dedupes only `previousAmount == newAmount` (`user_trust_edge_repository.dart:188`). Spec §Evidence ledger says "retries, event replay … must not apply evidence twice" — the plan should state explicitly that for votes this guarantee is delegated to the vote-amount state machine (and to the pair advisory lock in `setVoteAmountAndDetectMutualFormationInTransaction`), not the ledger.

15. **`commitmentAt = help_offer.created_at` has an aliasing edge** — `beacon_help_offer` PK is `(beacon_id, user_id)` (renamed `beacon_commitment`, `m0014.dart:45`); a withdraw/re-offer cycle reuses the row, so `created_at` may predate the forward that actually prompted the eventual acknowledged offer, making genuinely causal forwards ineligible (unverified whether the re-offer path preserves `created_at` — verify before Phase 5 and consider `updated_at`-based or admission-event-based timestamps).

16. **Terminal-seed policy is a plan invention, not a spec rule — label it** — spec §Terminal mass only defines mass 1.0 at the committer; the distinct-sender equal split (decision 8) is reasonable and repeated-forward-safe, but it also ignores any explicit attribution the committer may have recorded for their own inbound sources (they answered the prompt only if they *forwarded*). Mark it as a spec-gap decision in the design doc, not as spec-derived.

17. **Sybil invariance is only tested at budget level** — spec §Topology and Sybil invariance requires "external MeritRank score of the downstream target does not increase merely from path subdivision"; §11 tests conserve sender budgets but never assert an `mr_node_score` before/after inserting an intermediary. Add one pg test through the real engine, otherwise AC 18's MeritRank half is unverified.

18. **Sweep suppresses relationship realtime for legitimate decay changes** — `trust_rebuild_effective_all` sets the suppress GUC (§4.6), so epsilon-exceeding *effective weight changes* published by the daily sweep never emit `relationship` events; clients keep stale relationship UI until another write on that pair. m0114's convention was safe because the old sweep path only rewrote bookkeeping; the new sweep is the *only* writer that moves decayed effective weights. Decide deliberately (and document) whether decay-driven changes should be client-visible.

19. **Writer round-trip count** — §5.3 performs one INSERT + one function call per item plus one per pair, all sequentially inside the close transaction; for a wide request (dozens of eligible pairs from §8.1 step 6 `no_effect`) that is 3×N sequential round trips inside a lock-holding transaction. Batch the ledger inserts (multi-VALUES) and consider a set-based apply.

### Open questions for the author

1. What is the intended forward-learning semantics of a **re-reviewed** request (Blocker 2)? Freeze the first episode, replace it (compensating events), or merge? The spec is silent; the plan must pick one explicitly.
2. Mutual-visibility first-hop chains are excluded as rootless (decision 9), so those senders get neither positive nor `no_effect` learning forever in v1. Intended, or should a mutual-visibility first hop count as an author-equivalent root (the author chose visibility, arguably a delegation act)?
3. `forceRefreshStar` rebuilds only the subject's **outgoing** pairs (§4.7), matching old semantics — but effective rows are now derived; should a user-triggered resync also refresh incoming pairs whose sources changed while publication was failing?
4. Who deletes MeritRank edges when a user account is deleted (Major 6)? Today nothing does; the plan institutionalizes `effective` as the only publication path but gives it no deletion trigger.
5. Is `TRUST_SWEEP_INTERVAL_HOURS=24` (§5.4) compatible with `TRUST_EDGE_EPSILON=0.1` and a 182-day half-life? Rough math says a daily sweep will publish almost nothing (daily decay ≈ 0.4%, below epsilon for all but the heaviest edges) — fine, but then the sweep's cost concern (Blocker 1) is dominated by the loop itself, not publication; a cheaper drift pre-filter (`WHERE abs(current − prev) > ε` computed set-based) could skip the per-pair function call entirely.

---

## Appendix B — Resolution of the critique (rev 2)

_2026-07-19. Every Appendix A finding was addressed in the plan body above; this appendix maps finding → resolution and records the overengineering re-check. Appendix A itself is preserved unmodified as the review record._

### B.1 Finding-by-finding resolution

| # | Finding | Resolution | Where |
| --- | --- | --- | --- |
| 1 (Blocker) | Advisory-lock exhaustion in bulk rebuild | Advisory locks removed entirely. Per-pair serialization now uses ordered `SELECT … FOR UPDATE` on the pair's source rows (the spec's first-listed option); bulk sweep/recompute became **two set-based statements** (m0114 precedent) plus a drift-filtered, ordered publish loop. No lock-table consumption, no transaction-long accumulation. | Decisions 15; §4.6, §4.7 |
| 2 (Blocker) | Re-review can emit both positive and `no_effect` for one pair | Episode-exclusive partial unique index over **both automatic forward source types** on `(context, request, subject, object)`; first finalized episode is frozen per pair. Commitment evidence gets the same at-most-once guarantee via the second index — which also fixes a pre-existing bug (today re-review re-applies evaluation evidence twice). | Decisions 4, 11; §4.4; §11 episode-freeze test |
| 3 (Major) | Spec attribution priorities 2–3 discarded on a misapplied rationale | `opened_via` is now persisted (weight 1) whenever the **client** supplied `parentEdgeId`; explicit answers take precedence; only server-auto-resolved parents remain non-attributive (that part of the original rationale stands and is now argued honestly). Finalization priority: explicit → opened_via → equal fallback. | Decision 7; §7.1–7.2; §8.1 |
| 4 (Major) | Deadlock-prone lock ordering | All multi-pair loops are `ORDER BY`-ed (writer, resync, sweep publish loop); bulk materialization is one statement. Residual risk from the set-based INSERT's internal ordering vs a concurrent writer is accepted: the deadlock detector aborts one party, nothing is left half-published, and the task worker retries next interval. | §4.7, §5.3, §9.3 |
| 5 (Major) | One failed `mr_put_edge` aborts finalization / expiry batch | Publication is deferred-on-failure: `EXCEPTION`-wrapped inside the rebuild, `prev_sent_weight` un-advanced, WARNING raised, auto-republish on next rebuild/sweep. Evidence is never lost; closes never wedge. Writer additionally keeps today's per-item savepoint degradation. | Decision 14; §4.6, §4.7, §5.3 |
| 6 (Major) | Deleted users: stale MR edges + orphaned ancestry | `AFTER DELETE` trigger on published effective rows calls `mr_delete_edge` (exception-swallowed). Orphaned forwarding subtrees are accepted lossy v1 behavior, now **logged** per finalization (rootless-edge count) instead of silent. | Decision 16; §4.7 trigger; §8.1 step 3 |
| 7 (Major) | No rollback, no upgrade-path test | §4.10 rollback runbook: backup-restore primary path, value-preserving reverse script (`sql/rollback_m0122.sql`) secondary path, staging dry-run against a production dump on the release checklist. Migration test now replays the m0122 data-transform statements **verbatim** (they are importable Dart values) and exercises the reverse script in a rolled-back transaction. | §4.10; §11 `trust_migration_test.dart` |
| 8 (Major) | Per-context half-life is a VSIDS corruption trap | Column **removed** from v1 (global half-life only); the re-anchoring requirement for any future per-context half-life is documented in the migration comment and design doc. | Decision 3; §4.2; §10.2 |
| 9 | Migration runner mischaracterized | §1.6 corrected: one transaction per migration, guaranteed GUC coverage, idempotency demoted to defense-in-depth. | §1.6, §4.1 |
| 10 | Startup-downtime window unstated | Operational note added (seconds-scale pause, don't stack long migrations). | §4.1 |
| 11 | Wrong sanity formula | Corrected to `(1.0 × 1 × 3)/(5 + 1.0 × 3) = 0.375`. | §4.9 |
| 12 | Duplicate `(object)` index | Statement removed; existing `m0114` index noted. | §4.1 |
| 13 | GUC `''`-restore unexplained | Comment added (trigger tests literal `'1'`; `''` ≡ unset). | §4.5 |
| 14 | Vote replay protection implicit | Made explicit: delegated to the vote state machine + pair advisory lock; recorded in decision 4 and the design doc. | Decision 4; §10.2 |
| 15 | `commitmentAt` aliasing on re-offer | Verified real (`upsert` `DoUpdate` never touches `created_at`). Kept `created_at` **because the error direction is conservative** — it can only under-credit, never grant late credit (the spec's hard constraint). Documented as a v1 limitation with a revisit trigger. | Decision 9; §10.2 |
| 16 | Terminal seed presented as spec-derived | Relabeled a plan decision filling a spec gap, in both the decision list and the design doc. | Decision 8; §10.2 |
| 17 | Sybil invariance untested at engine level | Added an `mr_node_score` before/after path-subdivision assertion to the boundary pg test. | §11 `trust_meritrank_boundary_test.dart` |
| 18 | Sweep suppresses realtime for real decay changes | Made a deliberate, documented decision: bulk decay drift surfaces on next fetch, not via realtime push (avoids nightly notify storms); single-pair rebuilds still notify. | §4.7 comment; §10.2 |
| 19 | Writer round-trip chattiness | Kept per-item statements deliberately (bounded N, savepoint semantics stay simple); multi-VALUES batching noted as a pure optimization to apply only if profiling demands. | §5.3 |

### B.2 Open questions — answered

1. **Re-review semantics:** first finalized episode is frozen per (request, pair); re-finalization emits nothing for covered pairs and normal events for genuinely new pairs (decision 11). Rationale: any "replace/merge" scheme needs compensating negative events, which the evidence model deliberately lacks.
2. **Mutual-visibility first-hop chains:** stay excluded in v1 — the spec is explicit that every valid path originates from the author, and inventing synthetic author roots is new mechanism the spec doesn't license. The loss is now measurable (rootless-edge log, §8.1); revisit with data.
3. **`forceRefreshStar` outgoing-only:** kept — spec §One-user resync literally prescribes "effective outgoing edges only" (§4.7 note). Incoming staleness self-heals via the sweep's drift filter.
4. **Deleted users:** answered by the delete trigger (decision 16).
5. **Sweep economics:** answered by the set-based rebuild + drift-filtered publish loop (§4.7 economics note) — the critic's suggested pre-filter is exactly what was implemented.

### B.3 Overengineering re-check (what rev 2 deliberately does NOT do)

Each fix was chosen as the smallest mechanism that closes the finding; the heavier alternatives considered and rejected:

- **No publication outbox/queue** (considered for Major 5): the `EXCEPTION`-wrap + un-advanced `prev_sent_weight` + existing sweep already form a retry loop with zero new tables or workers. An outbox adds a table, a drainer, and ordering questions for strictly less benefit at this scale.
- **No per-episode attribution snapshot store** (considered for Major 3): spec §Later forwarding episodes describes snapshot reuse rules, but v1 stores at most one attribution record per batch and recomputes fallback at finalization — the snapshot machinery would model states v1's UX can't even produce.
- **No synthetic roots for mutual-visibility chains** (open question 2): would silently widen the spec's rootedness rule.
- **No Dart-driven batched sweep driver** (considered for Blocker 1): two set-based SQL statements are less code than a batching driver with checkpointing, and match the m0114 precedent already in the tree.
- **No per-context half-life** (Major 8): removed rather than guarded — the simplest correct system is one that cannot express the corrupting operation.
- **No writer micro-batching** (finding 19): bounded N; simplicity of savepoint-per-item wins until profiled otherwise.
- **No new telemetry infrastructure**: structured logs + ledger SQL remain sufficient for every spec §Telemetry metric.

Residual accepted risks, stated plainly: (a) a rare deadlock between the sweep's set-based INSERT and a concurrent per-pair writer — detector-resolved, retried next interval, never half-published; (b) ancestry loss after user deletion — logged, not repaired; (c) under-crediting across withdraw/re-offer cycles — conservative by construction. All three are visible in logs/telemetry, none violates a spec acceptance criterion.

---

## Appendix C — Incorporation of correction patch 1 (rev 3)

_2026-07-19. Correction patch 1 (archived verbatim as [`typed-trust-correction-patch-1.md`](typed-trust-correction-patch-1.md)) supersedes the scalar request-outcome-strength and `max`-consolidation design that rev 2 carried from the original spec. Appendices A and B remain historical records of rev 1→2; where they mention `successful_request_forward_path`, outcome strength, or `max` consolidation, rev 3's body text wins._

### C.1 What changed, section by section

| Plan section | Rev 2 (superseded) | Rev 3 (patch 1) |
| --- | --- | --- |
| §2 terminology | "author-positive commitment" (`pos1`/`pos2` only) | "author-evaluated commitment (non-negative)": `zero`/`pos1`/`pos2`; negatives never propagate |
| Decision 10 | `pos1→0.5`, `pos2→1.0`, `max` reducer, single `good`-bin positive events | per-bin vector support (summed), `observation_weight = 1.0` per commitment, one `evaluated_outcome_budget = 1.0` per sender split across recipients **and** bins, bins preserved end-to-end |
| Decisions 4, 11 | pair-level episode-exclusive unique index | per-bin index (4a) + route-failure index (4b) + general index (4c); cross-type exclusivity and re-review freeze moved to a request-level episode gate in the finalizer |
| §4.4 DDL | 2 partial unique indexes | 3 partial unique indexes (bin in the propagated key) |
| §5.2 enum | `successfulRequestForwardPath` | `propagatedAuthorEvaluatedCommitment` |
| §8.1 | `outcomeStrength` policy + `consolidateMax` | `mapAuthorEvaluationToDirichletBin` (reuses `reviewValueToBin`), `accumulate`/`normalizePerSender` vector consolidator, mixed-bin events |
| §8.2 | positive-only filter (`isPositive`) | non-negative filter (`zero`/`pos1`/`pos2`) + episode gate before emission |
| §10.2 | constants list incl. 0.5/1.0 strengths, `max` | quantity/value separation, double-weighting prohibition, patch's four worked examples |
| §11 | scalar-budget tests | patch §12 test matrix (bin preservation, cross-bin normalization, mixed evidence, neutral distinction, no double weighting) |
| §12 | spec's 29 criteria | criteria 14/16/17 marked patch-amended; patch §13's P1–P9 mapped |

Deliberately **unchanged**: everything in Phases 1–4 and 6–7 that the patch does not touch — schema strategy, config table, decay/VSIDS math, effective projection and publication, attribution recording (decision 7's priority chain: explicit → opened_via → fallback), route-failure `no_effect` magnitude and opportunity interval, sweep/rollback/deletion machinery.

### C.2 Patch-interpretation notes (flag these at review)

The patch is internally inconsistent or silent in three places; decision 17 records the resolutions:

1. **`neutral_commitment_forward_path` (patch §8) vs `propagated_author_evaluated_commitment` (patch §9–10).** Resolved to the single §9/§10 source type with `bin` carrying the outcome — the neutral/route-failure distinction the patch demands survives intact, and the ledger stays queryable by (source_type, bin). If the product owner wants the separate neutral source type instead, only §5.2, index 4a, and decision 17a change.
2. **The no-outcome gate.** Patch §9's pseudocode silently dropped the original "no positive commitment ⇒ no automatic `no_effect`" return. Reinterpreted (not removed): the gate now requires ≥ 1 finalized **non-negative** author evaluation. Dropping the gate entirely would `no_effect`-tag every route of every abandoned request — contradicting the original spec's §Positive-outcome gate rationale, which the patch never argues against.
3. **Negatively-evaluated paths and route-failure classification.** The patch's exclusion list (§8) names only non-negative bins, so a pair lying solely on a negatively-evaluated commitment's path is classified unsuccessful when eligible. Followed literally (decision 17c); if this is unintended, add negative-path pairs to `observedPairs` — a one-line change in the finalizer.

### C.3 Property change accepted with the patch

Rev 2's `max` consolidation made a sender's *relative* distribution invariant to commitment-count multiplication behind one branch. The patch's summed per-bin support deliberately trades that away for observation-counting semantics: totals stay bounded (Σ per sender = 1.0 regardless of commitment count — the anti-inflation invariant the original spec cared most about survives), but a branch backed by more evaluated commitments now earns a proportionally larger *share* of the sender's budget. This is the patch's explicit design (each evaluation is one observation), so the multiple-commitments worked example and the duplication tests were recomputed accordingly (§11) rather than "fixed". Telemetry already tracks commitments per request; if share-tilting via commitment splitting shows up in practice, the policy seam is `ForwardRequestConsolidator.accumulate`.

### C.4 Overengineering re-check for rev 3

- `observation_weight` and `evaluated_outcome_budget` are **code constants**, not env knobs or config columns — the patch fixes both at 1.0 for v1 and only demands the *seam* for a future orthogonal confidence weight (`accumulate` already takes the weight per commitment internally; exposing it is a later, deliberate act).
- No separate neutral source type, no per-bin budget accounting tables, no bin-weight configuration — all would model states v1 cannot produce.
- The request-level episode gate is one indexed `EXISTS` query reusing an index that already exists for other reasons — chosen over schema-level exclusion constraints (`EXCLUDE USING`), which would be the first such constraint in the codebase for a case the gate covers trivially.
- The finalizer's result type grew one field (`bin`) and the consolidator swapped `max` for sum — the pure-pipeline structure, transaction boundaries, locking, publication, and migration design of rev 2 all survive unchanged.

---

## Rev 3 review verdict (2026-07-19) — the review that produced rev 4

Verdict: **do not approve rev 3**. Direction sound; two correctness blockers can corrupt or permanently under-apply trust evidence.

1. **Blocker — partial-commit episodes.** The rev-3 writer caught every per-item error and continued (per-item savepoints), so a forward result — normalized as one bounded sender budget — could apply only some bins/pairs. The next finalization was then rejected as soon as *any* forward event existed, so missing items could never be repaired. It also regressed personal votes: the vote transaction currently lets evidence failure abort it; under a best-effort writer the vote could commit without evidence, after which the unchanged-amount guard prevents retry (violates the source spec's consistent-transaction requirement). **Required:** ledger insertion and source mutation atomic for the complete semantic batch; only expected idempotency conflicts skipped; other failures abort the close so the outer transaction can retry. MeritRank publication may stay independently deferred.

2. **Blocker — pair serialization not correct.** (a) `trust_apply_source_evidence` first locked only its own context row; a concurrent personal writer and forward writer could each hold a different row, then both attempt to lock every context during rebuild — ordered acquisition does not prevent deadlock when locks were already acquired in different contexts. (b) The bulk sweep aggregated source rows without locking them, then `ON CONFLICT DO UPDATE` — it could read an old snapshot, wait behind a newer per-pair rebuild, and overwrite the newer effective row with stale values. **Required:** a stable pair lock before any context-row mutation (bounded per-pair advisory lock fine for request-sized sorted sets); sweep batched with the same lock discipline or an optimistic CAS; explicit personal-vs-forward and sweep-vs-writer concurrency tests.

3. **Major — orchestration in the wrong layer.** Rev 3 placed request semantics, four-table loading, episode gating, domain calculation and evidence emission inside `EvaluationRepository.closeBeaconReviewWindow`, conflicting with the project rule that use cases orchestrate while repositories remain data sources. `record()` also relied on ambient Drift transaction state without expressing the dependency in its API. **Required:** a review-finalization use case owning workflow + transaction boundary through a narrow unit-of-work port; repositories load/store typed snapshots; the pure finalizer returns typed evidence plus diagnostics, no internal log-and-skip.

4. **Major — attribution not server-authoritative.** "First outgoing episode" was enforced only in client state; the eligible query loaded active inbound edges without requiring involvement authorization; the current server validates inbound edges *before* entering the forwarding transaction (TOCTOU); duplicate attribution ids were not rejected; attribution could be stored even when `createBatch` inserted no recipients. **Required:** validate and lock the authoritative inbound set inside the forwarding transaction; enforce first-episode semantics server-side including cancelled historical batches; require the same involvement guard as the graph query; reject duplicate and overlarge lists; never convert the server's "most recent" heuristic into an apparent opened-via selection.

5. **Major — failed MeritRank deletion had no retry path.** The delete trigger swallowed `mr_delete_edge` failure after the effective row was gone; the sweep could not retry because no row remained to discover. **Required:** durable deletion tombstone/outbox (or periodic authoritative reset), plus a test of deletion while MeritRank is down and subsequent automatic convergence.

6. *(withdrawn by reviewer — not applicable.)*

7. **Major — runtime configuration could silently reinterpret history.** Global half-life was an unrestricted env value with no stored model epoch — a changed or mismatched deployment could reinterpret the same accumulator, or two half-lives could write concurrently, undetected. Multipliers were changed via direct SQL + separate manual rebuild; `config_version` was never attached or enforced. Speculative extension points (`model_kind` free-form, reserved attribution methods, recipient-feedback writer support) were accepted but unimplemented. **Required:** one validated database policy version authoritative; startup fails on half-life mismatch unless re-anchoring has run; one controlled config-change/rebuild operation; reject non-finite/unreasonable values; constrain or omit speculative points.

8. **Major — sweep scheduling process-local.** The proposed sweep copied the task worker's in-memory throttle: every replica runs it, the last-run timestamp is recorded *before* awaiting the task (one failure suppresses retry for 24 h), and a long rebuild blocks the sequential worker loop. The migration also required a quiesced deployment without proof old instances had stopped before the old SQL signature was dropped. **Required:** database lease or global advisory lock, success recorded after completion, shorter failure retry, bounded execution; mixed-fleet-safe migration.

9. **Medium — conflicting normative instructions** (§4.4 comment vs §7.2 on `opened_via`; body's request-wide freeze vs Appendix B's "new pairs may still emit"; "pure" finalizer that must log diagnostics absent from its result type; inline GraphQL list arg vs the `InputField*` rule). **Required:** clean rev 4 normative document, historical critiques moved to a separate record, typed attribution methods, typed audit metadata/diagnostics, Freezed entities where required.

### Product sign-offs (verbatim decisions)

**S1 — negatively evaluated commitment paths.** Agreed real semantic bug. A negatively evaluated commitment may produce **neutral route-learning evidence** but must not be classified as an unobserved/unsuccessful route. Mapping:

```text
commitment evaluation     direct commitment bin     propagated forward bin
no_effect                 no_effect                 no_effect
good                      good                      good
very_good                 very_good                 very_good
bad                       bad                       no_effect
very_bad                  very_bad                  no_effect
```

Distinguish: `observedOutcomePairs` = paths for **every** finalized author evaluation, including bad/very_bad; propagated outcome evidence uses the mapping above; `noObservedOutcomePairs` = eligible forwarding pairs minus `observedOutcomePairs`. Negative commitment paths emit a distinct `source_type = negative_commitment_route_no_effect` with `bin = no_effect`; they must **not** emit `no_observed_route_effect`-class events (`unsuccessful_request_forward`), which remain reserved for forwarding relations that produced no finalized evaluated commitment at all. Remove the early gate that made propagation depend on the presence of a non-negative commitment (it made a negative-only request emit no route evidence while the same negative path received `no_effect` when a positive commitment coexisted).

**S2 — mutual-visibility rootless branches never learn in v1: fine.** There is no generic visibility for requests — they require explicit forward from the author, so the rootless situation should never arise.

**S3 — re-review freeze: valid concern; resolve by forbidding re-opening.** Closed (already reviewed, evidence-applied) requests can never be re-opened. Offset: the existing affordance to duplicate a request. The closed request's room may stay active, but the beacon screen/room must show a **non-closable banner** stating the request is closed and no further evidence or notifications will be produced from it.

**S4 — audit data survives user deletion: fine**, as long as it contains no real names or user-generated texts — those are scraped on deletion to anonymize the account.
