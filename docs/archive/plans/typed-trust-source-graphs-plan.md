# Typed trust source graphs & forward trust propagation — implementation plan

- **Status:** rev 6, draft for review — do NOT implement until approved. Rev 6 completes the rev-5 response to overengineering findings O1–O8 (resolution map in §13): separate source and effective tables; database-only policy frozen at runtime; reuse of the existing `MutatingUnitOfWorkPort`; one quiesced cutover release; no feature-specific lease, compatibility release, runtime policy control plane, speculative model column, verbose audit payload, or reverse-SQL rollback. It also removes the stale rev-4 instructions that survived the first rewrite and makes the future policy-migration contract pre-serve and failure-safe. Where an older revision conflicts with this text, this text wins.
- **Source spec:** [`/plan_forward.md`](../../plan_forward.md) (product/math spec) **as amended by** [`typed-trust-correction-patch-1.md`](typed-trust-correction-patch-1.md) (bin-preserving vector consolidation) **and by the rev-3 product sign-offs S1–S4** (recorded verbatim in the review record). Precedence: sign-offs > patch > spec.
- **Date:** 2026-07-19.
- **Audience:** an implementing LLM/engineer with no prior context. Every referenced file, function and column was verified against the codebase on the date above; `file:line` anchors may drift a few lines but the symbols are exact.

---

## 0. How to use this document

1. Implement **phase by phase, in order**. Each phase ends in a compiling, testable state.
2. Never edit an existing migration file (`packages/server/lib/data/database/migration/m0001.dart` … `m0121.dart`). Migrations are append-only; all schema work goes into **one new** file `m0122.dart`, registered at the end of the list in `_migrations.dart`.
3. After any change to Injectable-annotated classes or Drift tables run, from `packages/server/`:
   `dart run build_runner build --delete-conflicting-outputs`
4. Follow the repo layer contract (`.cursor/rules/architecture.mdc`, condensed in `.claude/skills/clean-architecture/SKILL.md`): **UI → Data → Domain → nothing**. Domain code (`packages/server/lib/domain/**`) must not import `data/` or Drift/postgres types. Data may import domain (including the pure algorithm classes added here). **Use cases orchestrate; repositories remain data sources** (`architecture.mdc` "Use cases orchestrate") — this plan adds a finalization use case precisely to honor that rule.
5. User-facing terminology is **Request** («запрос»); code and DB identifiers stay `beacon` (see `.cursor/rules/terminology.mdc`). Do not rename existing identifiers.
6. `sql/triggers.sql` is a human-reference mirror of trigger/function SQL. When you change SQL functions in a migration, update the same function text there too. It is **not** executed by the server.
7. Verification loop per phase, from `packages/server/`:
   - `dart analyze`
   - `dart test -x pg` (pure/unit tests)
   - `dart test -t pg` (Postgres-integration tests; requires the local compose stack from `compose.dev.yaml` — see `.claude/skills/local-debug/SKILL.md`)
8. Do **not** touch the MeritRank engine itself (`pgmer2` extension, `mr_*` functions). Only change what Tentura sends to it.

---

## 1. Verified current state (read this before coding)

### 1.1 Trust storage & math (SQL-owned)

- Table `public.user_trust_edge` created in `m0088.dart`: columns `subject`, `object`, `s_very_bad`, `s_bad`, `s_no_effect`, `s_good`, `s_very_good` (double precision, default 0), `anchor_at`, `prev_sent_weight`, `created_at`, `updated_at`; `PRIMARY KEY (subject, object)`; FKs to `public."user"`. There is **no** `trust_context` column today. Note the existing published-weight column is named **`prev_sent_weight`**, not `prev_published_weight` as in the spec — keep the existing name.
- `public.trust_edge_weight(vb, b, ne, g, vg, f)` (immutable SQL, `m0088.dart:29`): `(f*(-5vb - b + g + 5vg)) / (5 + f*(vb+b+ne+g+vg))`. `f` is the decay factor applied to the stored (inflated) sums.
- `public.trust_apply_evidence(_subject, _object, _bin, _count, _half_life_seconds, _epsilon)` — **current definitive version is in `m0114.dart` (~line 585)**, not m0088. It: upserts the row (anchor fixed on conflict), inflates the bump by `2^((now-anchor)/half_life)`, adds it to one bin, computes the deflated weight, and if `|w - prev_sent_weight| > epsilon` calls `mr_put_edge(subject, object, w, '', 0)` and advances `prev_sent_weight`. It also manages the transaction-local GUC `tentura.suppress_relationship_notify` so the realtime relationship fan-out fires exactly once per apply.
- `public.meritrank_sweep(_half_life, _epsilon)` — defined **only** in `m0088.dart:108` (never redefined later); loops all rows, recomputes deflated weight, epsilon-gated `mr_put_edge`. Nothing in the Dart server currently schedules it (only a comment in `sql/triggers.sql:196`).
- `public.trust_resync_source(_subject, _half_life)` and `public.trust_recompute_all(_half_life)` — definitive versions in `m0114.dart` (~lines 505–575), both set `tentura.suppress_relationship_notify`. `trust_recompute_all` is now a single set-based UPDATE of `prev_sent_weight` (no `mr_put_edge`); the Dart caller follows it with `mr_reset()` + `meritrank_init()`.
- `public.meritrank_init()` — defined only in `m0088.dart:227`. Bulk-loads via `mr_bulk_load_edges` a UNION of: all `user_trust_edge` rows (`prev_sent_weight` as weight), plus polling edges (`polling_variant→polling`, `polling_act` author edges). Any schema change must keep the polling edges intact.
- `public.user_trust_edge_degree(node_id, positive_only)` — definitive version in `m0109.dart`: `COUNT(DISTINCT neighbor)` over `user_trust_edge` where `subject=node OR object=node` and optionally `prev_sent_weight > 0`. Consumed by `public.graph(...)` (`m0108.dart`), which wraps `mr_graph` for the client graph screen. **Rev 6: `user_trust_edge` remains the effective projection unchanged, so this function (and `graph`, `meritrank_init`, the realtime triggers, the Drift table) need no changes.**
- Realtime: statement-level triggers `trust_edge_relationship_{insert,update,delete}_notify` on `user_trust_edge` (created in `m0114.dart`, ~lines 776–800) call `notify_relationship_change()`, which chunks by `subject` and emits `relationship` realtime events unless the transaction-local GUC `tentura.suppress_relationship_notify` is `'1'`.

### 1.2 Dart trust layer (server)

- `packages/server/lib/domain/trust/trust_bin.dart` — `TrustBin` enum (`very_bad`…`very_good`), `kTrustVoteEvidenceCount = 3`, `kTrustReviewEvidenceCount = 1`.
- `packages/server/lib/domain/trust/trust_evidence.dart` — `TrustEvidence {targetUserId, bin, count}` and `TrustEvidenceBatch {sourceUserId, at, items}`.
- `packages/server/lib/domain/trust/trust_math.dart` — `reviewValueToBin(int)` (maps `BeaconEvaluationValue` codes) and `voteAmountToBin(int)`.
- `packages/server/lib/data/repository/user_trust_edge_repository.dart` (`UserTrustEdgeRepository`, implements `domain/port/user_trust_edge_repository_port.dart`): `_applyEvidenceItem` runs `SELECT trust_apply_evidence($1..$6)`; `applyEvidenceInTransaction` wraps items in savepoints; `setVoteAmount*` maintain the `vote_user` table and emit vote evidence; `forceRefreshStar` → `trust_resync_source`; `forceRefreshAll` → `trust_recompute_all` + `_meritrank.reset()` + `_meritrank.init()`; `cutoverBackfillIfNeeded` backfills trust edges from `vote_user` on an empty table (called at startup from `packages/server/lib/app/app.dart:30`).
- `packages/server/lib/data/repository/meritrank_repository.dart` — thin wrapper over `meritrank_init`, `mr_reset`, `mr_put_edge`, `mr_delete_edge`, `mr_recalculate_clustering`.
- Drift table `packages/server/lib/data/database/table/user_trust_edges.dart` (`UserTrustEdges`, tableName `user_trust_edge`) mirrors the SQL columns; PK `{subject, object}`.
- Env knobs (`packages/server/lib/env.dart`): `trustEdgeHalfLife` (`TRUST_EDGE_HALF_LIFE_DAYS`, default 182 days) and `trustEdgeEpsilon` (`TRUST_EDGE_EPSILON`, default 0.1); documented in `.env.example:103-104`.

### 1.3 Evidence producers today

| Producer | Where | Evidence |
| --- | --- | --- |
| User vote (subscribe/like person) | `UserTrustEdgeCase.setUserVote` → `UserTrustEdgeRepository._setVoteAmountCore` | bin from `voteAmountToBin(amount)`, count 3 |
| Mutual invite accept | `packages/server/lib/data/repository/user_repository.dart` `_applyReciprocalTrustEdges` (~line 865) | reciprocal `good`, count 3, plus `vote_user` rows |
| Finalized request evaluations | `packages/server/lib/data/repository/evaluation_repository.dart` `closeBeaconReviewWindow` (~line 387) | per final evaluation: `reviewValueToBin(value)`, count 1, evaluator → evaluated |
| Startup backfill | `UserTrustEdgeRepository.cutoverBackfillIfNeeded` | votes → bins, count 3 |

### 1.4 Request/evaluation lifecycle (the finalization hook)

- Tables (`m0019.dart`): `beacon_review_window` (PK `beacon_id`; `status` 0 open / 1 closed; `opened_at`, `closes_at`), `beacon_evaluation_participant` (`role`: 0 author / 1 committer / 2 forwarder — `packages/server/lib/domain/evaluation/evaluation_participant_role.dart`), `beacon_evaluation` (PK `(beacon_id, evaluator_id, evaluated_user_id)`, `value` int, `status` added in `m0021.dart`: 0 draft / 1 submitted / 2 final), `beacon_review_status`.
- Evaluation values (`packages/server/lib/domain/evaluation/beacon_evaluation_value.dart`): `noBasis=0, neg2=1, neg1=2, zero=3, pos1=4, pos2=5`; helper `BeaconEvaluationValue.isPositive(v)` ⇔ `v ∈ {4, 5}`.
- **`EvaluationRepository.closeBeaconReviewWindow(beaconId, {reason, actorUserId})` is the single request-outcome finalization point today.** Inside one `_db.transaction` it: no-ops if window status ≠ 0; sets window status 1; sets beacon status to closed (6); marks review statuses; transitions all `submitted` evaluations to `final` via one `UPDATE … RETURNING`; converts them to `TrustEvidence` batches and applies them via `_trustEdgeRepository.applyEvidenceInTransaction`. All close paths funnel here: author "close now" (`EvaluationCase.closeNow`), lazy expiry (`EvaluationCase._ensureExpiredClosed` → `closeExpiredWindows`), and the background sweep (`AttentionExpirySweepCase.runDue`, driven every ≥1 min by `TaskWorkerCase` in `packages/server/lib/domain/use_case/task_worker_case.dart`). **This plan moves the orchestration out of the repository into a use case (Phase 5); the repository keeps typed load/store operations only.**
- There is also a re-scaffold flow: `EvaluationCase` → `deleteReviewScaffoldingForBeacon` (`evaluation_repository.dart:342` — deletes the `beacon_review_window` row outright) followed by a fresh `insertReviewWindow(status: 0)`. **This plan forbids that flow for already-closed requests (sign-off S3, decision 12).**
- `AttentionExpirySweepCase.runDue` currently wraps **all** due beacons in one `runAction` transaction — with atomic finalization (decision 19) this becomes per-beacon transactions (Phase 5.4).
- "Committer" in product terms = a help offerer (`beacon_help_offer`, `status 0` = active) acknowledged through coordination (`EvaluationParticipantGraphBuilder` in `packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart` selects `acknowledgedCommitters` and records them as role-1 participants).

### 1.5 Forwarding provenance (already exists)

- Table `public.beacon_forward_edge` (`m0014.dart`): `id` ('F…'), `beacon_id`, `context`, `sender_id`, `recipient_id`, `note`, `parent_edge_id` (self-FK, `ON DELETE SET NULL`), `batch_id`, `created_at`; plus `cancelled_at`, `recipient_read_at` added in `m0058.dart`. One row per sender→recipient forward.
- `ForwardCase.forward` (`packages/server/lib/domain/use_case/forward_case.dart:116`) creates a batch (`batchId = generateId('X')`), resolves one provenance parent via `resolveForwardParentEdgeId` (`packages/server/lib/domain/coordination/resolve_forward_parent_edge.dart`): client-supplied parent (validated as the sender's active inbound edge) → direct author→sender edge → most recent active inbound edge → `null` for the author or mutual-visibility first-hop senders. Note: `fetchActiveInboundEdges` runs **before** the write transaction (`forward_case.dart:152`) — a TOCTOU window this plan closes for attribution (decision 8).
- GraphQL: mutation `beaconForward(id, recipientIds, note, perRecipientNotes, context, parentEdgeId, reasons, recipientReasons)` in `packages/server/lib/api/controllers/graphql/mutation/mutation_forward.dart`; queries `beaconForwardGraph` (`query_forward_graph.dart` → `BeaconForwardGraphCase`, which guards on `canReadInvolvement` — `beacon_forward_graph_case.dart:45`) and `beaconHelpOffererForwardPath`. `ForwardEdgeRepositoryPort` already offers `fetchByBeaconId`, `fetchActiveInboundEdges`, `findActiveEdge`, `isDirectAuthorForward`, recursive `fetchHelpOffererPathChain`.
- Client feature `packages/client/lib/features/forward/` (data/domain/ui + `gql/*.graphql`, e.g. `forward_beacon.graphql`).
- **There is no attribution table and no forward-outcome learning today.** Forward edges never produce trust evidence.

### 1.6 Test & tooling conventions

- Postgres-integration tests are tagged `@Tags(['pg'])` and self-skip when Postgres is unreachable (pattern: `packages/server/test/data/repository/user_trust_edge_degree_test.dart`). Unit runs use `dart test -x pg`.
- Existing tests that will need updating: `test/data/repository/user_trust_edge_degree_test.dart` (inserts raw `user_trust_edge` rows), `test/domain/use_case/user_trust_edge_case_test.dart` (+ its mocks), evaluation close tests under `test/domain/evaluation/`.
- Migration framework: `package:migrant` with `migrant_db_postgresql`; each `Migration('NNNN', [sql, …])` is a list of SQL statements applied in order at startup (`migrateDbSchema` in `_migrations.dart`, invoked from `app.dart` before DI). The gateway applies **all statements of one migration plus its version row in a single transaction**, so a failed statement rolls the whole migration back cleanly. Idempotent statements (`IF NOT EXISTS` / `CREATE OR REPLACE` / guarded `DO $$` blocks) are still the house style — treat them as defense-in-depth, not as a correctness requirement.
- GraphQL list arguments must be defined as `InputField*` classes (`input_field_*.dart` as `part of '_input_types.dart'` under `packages/server/lib/api/controllers/graphql/input/`), never inline `GraphQLListType` in the mutation file (`architecture.mdc` §Server GraphQL).

---

## 2. Terminology map (spec ⇄ codebase)

| Spec term | Codebase term |
| --- | --- |
| request | `beacon` |
| request author | `beacon.user_id` / `beacon.author.id` |
| commitment / committer | acknowledged help offer / role-1 `beacon_evaluation_participant` |
| finalized request evaluation | `beacon_evaluation` row with `status = 2 (final)` |
| request outcome finalization | planned `ReviewFinalizationCase.closeAndFinalize` (Phase 5) |
| forwarding edge | `beacon_forward_edge` row |
| forwarding decision / batch | `beacon_forward_edge.batch_id` group |
| `prev_published_weight` | existing column `prev_sent_weight` (name kept) |
| evaluated commitment | final `beacon_evaluation` with `evaluator_id = author`, `evaluated_user_id` a role-1 participant, `value ∈ {neg2 (1), neg1 (2), zero (3), pos1 (4), pos2 (5)}` — i.e. any bin-mappable value. `noBasis (0)` is never an observation. **Sign-off S1:** negative evaluations DO participate in route learning, as neutral (`no_effect`) route evidence with a distinct source type — see decision 4. |

---

## 3. Outcome mapping (normative — sign-off S1)

The single source of truth for how one finalized author evaluation of a committer turns into evidence:

| Author evaluation | Direct `commitment` bin (evaluator → evaluated, count 1 — unchanged today's path) | Propagated `forward` evidence along the committer's causal paths |
| --- | --- | --- |
| `noBasis (0)` | none | none (not an observation) |
| `neg2 (1)` | `very_bad` | `bin = no_effect`, `source_type = negative_commitment_route_no_effect` |
| `neg1 (2)` | `bad` | `bin = no_effect`, `source_type = negative_commitment_route_no_effect` |
| `zero (3)` | `no_effect` | `bin = no_effect`, `source_type = propagated_author_evaluated_commitment` |
| `pos1 (4)` | `good` | `bin = good`, `source_type = propagated_author_evaluated_commitment` |
| `pos2 (5)` | `very_good` | `bin = very_good`, `source_type = propagated_author_evaluated_commitment` |

Derived sets, per finalized request:

- **`observedOutcomePairs`** — every `(sender, recipient)` pair lying on an eligible causal path of **any** evaluated commitment, including negatively evaluated ones.
- **Propagated outcome evidence** — emitted for `observedOutcomePairs` per the mapping above, budget-normalized (decision 5).
- **`noObservedOutcomePairs`** — eligible forwarding pairs (computed against `finalizedAt`) **minus** `observedOutcomePairs`; these get `source_type = unsuccessful_request_forward`, `bin = no_effect`, undivided count. `unsuccessful_request_forward` is **reserved exclusively** for forwarding relations that produced no finalized evaluated commitment at all — a negatively evaluated path is *observed*, never *unsuccessful*.

**Gate (replaces the rev-3 "non-negative" gate):** forward emission requires **≥ 1 finalized author evaluation of a role-1 committer with a bin-mappable value** (anything except `noBasis`). A request whose author evaluated nothing (or only `noBasis`) emits no forward evidence of any kind — with zero observations we cannot distinguish bad routing from a doomed request. The old gate's additional "non-negative" condition is **removed** (S1): a negative-only request now emits `negative_commitment_route_no_effect` on its observed paths and `unsuccessful_request_forward` on its unobserved eligible pairs, exactly like any other evaluated request.

---

## 4. Fixed v1 design decisions

1. **Schema strategy: new source table `user_trust_source_edge`; `user_trust_edge` stays the effective projection, unchanged (rev-4 finding O1).** Source accumulators and the effective projection have different invariants (`prev_sent_weight` is meaningful only for effective rows; source writes must not fan out realtime), so they get different tables. There is no PK swap, no context column or effective twin added to the existing table, and no trigger suppression on source writes. Migration makes one lossless source copy of each existing effective row; every existing effective consumer (`meritrank_init`, `user_trust_edge_degree`, `graph`, realtime triggers, Drift `UserTrustEdges`) keeps working untouched.
2. **Contexts:** stored source rows use `personal`, `commitment`, `forward`, `legacy`; the source-table CHECK admits exactly those four. Runtime `TrustContext` and the evidence ledger admit only the three writable contexts (`personal`, `commitment`, `forward`). `legacy` is migration-only, and `trust_apply_source_evidence` rejects it, so “no new legacy evidence” is enforced rather than conventional. There is no `effective` context — effectiveness is a table, not a context value. No `model_kind` column anywhere (rev-4 finding O7): the projector is hardcoded to five Dirichlet bins and non-Dirichlet models are a non-goal; add the column when a second model exists (the source spec explicitly permits omitting it in v1).
3. **Policy is database-authoritative and frozen in v1 (rev-4 finding O2).** New single-row `trust_policy` table owns `half_life_seconds`, `epsilon`; SQL functions read it directly — half-life and epsilon are **removed from every function signature**. The DB is the *sole* canonical value: `TRUST_EDGE_HALF_LIFE_DAYS` / `TRUST_EDGE_EPSILON` are removed from `env.dart` and `.env.example` (there is no env/DB equality check — a second canonical copy is what the check would exist to babysit). There is deliberately **no per-context half-life** and **no runtime reconfiguration**. Before m0122 is approved, choose the one product policy for every environment and freeze it in the migration; a pre-existing production env override is an input to that decision, not an environment-specific edit made while deploying. Any later policy change is a separate audited, quiesced migration that re-anchors under the old half-life when necessary, rebuilds the whole effective projection, and resets MeritRank **before web workers start** (§10.2).
4. **Evidence taxonomy (S1).** Source types written in v1: `user_vote`, `finalized_request_evaluation`, `propagated_author_evaluated_commitment`, `negative_commitment_route_no_effect`, `unsuccessful_request_forward`. Nothing else — `recipient_forward_relevance_feedback` and other speculative values are **omitted** (add them when a feature needs them; rev-3 finding 7). Ledger idempotency indexes (§5.4): (4a) propagated outcome events (both propagated source types) unique on `(trust_context, source_type, request_id, subject, object, bin)`; (4b) `unsuccessful_request_forward` unique per `(trust_context, request_id, subject, object)` (no `source_type` in the key — there is one such type); (4c) general request-scoped index for commitment evidence. Personal votes (`request_id NULL`) delegate replay protection to the vote state machine (`_setVoteAmountCore` no-ops on unchanged amount) — **which is sound only because evidence write and vote write are atomic** (decision 19): a vote can no longer commit while its evidence fails.
5. **Bin-preserving vector consolidation (correction patch 1, extended by S1).** Every evaluated commitment contributes `observation_weight = 1.0` of causal mass regardless of bin (value differences come solely from the Dirichlet utility mapping — a bin-dependent weight would double-count valence, patch §2). Per-commitment local shares are accumulated into per-`(sender, recipient, bin, provenance)` support, where `provenance ∈ {evaluated, negativeRoute}` (S1: negative commitments accumulate into `no_effect` support under `negativeRoute`; non-negative under `evaluated` with their preserved bin). One bounded `evaluated_outcome_budget = 1.0` per (sender, request) is normalized across **all** of a sender's `(recipient, bin, provenance)` cells: `delta = budget × R/Z(u)`, `Z(u) = Σ R`; `Z(u) = 0` ⇒ nothing emitted for that sender. Mixed evidence on one pair (several bins, or evaluated + negativeRoute `no_effect`) is legitimate and never collapsed, maxed or averaged. Route-failure `no_effect` stays **outside** this budget, full configured count per pair, never divided; minimum opportunity interval default 24 h (env). Known accepted property (patch): summed support means commitment count behind a branch influences relative shares; totals stay bounded at 1.0 per sender.
6. **Old combined rows are copied into `legacy` source rows losslessly; the existing `user_trust_edge` rows stay in place as the effective projection** (bins, `anchor_at`, `prev_sent_weight` untouched; legacy multiplier 1 ⇒ bit-identical weight at cutover; no republication, no zeroing pass). `legacy` receives no new evidence ever.
7. **SQL owns** Dirichlet mutation, decay normalization, effective projection, pair-level locking, epsilon-gated publication. **Dart domain owns** eligibility, DAG building, mass propagation, normalization, consolidation as pure classes; **a use case owns the finalization workflow and transaction boundary** (decision 14).
8. **Attribution is server-authoritative (rev-3 finding 4).** Persisted rows: explicit user answers (`explicit_single`/`explicit_multiple`) and `opened_via` (weight 1) when the client supplied `parentEdgeId`. Server-auto-resolved parents (author-direct / most-recent-inbound heuristics) are **never** persisted as attribution — the server must not launder its own guess into an apparent user decision. Enforcement moves inside the forwarding transaction (Phase 4): the inbound set is re-validated and locked (`FOR SHARE`) in-transaction; first-episode semantics (`attribution accepted only on the sender's first outgoing batch for this beacon, cancelled batches included`) are checked server-side in the same transaction; duplicate ids and lists larger than `kMaxAttributionParents = 16` are rejected; attribution rows are written only if `createBatch` actually inserted recipients. The `attribution_method` CHECK admits exactly the three written values — no reserved values (rev-3 finding 7). Finalization priority: `explicit_*` → `opened_via` → equal fallback across distinct eligible inbound senders.
9. **Fallback equality is per distinct sender**, not per edge, everywhere — including the terminal seed at the committer (a plan decision filling a spec gap; spec §Terminal mass only defines "mass 1.0 at the committer").
10. **Commitment timestamp** for eligibility = the committer's `beacon_help_offer.created_at` (fallback: `beacon_review_window.opened_at`). Withdraw/re-offer cycles reuse the row without touching `created_at` (verified: `help_offer_repository.dart` `upsert` `DoUpdate` sets only message/helpType/status/updated_at), so `commitmentAt` is the *first* offer time — errs conservatively (can only under-credit; no late forward ever gains credit, which the spec hard-requires). Accept for v1. Rootedness: an eligible parentless edge must have `sender_id = author`. Mutual-visibility rootless branches never learn in v1 — **signed off (S2)**: requests have no generic visibility, they require explicit forward from the author, so the rootless situation should not arise in practice; the finalizer still counts rootless edges in diagnostics so a violation of that assumption is visible.
11. **Episode integrity is transactional, not best-effort (rev-3 blocker 1).** A finalization episode (window close + evaluation transition + commitment evidence + forward evidence, ledger + source mutations) commits **atomically or not at all**. The evidence writer skips only *expected* idempotency conflicts (`ON CONFLICT DO NOTHING` returning no row); any other failure aborts the whole close transaction so the caller (author close-now / lazy expiry / background sweep) retries the complete episode later. MeritRank *publication* remains independently deferred-on-failure (decision 13) — an engine outage delays publication, never evidence. There is no partial-episode state to repair, so the episode gate (decision 12) is a plain "already finalized ⇒ no-op" check, not a freeze that can strand missing items.
12. **Closed requests are never re-opened (sign-off S3).** The re-scaffold flow is forbidden once a request's review window has closed with evidence applied: the guard rejects `deleteReviewScaffoldingForBeacon` + re-insert for beacons with a closed window (Phase 5.3). Users who need another round duplicate the request (existing affordance). The closed request's room may stay active, but the beacon screen/room shows a non-closable banner: the request is closed, no further evidence or notifications will be produced (Phase 5.5). Defense-in-depth: the finalizer still checks `EXISTS (SELECT 1 FROM trust_evidence_event WHERE request_id = $beacon AND trust_context = 'forward')` and no-ops — with atomic episodes (decision 11) "any event exists" now genuinely means "the complete episode exists".
13. **Publication is deferred-on-failure, never blocking.** `mr_put_edge` inside the effective rebuild is wrapped in a plpgsql `EXCEPTION` block: on engine failure the effective row still commits, `prev_sent_weight` does **not** advance, a WARNING is raised, and the next rebuild or sweep republishes automatically. Deletions get the same durability through tombstones (decision 15).
14. **Orchestration lives in a use case (rev-3 finding 3), on the *existing* transaction seam (rev-4 finding O3).** New `ReviewFinalizationCase` owns the finalization workflow; its transaction boundary is the already-existing `MutatingUnitOfWorkPort` (`packages/server/lib/domain/port/mutating_unit_of_work_port.dart`, implemented by `MutatingUnitOfWork` over `TenturaDb`). No new `TransactionRunnerPort`, no Zone-based `isInTransaction` flag — a second competing definition of the application transaction boundary is exactly the kind of accidental complexity this plan must not add. The evidence writer's transactional requirement is a documented contract verified by the atomicity tests (§12), not an ambient-state runtime probe. `EvaluationRepository` is reduced to typed load/store operations. The pure finalizer returns typed evidence **plus typed diagnostics** (`ForwardFinalizationDiagnostics`) — it never logs or skips internally; the use case logs.
15. **Deleted users must not leave stale MeritRank edges (rev-3 finding 5).** The `AFTER DELETE` trigger on published effective rows attempts `mr_delete_edge`; on failure it writes a durable row to `meritrank_edge_tombstone` instead of merely WARNING. The maintenance sweep drains tombstones (retry `mr_delete_edge`, delete the tombstone on success; discard the tombstone if the pair has a live republished effective row). Deletion therefore converges automatically after an engine outage.
16. **Pair serialization uses one stable per-pair advisory lock (rev-3 blocker 2).** `trust_pair_lock(subject, object)` (`pg_advisory_xact_lock` on a hash of the pair) is acquired **before any context-row read or mutation** by both `trust_apply_source_evidence` and `trust_rebuild_effective_edge`. Writers touch a request-sized, sorted set of pairs — no exhaustion risk (the rev-1 exhaustion concern applied to holding thousands of locks during a bulk sweep). Bulk operations never run as one giant transaction: the Dart maintenance driver calls `trust_rebuild_effective_batch` in **bounded batches** (default 200 pairs/transaction), each pair rebuilt under the same pair lock, ordered `(subject, object)` — the sweep can neither deadlock with writers on lock-order inversion nor overwrite a newer effective row with a stale aggregate (it aggregates only while holding the pair lock).
17. **Policy changes ship as quiesced migrations, not as a runtime control plane (rev-4 finding O2; supersedes the rev-4 `trustReconfigure` mutation).** Half-life, epsilon and context multipliers change only through a new audited migration following §10.2. The same migration transaction re-anchors under the old half-life when necessary and rebuilds the complete effective projection while the old application is stopped; its final external action resets MeritRank, and normal startup re-initializes the empty engine from the committed projection before spawning workers. A policy migration must never commit a new policy and leave the old projection serving until somebody invokes an admin endpoint. This removes the admin mutation, per-edge `config_version` epochs, environment reconciliation, and reconfigure/sweep lease. Direct ad-hoc SQL edits of `trust_policy`/`trust_context_config` remain prohibited; the migration is the interface.
18. **Quiesced one-release cutover (rev-4 finding O4; supersedes the mixed-fleet shim).** Production deployment stops the stack before starting the new version (`deploy.sh:99`) and runs one Tentura container (`compose.prod.yaml:107`) — there is no overlapping-binaries window to defend against. m0122 therefore **drops** the legacy function signatures outright (`trust_apply_evidence(6-arg)`, `meritrank_sweep`, `trust_recompute_all`, old `trust_resync_source`) and the Dart call-site changes ship in the same release. No compatibility shim, no m0123, no second release. If rolling multi-replica deployment is ever introduced, compatibility becomes a general deployment contract, not a feature-specific shim.
19. **Vote transactions keep their consistency guarantee.** `setVoteAmount*` wraps vote-row update and evidence write in one transaction, and with decision 11 an evidence failure aborts the vote update too — the unchanged-amount guard can never lock in a vote whose evidence was lost.
20. **Audit metadata is minimal and anonymizable by construction (sign-off S4; rev-4 finding O6).** `trust_evidence_event.metadata` contains **only** an `algorithm_version` int and indispensable provenance ids (`supporting_commitment_ids` for propagated cells, `attribution_method` for attribution-derived shares) — never display names, notes, any user-generated text, and **not** the algorithm's intermediate representation (raw masses, local shares, per-bin support, normalization denominators). Request-wide diagnostics live in the one structured `ForwardFinalizationDiagnostics` log line per finalization, not duplicated across every emitted cell — the immutable ledger must not be coupled to the current algorithm's internals. Writer invariant with a test (§12); account-deletion anonymization then needs no ledger scrubbing beyond the existing id-preserving account scrub.

---

## 5. Phase 1 — SQL migration `m0122` (schema + functions)

Create `packages/server/lib/data/database/migration/m0122.dart`, add `part 'm0122.dart';` and append `m0122` to the list in `_migrations.dart`. Statements, in order:

### 5.1 Source table (rev-4 finding O1 — `user_trust_edge` is not touched)

```sql
CREATE TABLE IF NOT EXISTS public.user_trust_source_edge (
  trust_context text NOT NULL CHECK (
    trust_context IN ('personal','commitment','forward','legacy')),
  subject text NOT NULL REFERENCES public."user"(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  object text NOT NULL REFERENCES public."user"(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  s_very_bad double precision NOT NULL DEFAULT 0,
  s_bad double precision NOT NULL DEFAULT 0,
  s_no_effect double precision NOT NULL DEFAULT 0,
  s_good double precision NOT NULL DEFAULT 0,
  s_very_good double precision NOT NULL DEFAULT 0,
  anchor_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (trust_context, subject, object)
);
CREATE INDEX IF NOT EXISTS user_trust_source_edge_pair_idx
  ON public.user_trust_source_edge (subject, object);
CREATE INDEX IF NOT EXISTS user_trust_source_edge_object_idx
  ON public.user_trust_source_edge (object);
```

No `prev_sent_weight`, no `config_version`: those belong to the effective projection (`user_trust_edge`), which keeps its schema, PK, FKs, triggers, Drift mapping and every consumer exactly as today. There are no triggers on the source table, so source writes need **no** notification-suppression GUC handling.

### 5.2 Policy & config tables

```sql
CREATE TABLE IF NOT EXISTS public.trust_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  half_life_seconds double precision NOT NULL
    CHECK (half_life_seconds >= 86400 AND half_life_seconds <= 3.2e9),
  epsilon double precision NOT NULL CHECK (epsilon >= 0 AND epsilon <= 1),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.trust_policy (half_life_seconds, epsilon)
VALUES (15724800, 0.1)  -- 182 days, 0.1 (verify against prod env before shipping — decision 3)
ON CONFLICT DO NOTHING;
```

```sql
CREATE TABLE IF NOT EXISTS public.trust_context_config (
  trust_context text PRIMARY KEY CHECK (
    trust_context IN ('personal','commitment','forward','legacy')),
  evidence_multiplier double precision NOT NULL
    CHECK (evidence_multiplier >= 0 AND evidence_multiplier <= 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.trust_context_config (trust_context, evidence_multiplier) VALUES
  ('legacy', 1.0), ('personal', 1.0), ('commitment', 1.0), ('forward', 0.20)
ON CONFLICT (trust_context) DO NOTHING;
```

CHECK bounds enforce "reject non-finite and unreasonable values" at the storage layer (`NaN`/`Infinity` fail the range checks; postgres `double precision` NaN compares false against both bounds). Half-life bounds: 1 day … ~101 years. Multiplier `0.0` disables a context (no separate `enabled` flag). No `model_kind` (decision 2), no `config_version` (decision 17 — policy changes are migrations). Doc-comment in the migration: multipliers scale evidence mass, not posterior weight; they need not sum to 1; every change follows the quiesced policy-migration contract in §10.2 — never direct SQL; a half-life change without re-anchoring corrupts all accumulators. All numeric values are empirical hypotheses.

### 5.3 Copy existing rows into `legacy` source rows

```sql
INSERT INTO public.user_trust_source_edge
  (trust_context, subject, object, s_very_bad, s_bad, s_no_effect, s_good,
   s_very_good, anchor_at, created_at, updated_at)
SELECT 'legacy', subject, object, s_very_bad, s_bad, s_no_effect, s_good,
       s_very_good, anchor_at, created_at, updated_at
FROM public.user_trust_edge
ON CONFLICT (trust_context, subject, object) DO NOTHING;
```

The existing `user_trust_edge` rows stay in place untouched (bins, `anchor_at`, `prev_sent_weight`); with legacy multiplier 1.0 the effective weight at any time `t` equals the pre-migration weight exactly — spec §Migration cutover satisfied with 0 tolerance, no republication, no zeroing pass, no relationship-notify suppression, no long lock: the only data motion is one INSERT…SELECT into a brand-new table.

### 5.4 Ledger, attribution, tombstone tables

```sql
CREATE TABLE IF NOT EXISTS public.trust_evidence_event (
  id text PRIMARY KEY DEFAULT concat('T', "substring"((gen_random_uuid())::text, '\w{12}')),
  trust_context text NOT NULL CHECK (
    trust_context IN ('personal','commitment','forward')),
  subject_user_id text NOT NULL,
  object_user_id text NOT NULL,
  bin text NOT NULL CHECK (bin IN ('very_bad','bad','no_effect','good','very_good')),
  count double precision NOT NULL CHECK (count >= 0 AND count <= 1e6),
  source_type text NOT NULL CHECK (source_type IN (
    'user_vote','finalized_request_evaluation',
    'propagated_author_evaluated_commitment',
    'negative_commitment_route_no_effect',
    'unsuccessful_request_forward')),
  source_id text,
  request_id text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  applied_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);
-- (4a) Propagated outcome events (both provenances): bin is part of evidence
-- identity (patch §10) — one (request, pair) may hold several bins and both
-- source types (mixed evidence), each at most once.
CREATE UNIQUE INDEX IF NOT EXISTS trust_evidence_event_propagated_unique
  ON public.trust_evidence_event
  (trust_context, source_type, request_id, subject_user_id, object_user_id, bin)
  WHERE request_id IS NOT NULL
    AND source_type IN ('propagated_author_evaluated_commitment',
                        'negative_commitment_route_no_effect');
-- (4b) Route-failure events: one per (request, pair).
CREATE UNIQUE INDEX IF NOT EXISTS trust_evidence_event_unsuccessful_unique
  ON public.trust_evidence_event
  (trust_context, request_id, subject_user_id, object_user_id)
  WHERE request_id IS NOT NULL
    AND source_type = 'unsuccessful_request_forward';
-- (4c) General request-scoped idempotency (commitment evidence).
CREATE UNIQUE INDEX IF NOT EXISTS trust_evidence_event_request_unique
  ON public.trust_evidence_event
  (trust_context, source_type, request_id, subject_user_id, object_user_id)
  WHERE request_id IS NOT NULL
    AND source_type NOT IN ('propagated_author_evaluated_commitment',
                            'negative_commitment_route_no_effect',
                            'unsuccessful_request_forward');
CREATE INDEX IF NOT EXISTS trust_evidence_event_pair_idx
  ON public.trust_evidence_event (subject_user_id, object_user_id, applied_at DESC);
CREATE INDEX IF NOT EXISTS trust_evidence_event_request_idx
  ON public.trust_evidence_event (request_id) WHERE request_id IS NOT NULL;
```

(No FK on `request_id`/user ids: the ledger is an immutable audit log and must survive entity deletion. **Metadata invariant — decision 20:** provenance ids, a version number and a constrained attribution-method enum only; no names/user text. The writer and tests enforce this because jsonb content cannot be CHECK-constrained practically.)

```sql
CREATE TABLE IF NOT EXISTS public.forward_decision_attribution (
  child_forward_batch_id text NOT NULL,
  parent_forward_edge_id text NOT NULL
    REFERENCES public.beacon_forward_edge(id) ON UPDATE CASCADE ON DELETE CASCADE,
  attribution_weight double precision NOT NULL
    CHECK (attribution_weight > 0 AND attribution_weight <= 1),
  attribution_method text NOT NULL CHECK (attribution_method IN
    ('explicit_single','explicit_multiple','opened_via')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (child_forward_batch_id, parent_forward_edge_id)
);
CREATE INDEX IF NOT EXISTS fda_parent_idx
  ON public.forward_decision_attribution (parent_forward_edge_id);
```

(Exactly the three methods v1 writes — no reserved values, decision 8.)

```sql
CREATE TABLE IF NOT EXISTS public.meritrank_edge_tombstone (
  subject text NOT NULL,
  object text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  PRIMARY KEY (subject, object)
);
```

No `task_lease` table (rev-4 finding O5): the application runs exactly one task-worker isolate (`packages/server/lib/app/app.dart:35`) in one server container, so the maintenance job uses the existing `TaskWorkerCase` scheduling like every other periodic task. If multi-replica workers ever become real, build one shared leasing facility for all periodic jobs — not a trust-specific one.

### 5.5 Pair lock & source-evidence function

```sql
CREATE OR REPLACE FUNCTION public.trust_pair_lock(_subject text, _object text)
RETURNS void LANGUAGE sql VOLATILE AS $$
  -- One stable transaction-scoped lock per (subject, object) pair, acquired
  -- BEFORE any context-row read or mutation (decision 16). Hash collisions
  -- only over-serialize; they never break correctness.
  SELECT pg_advisory_xact_lock(hashtextextended(_subject || chr(31) || _object, 4242));
$$;
```

```sql
CREATE OR REPLACE FUNCTION public.trust_apply_source_evidence(
  _context text,
  _subject text,
  _object text,
  _bin text,
  _count double precision
) RETURNS void
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _r public.user_trust_source_edge%ROWTYPE;
  _hl double precision;
  _f_inflate double precision;
  _bump double precision;
BEGIN
  IF _context = 'legacy' THEN
    RAISE EXCEPTION 'trust_apply_source_evidence: legacy is migration-only';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.trust_context_config WHERE trust_context = _context
  ) THEN
    RAISE EXCEPTION 'trust_apply_source_evidence: unknown context %', _context;
  END IF;
  IF _count IS NULL OR NOT (_count >= 0 AND _count <= 1e6) THEN
    RAISE EXCEPTION 'trust_apply_source_evidence: invalid count %', _count;
  END IF;

  -- Decision 16: stable pair lock FIRST — before touching any pair row.
  PERFORM public.trust_pair_lock(_subject, _object);

  SELECT half_life_seconds INTO STRICT _hl FROM public.trust_policy;

  -- Source table has no triggers: no realtime fan-out, no GUC handling needed.
  INSERT INTO public.user_trust_source_edge (trust_context, subject, object, anchor_at)
  VALUES (_context, _subject, _object, now())
  ON CONFLICT (trust_context, subject, object) DO UPDATE SET updated_at = now()
  RETURNING * INTO _r;

  _f_inflate := pow(2,
    greatest(EXTRACT(EPOCH FROM (now() - _r.anchor_at)), 0) / _hl);
  _bump := _count * _f_inflate;

  UPDATE public.user_trust_source_edge SET
    s_very_bad  = s_very_bad  + CASE WHEN _bin = 'very_bad'  THEN _bump ELSE 0 END,
    s_bad       = s_bad       + CASE WHEN _bin = 'bad'       THEN _bump ELSE 0 END,
    s_no_effect = s_no_effect + CASE WHEN _bin = 'no_effect' THEN _bump ELSE 0 END,
    s_good      = s_good      + CASE WHEN _bin = 'good'      THEN _bump ELSE 0 END,
    s_very_good = s_very_good + CASE WHEN _bin = 'very_good' THEN _bump ELSE 0 END,
    updated_at = now()
  WHERE trust_context = _context AND subject = _subject AND object = _object;
END; $$;
```

Invariants: anchor never advances on evidence; VSIDS inflation identical to today; no `mr_put_edge` here; half-life read from `trust_policy` inside the same transaction — no caller-supplied half-life can diverge (decision 3). Writes to the effective table happen only in the rebuild function; the source table cannot fan out realtime because it has no triggers — the whole suppress/restore GUC dance of rev 4 is gone.

### 5.6 Effective projector/publisher

```sql
CREATE OR REPLACE FUNCTION public.trust_rebuild_effective_edge(
  _subject text,
  _object text,
  _epsilon_override double precision DEFAULT NULL
) RETURNS double precision
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _now timestamptz := now();
  _hl double precision;
  _eps double precision;
  _vb float8; _b float8; _ne float8; _g float8; _vg float8;
  _prev float8;
  _w float8;
BEGIN
  -- Decision 16: same stable pair lock as the evidence writer, acquired first.
  -- A writer that already holds it in this transaction re-enters for free;
  -- concurrent writers/rebuilds of this pair serialize here, so the aggregate
  -- below can never be computed from a snapshot older than a committed rebuild.
  PERFORM public.trust_pair_lock(_subject, _object);

  SELECT half_life_seconds, epsilon INTO STRICT _hl, _eps FROM public.trust_policy;
  _eps := COALESCE(_epsilon_override, _eps);

  SELECT
    COALESCE(sum(c.evidence_multiplier * e.s_very_bad  * d.f), 0),
    COALESCE(sum(c.evidence_multiplier * e.s_bad       * d.f), 0),
    COALESCE(sum(c.evidence_multiplier * e.s_no_effect * d.f), 0),
    COALESCE(sum(c.evidence_multiplier * e.s_good      * d.f), 0),
    COALESCE(sum(c.evidence_multiplier * e.s_very_good * d.f), 0)
  INTO _vb, _b, _ne, _g, _vg
  FROM public.user_trust_source_edge e
  JOIN public.trust_context_config c
    ON c.trust_context = e.trust_context AND c.evidence_multiplier > 0
  CROSS JOIN LATERAL (
    SELECT pow(2, -greatest(EXTRACT(EPOCH FROM (_now - e.anchor_at)), 0) / _hl) AS f
  ) d
  WHERE e.subject = _subject AND e.object = _object;

  -- Bins are deflated to _now, so weight uses decay factor 1.
  _w := public.trust_edge_weight(_vb, _b, _ne, _g, _vg, 1);

  SELECT prev_sent_weight INTO _prev FROM public.user_trust_edge
  WHERE subject = _subject AND object = _object;
  _prev := COALESCE(_prev, 0);

  -- Effective-row write is the user-visible relationship change: the existing
  -- m0114 statement triggers fire normally (not suppressed).
  INSERT INTO public.user_trust_edge
    (subject, object, s_very_bad, s_bad, s_no_effect,
     s_good, s_very_good, anchor_at, prev_sent_weight)
  VALUES (_subject, _object, _vb, _b, _ne, _g, _vg, _now, _prev)
  ON CONFLICT (subject, object) DO UPDATE SET
    s_very_bad = EXCLUDED.s_very_bad, s_bad = EXCLUDED.s_bad,
    s_no_effect = EXCLUDED.s_no_effect, s_good = EXCLUDED.s_good,
    s_very_good = EXCLUDED.s_very_good, anchor_at = EXCLUDED.anchor_at,
    updated_at = now();

  IF abs(_w - _prev) > _eps THEN
    -- Deferred-on-failure publication (decision 13): an engine outage must
    -- not abort evidence writes or review-window closes. prev_sent_weight
    -- stays behind, so the next rebuild/sweep republishes automatically.
    BEGIN
      PERFORM mr_put_edge(_subject, _object, _w, ''::text, 0);
      UPDATE public.user_trust_edge SET prev_sent_weight = _w, updated_at = now()
      WHERE subject = _subject AND object = _object;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'trust_rebuild_effective_edge: publish %->% deferred: %',
        _subject, _object, SQLERRM;
    END;
  END IF;

  RETURN _w;
END; $$;
```

Notes: when every source decays to ~0, `_w` approaches 0 and, past epsilon drift, a **zero edge is published** (spec §Effective-edge rebuild); rows are never deleted in v1 except via user-deletion cascades (reconciled by §5.8 tombstones). `prev_sent_weight` advances only in the same subtransaction as a **successful** `mr_put_edge`. There is deliberately no no-publish/bookkeeping mode: a multi-transaction rebuild must never make rows look published before the external engine accepted them.

```sql
CREATE OR REPLACE FUNCTION public.trust_rebuild_effective_batch(
  _after_subject text,
  _after_object text,
  _limit integer,
  _epsilon_override double precision DEFAULT NULL
) RETURNS TABLE (last_subject text, last_object text, processed integer)
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _pair record;
  _n integer := 0;
  _ls text := NULL; _lo text := NULL;
BEGIN
  IF _limit IS NULL OR _limit < 1 OR _limit > 10000 THEN
    RAISE EXCEPTION 'trust_rebuild_effective_batch: invalid limit %', _limit;
  END IF;
  -- Bulk maintenance keeps relationship realtime quiet (m0114 convention).
  -- Documented consequence: decay-driven effective drift surfaces on the
  -- client's next fetch, not via realtime push.
  PERFORM set_config('tentura.suppress_relationship_notify', '1', true);

  -- Distinct pairs from BOTH the source table and the effective table (an
  -- effective row whose sources were all deleted must be rebuilt down to
  -- zero), in stable (subject, object) order — the same order every writer
  -- uses, so lock acquisition order is globally consistent (decision 16).
  -- Each iteration rebuilds under the pair lock, so at most _limit locks are
  -- held per transaction (the Dart driver commits between batches).
  FOR _pair IN
    SELECT subject, object FROM (
      SELECT subject, object FROM public.user_trust_source_edge
      UNION
      SELECT subject, object FROM public.user_trust_edge
    ) p
    WHERE (subject, object) > (_after_subject, _after_object)
    ORDER BY subject, object
    LIMIT _limit
  LOOP
    PERFORM public.trust_rebuild_effective_edge(
      _pair.subject, _pair.object, _epsilon_override);
    _n := _n + 1;
    _ls := _pair.subject; _lo := _pair.object;
  END LOOP;

  RETURN QUERY SELECT _ls, _lo, _n;
END; $$;
```

The runtime driver loop (§10.3) starts at `('', '')` and repeats until `processed < _limit`, one transaction per call. There is deliberately **no runtime single-transaction full-table rebuild function**: rev-3's set-based sweep could aggregate an unlocked stale snapshot and overwrite newer rows; the batched form aggregates only under the pair lock and bounds advisory-lock consumption per transaction. A future policy-changing migration is the sole exception: it runs quiesced, before application workers exist, and owns its set-based rebuild as migration-local SQL (§10.2).

### 5.7 Drop superseded functions, redefine one-user resync

Quiesced one-release cutover (decision 18): the old binary is stopped before m0122 runs, and the new binary calls only the new functions, so the legacy signatures are **dropped outright** — no shims, no raising stubs, no m0123:

```sql
DROP FUNCTION IF EXISTS public.trust_apply_evidence(
  text, text, text, double precision, double precision, double precision);
DROP FUNCTION IF EXISTS public.meritrank_sweep(double precision, double precision);
DROP FUNCTION IF EXISTS public.trust_recompute_all(double precision);
DROP FUNCTION IF EXISTS public.trust_resync_source(text, double precision);
```

```sql
CREATE OR REPLACE FUNCTION public.trust_resync_source(_subject text)
RETURNS integer
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _pair record;
  _n integer := 0;
BEGIN
  PERFORM set_config('tentura.suppress_relationship_notify', '1', true);
  FOR _pair IN
    SELECT DISTINCT object FROM public.user_trust_source_edge
    WHERE subject = _subject
    ORDER BY object   -- consistent lock order
  LOOP
    -- epsilon override -1 => always republish (force-push semantics).
    PERFORM public.trust_rebuild_effective_edge(_subject, _pair.object, -1);
    _n := _n + 1;
  END LOOP;
  RETURN _n;
END; $$;
```

One-user resync stays per-pair (out-degree is small; lock count bounded) and rebuilds **outgoing pairs only** — spec §One-user resync literally says "rebuild and publish effective outgoing edges only". The Dart maintenance driver (Phase 6) is the only bulk path; a single-transaction bulk rebuild must not exist (decision 16).

`meritrank_init()` and `user_trust_edge_degree` are **unchanged** — they already read exactly the effective projection (`user_trust_edge`), which rev 6 leaves in place (decision 1). `public.graph(...)` from `m0108.dart` keeps working untouched.

### 5.8 Deletion reconciliation (tombstoned — decision 15)

```sql
CREATE OR REPLACE FUNCTION public.trust_edge_on_effective_delete()
  RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM mr_delete_edge(OLD.subject, OLD.object, ''::text);
    -- Success: any stale tombstone for this pair is settled.
    DELETE FROM public.meritrank_edge_tombstone
    WHERE subject = OLD.subject AND object = OLD.object;
  EXCEPTION WHEN OTHERS THEN
    -- Engine down: record a DURABLE retry obligation (rev-3 finding 5) —
    -- the effective row is gone, so nothing else remembers this edge.
    INSERT INTO public.meritrank_edge_tombstone (subject, object, last_error)
    VALUES (OLD.subject, OLD.object, left(SQLERRM, 500))
    ON CONFLICT (subject, object)
      DO UPDATE SET last_error = EXCLUDED.last_error;
    RAISE WARNING 'trust_edge_on_effective_delete %->%: % (tombstoned)',
      OLD.subject, OLD.object, SQLERRM;
  END;
  RETURN NULL;
END; $$;

CREATE OR REPLACE TRIGGER trust_edge_effective_delete_mr
  AFTER DELETE ON public.user_trust_edge
  FOR EACH ROW
  WHEN (OLD.prev_sent_weight <> 0)
  EXECUTE FUNCTION public.trust_edge_on_effective_delete();
```

Tombstone drain (part of the maintenance sweep, §10.3): for each tombstone in `(subject, object)` order — if a live effective row with `prev_sent_weight <> 0` exists for the pair (the pair was legitimately re-created after the deletion), just delete the tombstone; otherwise `mr_delete_edge` and delete the tombstone on success, keep it (update `last_error`) on failure.

### 5.9 Mirror update

Update `sql/triggers.sql`: replace/add all function texts from §5.5–§5.8 and the new tables (reference-only file).

### 5.10 Phase-1 verification

- Fresh DB: start local stack, run server once; then in psql:
  - `\d user_trust_source_edge` shows the 3-column PK; `\d user_trust_edge` is **unchanged** (2-column PK, no new columns); `trust_policy` seeded (182 d, 0.1); `trust_context_config` seeded with 4 rows.
  - `SELECT trust_apply_source_evidence('personal','U1','U2','good',3);` then `SELECT trust_rebuild_effective_edge('U1','U2');` returns `(1.0 × 1 × 3) / (5 + 1.0 × 3) = 0.375`. The source row is in `user_trust_source_edge`; the effective row is in `user_trust_edge`.
  - `SELECT trust_apply_source_evidence('effective', …)` raises (unknown context); `('personal','U1','U2','good','NaN')` raises; `SELECT trust_apply_evidence('U1','U3','good',3,0,0)` fails (function dropped).
- Upgrade path: covered by the dedicated transform test (§12 `trust_migration_test.dart`) replaying the m0122 data-transform statements verbatim against synthetic pre-migration rows; plus a staging dry-run against a fresh production dump (release-checklist item).

### 5.11 Rollback

**Backup restore only (rev-4 finding O8).** DB backup immediately before deploying the Phase-1–3 release; rollback = restore + redeploy the previous binary. Evidence accrued in between is lost; acceptable for an emergency window. Past that window, roll forward with a repair migration. There is deliberately **no reverse-SQL downgrade script** — a narrow, admittedly lossy downgrade path costs more to maintain and test than it protects. Migrant applies m0122 atomically (§1.6), so a **failed** migration leaves the old schema intact and the previous binary can be redeployed without a database downgrade.

---

## 6. Phase 2 — Drift & Dart data layer

### 6.1 Drift tables (`packages/server/lib/data/database/table/`)

- `user_trust_edges.dart`: **unchanged** (decision 1).
- New `user_trust_source_edges.dart` (PK `{trustContext, subject, object}`), `trust_evidence_events.dart`, `forward_decision_attributions.dart`, `meritrank_edge_tombstones.dart` mirroring §5 (follow existing table-file style; register in `tentura_db.dart` `@DriftDatabase(tables: […])`). `trust_policy`/`trust_context_config` get **no** Drift mirror — only SQL functions read them (decision 3).
- Run build_runner; fix fallout in `tentura_db.g.dart` consumers.

### 6.2 Domain vocabulary (`packages/server/lib/domain/trust/`)

- `trust_context.dart`: `enum TrustContext { personal, commitment, forward }` with `key` strings. There is no `effective` member (effectiveness is the `user_trust_edge` table) and no `legacy` member (legacy is migration-only), so both invalid evidence writes are unrepresentable in Dart.
- `trust_source_type.dart`:

```dart
enum TrustSourceType {
  userVote('user_vote'),
  finalizedRequestEvaluation('finalized_request_evaluation'),
  /// Propagated outcome of a non-negatively evaluated commitment;
  /// the TrustBin carries the outcome (no_effect / good / very_good).
  propagatedAuthorEvaluatedCommitment('propagated_author_evaluated_commitment'),
  /// Sign-off S1: propagated outcome of a NEGATIVELY evaluated commitment —
  /// always bin no_effect (neutral route learning, never punishment).
  negativeCommitmentRouteNoEffect('negative_commitment_route_no_effect'),
  /// Route failure: eligible forwarding pair with NO finalized evaluated
  /// commitment on any of its paths. Reserved exclusively for that case.
  unsuccessfulRequestForward('unsuccessful_request_forward');
  const TrustSourceType(this.key);
  final String key;
}
```

- `trust_evidence.dart` — extend (Freezed, matching the repo's entity convention):

```dart
@freezed
sealed class TrustEvidence with _$TrustEvidence {
  const factory TrustEvidence({
    required String targetUserId,
    required TrustBin bin,
    required double count,
    required TrustContext context,
    required TrustSourceType sourceType,
    String? requestId,                  // beacon id => ledger idempotency key
    String? sourceId,                   // e.g. forward batch id, evaluation key
    @Default(TrustEvidenceMetadata()) TrustEvidenceMetadata metadata,
  }) = _TrustEvidence;
}
```

- `trust_evidence_metadata.dart` — **typed, minimal audit metadata (decision 20; rev-4 finding O6)**: a Freezed class with exactly `algorithmVersion` (int), `supportingCommitmentIds` (ids, propagated cells only) and `attributionMethod` (enum key, attribution-derived shares only), serialized to the `metadata` jsonb by the writer. No intermediate algorithmic state (raw masses, shares, denominators — those live in the diagnostics log line, §9.2). No free-form `Map<String, Object?>` — the type is the anonymity invariant (no field can hold a name or user text).
- `trust_bin.dart`: add `const double kTrustForwardNoEffectCount = 1.0;` (env-overridable default).

### 6.3 Transaction seam (decision 14 — reuse, don't duplicate)

No new port. The finalization use case runs its episode through the **existing** `MutatingUnitOfWorkPort.run({required action, actorUserId})` (`packages/server/lib/domain/port/mutating_unit_of_work_port.dart`, implemented by `packages/server/lib/data/repository/mutating_unit_of_work.dart` over `TenturaDb`). Nested calls join the outer transaction via Drift's ambient-transaction semantics — which is also why the evidence writer needs no runtime transaction probe: its statements automatically execute in whatever transaction the caller opened, and the atomicity tests (§12) verify the contract end-to-end.

### 6.4 Evidence writer (spec `TrustEvidenceWriter` — atomic, decision 11)

New port `packages/server/lib/domain/port/trust_evidence_repository_port.dart`:

```dart
abstract interface class TrustEvidenceRepositoryPort {
  /// Ledger-insert + source-apply + effective-rebuild for the whole batch.
  /// Contract: call inside an open unit of work (MutatingUnitOfWorkPort.run
  /// or an existing repository transaction) so the episode commits atomically.
  /// Atomic: any failure other than an expected idempotency conflict (ledger
  /// unique index) propagates and aborts the caller's transaction.
  /// Idempotency conflicts skip the item (ledger row AND source bump) — a
  /// legitimate replay of an already-committed episode.
  /// Each touched pair is rebuilt exactly once per batch.
  Future<void> record(TrustEvidenceBatch batch);
}
```

Implementation `packages/server/lib/data/repository/trust_evidence_repository.dart` (`@LazySingleton(as: …, env: [Environment.dev, Environment.prod], order: 1)`), constructor `(TenturaDb)` only — policy is read by SQL, so this adapter has no `Env` dependency. Algorithm for `record`:

1. No context validation needed in Dart: `TrustContext` contains only the three writable source contexts (§6.2); SQL independently rejects unknown and migration-only contexts.
2. For each item, **sorted by `(targetUserId, context)`** — consistent with the global `(subject, object)` pair-lock order:
   - `INSERT INTO trust_evidence_event … ON CONFLICT DO NOTHING RETURNING id` (occurred_at = `batch.at`; metadata = typed-metadata JSON). No row returned ⇒ idempotency duplicate ⇒ skip this item (do not apply source evidence).
   - Else `SELECT trust_apply_source_evidence($1..$5)`.
   - **No savepoint, no catch**: any other error propagates (decision 11). (The old `applyEvidenceInTransaction` savepoint-and-continue pattern is retired.)
3. For each distinct applied pair (same sort): `SELECT trust_rebuild_effective_edge($1, $2)`. Publish failures inside the function are deferred (decision 13) and never abort the batch.

Mock `packages/server/lib/data/repository/mock/trust_evidence_repository_mock.dart` (`env: [Environment.test], order: 1`).

### 6.5 Env knobs (`packages/server/lib/env.dart` + `.env.example`)

- `forwardNoEffectCount` ← `FORWARD_NO_EFFECT_COUNT`, double, default `1.0`.
- `forwardMinOpportunity` ← `FORWARD_MIN_OPPORTUNITY_HOURS`, Duration, default 24 h.
- `trustSweepInterval` ← `TRUST_SWEEP_INTERVAL_HOURS`, Duration, default 24 h.
- `trustSweepRetry` ← `TRUST_SWEEP_RETRY_MINUTES`, Duration, default 15 min (failure retry — decision in §10.3).
- `trustSweepBatchSize` ← `TRUST_SWEEP_BATCH_SIZE`, int, default 200.
- `trustSweepTimeBudget` ← `TRUST_SWEEP_TIME_BUDGET_MINUTES`, Duration, default 5 min.

`TRUST_EDGE_HALF_LIFE_DAYS` / `TRUST_EDGE_EPSILON` are **removed** from `env.dart` and `.env.example` (decision 3): the DB is the sole canonical policy source, so there is no second copy to validate against and no startup reconciliation check. Before approving m0122, explicitly compare any deployed override with the proposed 182-day/0.1 product policy and choose one canonical value for the migration. Do not create environment-specific variants of m0122.

### 6.6 Rewire `UserTrustEdgeRepository`

- Evidence paths (`_setVoteAmountCore`, `_applyReciprocalTrustEdges` in `UserRepository`, `cutoverBackfillIfNeeded`) construct typed `TrustEvidence` (`context: personal`, `sourceType: userVote`, `requestId: null`) and call `TrustEvidenceRepositoryPort.record` inside their existing transactions (Drift ambient-transaction semantics, §6.3). Vote atomicity: evidence failure aborts the vote transaction (decision 19) — this is current behavior, preserved deliberately.
- `forceRefreshStar` → the new one-argument SQL entry point (`trust_resync_source`); `forceRefreshAll` → `TrustMaintenanceCase.forceRefreshAll` (§10.3), which owns the bounded forced-republication workflow.
- `cutoverBackfillIfNeeded` emptiness check becomes `SELECT count(*) FROM user_trust_source_edge`.
- Run build_runner; fix mocks.

### 6.7 Phase-2 verification

`dart analyze`; `dart test -x pg`; targeted pg tests from Phase 8 (source isolation, writer atomicity + idempotency).

---

## 7. Phase 3 — Route existing producers to typed contexts

1. **Personal** (done in §6.6): user votes, mutual invite accept, startup vote backfill → `personal`/`user_vote`. Verify no other producer: `grep -rn "applyEvidence\|trust_apply" packages/server/lib` shows only the writer and the named paths.
2. **Commitment:** evaluation-close evidence items carry `context: commitment`, `sourceType: finalizedRequestEvaluation`, `requestId: beaconId`, `sourceId: '$beaconId:$evaluatorId:$evaluatedUserId'`. Magnitudes stay `kTrustReviewEvidenceCount = 1` / `kTrustVoteEvidenceCount = 3`. (The orchestration move itself is Phase 5; in Phase 3 the existing repository method may temporarily construct the typed items in place.)
3. Nothing writes `forward` until Phase 5. Nothing writes `legacy` after m0122's one-time copy; there is no runtime legacy writer or compatibility shim.

---

## 8. Phase 4 — Forward attribution recording & first-forward UX

### 8.1 Repository (spec `ForwardAttributionRecorder`)

- Domain enum `packages/server/lib/domain/entity/forward_attribution_method.dart`: `enum ForwardAttributionMethod { explicitSingle('explicit_single'), explicitMultiple('explicit_multiple'), openedVia('opened_via') }` — **typed, not a string** (rev-3 finding 9).
- New port `packages/server/lib/domain/port/forward_attribution_repository_port.dart`:

```dart
abstract interface class ForwardAttributionRepositoryPort {
  /// Weights must sum to 1 (± 1e-9). Must be called inside the forwarding
  /// transaction (same ambient-transaction contract as the evidence writer).
  Future<void> record({
    required String batchId,
    required Map<String, double> weightByParentEdgeId,
    required ForwardAttributionMethod method,
  });
  Future<List<ForwardAttributionEntity>> fetchByBatchIds(List<String> batchIds);
}
```

- Freezed entity `packages/server/lib/domain/entity/forward_attribution_entity.dart` (`childForwardBatchId`, `parentForwardEdgeId`, `weight`, `method`, `createdAt`).
- Implementation `packages/server/lib/data/repository/forward_attribution_repository.dart` (+ mock).

### 8.2 `ForwardCase.forward` extension — server-authoritative (decision 8)

New optional parameter `List<String>? attributionParentEdgeIds`. Input validation **before** the transaction: reject `> kMaxAttributionParents (16)` entries and duplicate ids (`ArgumentError`). Then **inside** the existing `runAction` transaction, after `createBatch` returns non-empty `insertedRecipientIds` (empty ⇒ no attribution at all):

1. **In-transaction authoritative inbound set:** `ForwardEdgeRepositoryPort.lockActiveInboundEdges(beaconId, recipientId: senderId)` — new port method, same predicate as `fetchActiveInboundEdges` plus `FOR SHARE` row locks. This closes the TOCTOU window between the pre-transaction fetch (`forward_case.dart:152`) and the write: a concurrently cancelled inbound edge can no longer be attributed.
2. **First-episode check, server-side:** `SELECT count(*) FROM beacon_forward_edge WHERE beacon_id = $1 AND sender_id = $2 AND batch_id <> $currentBatch` — **cancelled batches included**. If > 0, this is not the sender's first outgoing episode: silently drop attribution (structured log `attribution_dropped_not_first_episode`) — a stale client must not fail the forward, but its attribution is void.
3. **Explicit answer** (`attributionParentEdgeIds` non-empty): every id must be in the locked inbound set — otherwise `UnauthorizedException` (an id belonging to another user or beacon is hostile, not stale). Weights `1/n`; method `explicitSingle`/`explicitMultiple`.
4. **Else, opened-via** (client-supplied `parentEdgeId` argument was non-null): re-validate it against the *locked* inbound set (not the pre-transaction fetch); if valid, one row, weight 1, method `openedVia`; if no longer valid, store nothing.
5. **Else:** store nothing. Server-auto-resolved parents (`resolveForwardParentEdgeId` author-direct / most-recent heuristics) are provenance, never attribution — the "most recent" heuristic must not masquerade as an opened-via selection.

### 8.3 GraphQL API

- New input type `input_field_attribution_parent_edge_ids.dart` as `part of '_input_types.dart'` (the `InputField*` pattern is mandatory for list args — §1.6); wire into `mutation_forward.dart` and pass through to `ForwardCase.forward`.
- New query `beaconEligibleInboundForwards(beaconId)` → `[{edgeId, senderId, senderName, createdAt, isSuggestedSource}]`:
  - New `ForwardInboundQueryCase` (or method on `ForwardCase`): **first guard `BeaconAccessGuard.canReadInvolvement`** (same guard as `BeaconForwardGraphCase` — `beacon_forward_graph_case.dart:45`; rev-3 finding 4: "active" does not imply authorized), then `fetchActiveInboundEdges(beaconId, recipientId: viewer)`, hydrate sender display names, set `isSuggestedSource` on the edge `resolveForwardParentEdgeId` would pick.
  - New file `packages/server/lib/api/controllers/graphql/query/query_forward_inbound.dart`, registered in `_queries_all.dart`.

### 8.4 Client (`packages/client/lib/features/forward/`)

Implementation must go through the `material-3-flutter` skill; scope:

1. New `gql/forward_inbound_sources.graphql` + regenerate Ferry code.
2. In the forward-submission flow, before the user's **first** outgoing forward of this beacon (no prior outgoing edges), if eligible inbound sources `> 1`, show a compact, skippable dialog:
   - Title: «Чей форвард побудил вас переслать этот запрос?» / "Which forward prompted you to pass this request on?"
   - One radio row per sender (preselect `isSuggestedSource`), «Несколько из них» (multi-select), «Не знаю».
   - Skippable; must never block the forward. (Client-side "first forward only" is UX sugar — the server independently enforces first-episode semantics, §8.2 step 2.)
3. Map selection → `attributionParentEdgeIds` (`Not sure`/skip ⇒ omit). Add the argument to `forward_beacon.graphql`.

### 8.5 Verification

Server pg tests: explicit/opened-via/none recording; first-episode drop (prior batch exists — active or cancelled); hostile edge id ⇒ `UnauthorizedException`; duplicate/oversize list rejection; concurrent cancel of the inbound edge vs forward (the `FOR SHARE` re-validation path); zero-inserted-recipients ⇒ no attribution; involvement-guard rejection on the query. Client: bloc test for the prompt trigger; `flutter analyze`.

---

## 9. Phase 5 — Review finalization use case & forward outcome pipeline

### 9.1 Pure domain model (`packages/server/lib/domain/trust/forward/`) — no imports from `data/`

`forward_provenance.dart` — Freezed `ForwardProvenanceEdge {id, senderId, recipientId, createdAt, parentEdgeId?, batchId?, cancelledAt?}` and `ForwardAttributionInput {batchId, parentEdgeId, weight}`.

`forward_causal_graph_builder.dart` (spec `ForwardCausalGraphBuilder`): unchanged semantics from rev 3 —

```dart
final class ForwardCausalGraphBuilder {
  /// Eligibility: e.createdAt < commitmentAt; not cancelled before it;
  /// rooted: parentEdgeId == null ? senderId == authorId
  ///       : parent eligible && parent.createdAt < e.createdAt
  ///         && parent.recipientId == e.senderId.
  /// Cycle defense: revisit or depth > edge count => ForwardGraphIntegrityException.
  /// Returns null when no eligible edge reaches the committer.
  /// Also reports rejected parentless non-author edges via [BuildStats].
  EligibleForwardDag? build({...});
}
```

`forward_mass_propagator.dart` / `forward_local_normalizer.dart`: unchanged from rev 3 (terminal mass 1.0 split equally across distinct terminal senders; distribution priority attribution → per-distinct-sender fallback; local shares per sender sum to 1).

`forward_request_consolidator.dart` — extended per S1 (decision 5):

```dart
enum ForwardOutcomeProvenance { evaluated, negativeRoute }
typedef PairBinKey = (String sender, String recipient, TrustBin bin,
    ForwardOutcomeProvenance provenance);

final class ForwardRequestConsolidator {
  /// Per-cell support: R = Σ_k observation_weight × q_k. negativeRoute cells
  /// always carry bin no_effect. Never collapsed, maxed, or averaged.
  Map<PairBinKey, double> accumulate(
    List<(TrustBin bin, ForwardOutcomeProvenance provenance,
        Map<(String, String), double> sharesByPair)> perCommitmentShares,
  );

  /// delta = budget × R / Z(u); Z(u) = Σ over ALL of u's cells (both
  /// provenances). Senders with Z == 0 are absent.
  Map<PairBinKey, double> normalizePerSender(Map<PairBinKey, double> support,
      {double budget = kForwardEvaluatedOutcomeBudget});
}
```

`forward_outcome_policy.dart`: `kForwardObservationWeight = 1.0`, `kForwardEvaluatedOutcomeBudget = 1.0`, and the **normative mapping of §3**:

```dart
/// (§3, sign-off S1). Returns null for noBasis (not an observation).
({TrustBin forwardBin, ForwardOutcomeProvenance provenance})?
    mapAuthorEvaluationToForwardOutcome(int value);
```

(`zero/pos1/pos2` → own bin, `evaluated`; `neg1/neg2` → `noEffect`, `negativeRoute`; `noBasis` → null. Direct commitment bins keep using the existing `reviewValueToBin` untouched.)

`forward_outcome_finalizer.dart` — pure, returns typed diagnostics (decision 14):

```dart
@freezed
sealed class ForwardFinalizationDiagnostics with _$ForwardFinalizationDiagnostics {
  const factory ForwardFinalizationDiagnostics({
    required int eligibleEdgeCount,
    required int rootlessEdgeCount,          // S2 watch-metric
    required List<String> integrityFailedCommitters, // cycle/DAG failures
    required Map<String, double> budgetBySender,     // Z(u) per sender
    required int observedPairCount,
    required int unsuccessfulPairCount,
  }) = _ForwardFinalizationDiagnostics;
}

final class ForwardOutcomeResult {
  final List<EvaluatedOutcomeEvidence> propagatedOutcomes; // both provenances
  final List<(String sender, String recipient)> unsuccessfulPairs;
  final ForwardFinalizationDiagnostics diagnostics;
}
```

Algorithm:

1. Inputs: `authorEvaluationByCommitter` = **all** finalized author evaluations of role-1 committers with `value ∈ {neg2, neg1, zero, pos1, pos2}` (`noBasis` excluded — §3 gate). Empty ⇒ empty result.
2. Per committer `k`: `outcome = mapAuthorEvaluationToForwardOutcome(value)`; `dag = builder.build(...)`; skip committer if null; a `ForwardGraphIntegrityException` adds the committer to `integrityFailedCommitters` and skips (no logging inside the pure class); `raw = propagator.propagate(...)`; `shares = normalizer.normalize(raw)`; collect `(outcome.forwardBin, outcome.provenance, shares)`; add every pair with a share to `observedOutcomePairs` — **negative-route pairs included** (§3).
3. `support = consolidator.accumulate(...)`; `deltas = consolidator.normalizePerSender(support)`.
4. Propagated events: one per non-zero cell — `sourceType` from provenance (`evaluated` → `propagatedAuthorEvaluatedCommitment`, `negativeRoute` → `negativeCommitmentRouteNoEffect`), preserved/`noEffect` bin, `count = delta`, typed metadata (§6.2).
5. `unsuccessfulPairs`: author-rooted eligible pairs computed against `commitmentAt = finalizedAt`, minus `observedOutcomePairs`, minus pairs whose every edge has `finalizedAt − createdAt < minOpportunity` or was cancelled before `finalizedAt`. Full `unsuccessful_forward_no_effect_count` each, never divided, outside the budget.

Properties (tested): per sender with `Z > 0`, Σ counts over all cells = 1.0 ± 1e-9; every `evaluated` cell's bin equals some supporting commitment's evaluation bin; every `negativeRoute` cell's bin is `noEffect`; a pair never appears in both `unsuccessfulPairs` and any propagated cell.

### 9.2 `ReviewFinalizationCase` (decision 14 — orchestration out of the repository)

New `packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart` (`@singleton`), constructed with `MutatingUnitOfWorkPort` (existing — decision 14), `EvaluationRepositoryPort`, `BeaconRepositoryPort`, `ForwardEdgeRepositoryPort`, `ForwardAttributionRepositoryPort`, `HelpOfferRepositoryPort`, `TrustEvidenceRepositoryPort`, `Env`, `logger`.

`closeAndFinalize(beaconId, {required reason, actorUserId})` runs **one** `MutatingUnitOfWorkPort.run`:

1. `snapshot = _evaluationRepository.closeReviewWindow(beaconId, reason: …, actorUserId: …)` — repository method that performs the *storage* part only: window guard (status ≠ 0 ⇒ returns null ⇒ use case no-ops), window→1, beacon→closed(6), lifecycle event, review statuses, `submitted→final` transition; returns a typed `ReviewCloseSnapshot {beaconAuthorId, windowOpenedAt, finalizedEvaluations: List<FinalizedEvaluation {evaluatorId, evaluatedUserId, value}>}`. Draft cleanup stays inside it.
2. Build commitment evidence batches (per evaluator, `context: commitment`, mapping via `reviewValueToBin`) → `_trustEvidence.record(...)` per sorted evaluator.
3. Forward finalization gate: role-1 participant ids ∩ author evaluations with mappable values (§3). If empty → done. Defense-in-depth episode check (decision 12): `EXISTS` forward-context events for this request ⇒ log + done.
4. Load typed snapshots through ports: all forward edges of the beacon (including cancelled), attributions by distinct batch ids, `commitmentAt` per committer (`beacon_help_offer.created_at`, fallback `windowOpenedAt`).
5. `result = ForwardOutcomeFinalizer().compute(...)` — pure. Log `result.diagnostics` as one structured line.
6. Build per-sender `TrustEvidenceBatch`es (propagated cells + route-failure items with `count: env.forwardNoEffectCount`) → `_trustEvidence.record(...)` per sorted sender. All forward evidence is written `sender → recipient`, never reversed.

Any exception aborts the whole transaction (decision 11); callers retry. `EvaluationRepository.closeBeaconReviewWindow` is **deleted**; `EvaluationCase.closeNow`, `closeExpiredWindows`-driven paths and the expiry sweep call `ReviewFinalizationCase` instead. DI: update injections, mocks, build_runner.

### 9.3 No re-opening of closed requests (decision 12 / sign-off S3)

In `EvaluationCase` (the re-scaffold flow at ~`evaluation_case.dart:215–237`): before `deleteReviewScaffoldingForBeacon`, load the review window; if a window exists with `status = 1` (closed), throw a domain exception (`ReviewAlreadyClosedException` — new, in `domain/exception/`) instead of re-scaffolding. GraphQL surfaces it as a clear error. Repository-level backstop: `deleteReviewScaffoldingForBeacon` itself throws `StateError` when the window row has `status = 1`.

### 9.4 Per-beacon expiry transactions

`AttentionExpirySweepCase.runDue` currently wraps all due beacons in one `runAction` (`attention_expiry_sweep_case.dart:26`). With atomic finalization, one failing beacon must not wedge the batch: restructure to fetch due ids with `FOR UPDATE SKIP LOCKED` (repository method), then loop — **one `runAction` per beacon**, catching and logging per-beacon failures so the rest proceed; a failed beacon retries next sweep. `closeExpiredWindows` follows the same per-beacon shape.

### 9.5 Closed-request banner (client — sign-off S3)

Through the `material-3-flutter` skill, in `beacon_view` (screen) and `beacon_room`: when the beacon status is closed (6), show a persistent, **non-closable** `MaterialBanner`-style surface (design-system component): RU «Запрос закрыт. Новые отклики, уведомления и доверие по нему больше не создаются.» / EN "This request is closed. It no longer produces responses, notifications, or trust evidence." Include the existing duplicate-request affordance as the banner action where the viewer is the author. The room stays usable for chat; no new evidence or notifications originate from the beacon (server side already guarantees this via decision 12).

### 9.6 Verification

Pure tests (§12) via `dart test -x pg`; end-to-end pg test: seed users → forwards (chain + diamond) → help offers → author evaluations (mixed valences) → `ReviewFinalizationCase.closeAndFinalize` → assert ledger rows per §3 mapping, effective rebuild, idempotent re-close, re-open rejection.

---

## 10. Phase 6 — MeritRank boundary, maintenance, policy-migration contract

### 10.1 Boundary

Enforced by Phase 1: source-table writes never call MeritRank; only `trust_rebuild_effective_edge` calls `mr_put_edge`; `meritrank_init` continues to bulk-load only the effective projection in `user_trust_edge`; deletions are tombstoned. Boundary tests in §12.

### 10.2 Policy-change contract (decision 17 — quiesced migration, not a mutation)

There is **no** `trustReconfigure` mutation and no runtime policy mutation of any kind. A later policy change is valid only as a separately reviewed migration in a quiesced deployment; it must leave no interval in which a new policy serves with an old effective projection:

1. Stop the old application before the migration, using the same `deploy.sh` down/up boundary as m0122. The migration must not be applied by a still-serving mixed fleet.
2. Capture one `_calculation_time`. If half-life changes, deflate every source bin to that instant under the **old** half-life and set `anchor_at = _calculation_time`; then update `trust_policy`. Multiplier/epsilon changes update `trust_policy` / `trust_context_config` normally.
3. In the **same database transaction**, rebuild `user_trust_edge` set-wise from all source pairs at `_calculation_time`, including zeroing effective pairs that no longer have contributing sources. This SQL belongs to that migration, not to a reusable runtime full-table function. It is safe without pair locks only because no application writer is running. Set `prev_sent_weight` to the rebuilt weight because the engine will be authoritatively reloaded next.
4. Make `mr_reset()` the migration's final external action. Do not call `meritrank_init()` inside the migration. After the migration commits, the existing `App._uploadGraph` sees an empty engine and initializes it from the committed `user_trust_edge` projection **before** spawning task or web workers.
5. Recovery is deterministic despite `mr_reset()` being external: if reset succeeds but the migration transaction later rolls back, the next startup initializes the empty engine from the still-old committed projection; if the transaction commits, startup initializes the new projection. A reset failure aborts the migration and leaves the committed DB policy/projection unchanged.

Migrations are already the audited change channel, and the existing cold-start initializer is the recovery path. No lease, policy epochs, startup reconciliation, admin input surface, or post-start manual step is introduced. If the graph eventually becomes too large for this explicitly offline migration, that measured constraint is the trigger for a separate online-reconfiguration design.

### 10.3 Maintenance driver (existing worker — rev-4 finding O5)

New `TrustMaintenanceCase` registered in `TaskWorkerCase._tasks`, following the same in-memory scheduling pattern as the other periodic tasks (the app runs exactly one task-worker isolate — `app.dart:35`; no `task_lease` table):

1. **Due check for `runDue(now)`:** initialize as due on first run. When the most recent attempt failed after the most recent success, only `now - _lastFailedAt >= env.trustSweepRetry` makes it due; otherwise use `now - _lastSuccessAt >= env.trustSweepInterval`. This precedence prevents an already-expired success interval from causing a tight retry loop. Record success or failure only **after** the attempt completes (avoids the stamp-before-await gap of `task_worker_case.dart:88`).
2. **Tombstone drain** (§5.8 semantics), ordered, each in a short transaction.
3. **Batched sweep:** loop `trust_rebuild_effective_batch(cursor…, env.trustSweepBatchSize)` — one transaction per call — until done **or** `env.trustSweepTimeBudget` is exhausted (bounded execution; the epsilon gate makes a resumed-from-scratch next run publish only genuine drift). The sequential worker loop is never blocked longer than one batch + budget check.
4. **Explicit repair:** `forceRefreshAll()` first drains tombstones, then runs the same bounded cursor loop without the periodic time budget and passes `_epsilon_override = -1`, forcing every effective pair through `mr_put_edge`. It does **not** reset the engine. A publication failure leaves that pair's `prev_sent_weight` behind, so ordinary maintenance retries it; a mid-run process failure leaves every completed pair honestly published and the next call safely starts again. Effective-only pairs are rebuilt to zero and deletions converge through tombstones, making this a safe differential equivalent of reset/init without its recovery window. The existing `UserPrivileges.mrInit` guard stays in `UserTrustEdgeCase`. This is a no-policy-change repair operation, not a hidden reconfiguration path.

### 10.4 Verification

pg tests: tombstone convergence with the engine down/up, sweep-vs-writer concurrency and full-repair ordering (§12); unit tests for first-run, normal interval and failure-retry precedence. The policy-migration contract (§10.2) gets a migration-harness test proving re-anchoring preserves weight at the switch instant, every effective pair is rebuilt before reset, and cold-start initialization converges after both the commit and reset-then-rollback paths.

---

## 11. Phase 7 — Telemetry & documentation

1. **Telemetry (v1 = structured logs + ledger queries; no new infra):**
   - The finalization use case logs one structured line per request from `ForwardFinalizationDiagnostics` (+ per-source-type event counts, attribution method mix, per-sender Z).
   - `docs/design/trust-telemetry-queries.md`: ready SQL for events by context/source_type (now including `negative_commitment_route_no_effect`), legacy contribution over time, reuse rate of reinforced pairs, rootless-edge trend (S2 watch-metric), tombstone backlog, pairs whose effective `updated_at` predates their newest source `updated_at` (stale-projection detector). No public rankings anywhere.
2. **Design document** `docs/design/trust-forward-propagation.md`: every bullet of spec §Documentation requirements, plus rev-6 specifics — the §3 outcome mapping table verbatim (S1); quantity/value separation (bin = value, count = quantity; equal observation weight for good/very_good, utility mapping carries the difference; double-weighting prohibition); mixed evidence incl. evaluated + negativeRoute `no_effect` on one pair; `negative_commitment_route_no_effect` vs `unsuccessful_request_forward` semantics; worked examples (patch's four + one negative-route example: a request with one `bad` commitment emits `very_bad` direct evidence to the committer and `no_effect` route evidence along the path, and its unobserved eligible pairs get `unsuccessful_request_forward`); the policy-change contract (§10.2: quiesced migration, optional re-anchor and complete projection rebuild in one DB transaction, reset last, cold-start init before workers); closed requests are final (S3); audit-metadata anonymity invariant (S4); vote replay protection delegated to the vote state machine under atomic transactions; terminal-seed spec-gap decision; `commitmentAt` first-offer conservatism; empirical-hypothesis constants list.

---

## 12. Phase 8 — Test plan

**Pure domain (`dart test -x pg`), `packages/server/test/domain/trust/`:**

- `forward_causal_graph_builder_test.dart` — direct author→committer; single intermediate; multi-hop; diamonds; split/merge; shared stem; rootless parentless non-author edge rejected **and counted in BuildStats**; late edge ignored; cancelled-before-commitment ignored; parent.recipient ≠ child.sender rejected; temporal-order violation rejected; synthetic cycle → `ForwardGraphIntegrityException`.
- `forward_mass_propagator_test.dart` — terminal seeding sums to 1; per-sender fallback equality; explicit attribution overrides fallback; ineligible attributed parent → renormalize/fallback; masses ∈ [0,1].
- `forward_local_normalizer_test.dart` — unchanged rev-3 list.
- `forward_request_consolidator_test.dart` — per-cell accumulation (bins never collapsed/maxed/averaged); **provenance separation: a pair holding evaluated `no_effect` and negativeRoute `no_effect` keeps two cells**; patch examples (½/½ good+very_good; ⅓ mixed bins); Σ over all cells = budget per sender; `Z = 0` ⇒ absent; deterministic; no hidden bin multiplier.
- `forward_outcome_finalizer_test.dart` — **§3 mapping table exhaustively**: each evaluation value ⇒ expected (source_type, bin) or nothing; negative-only request emits negativeRoute events on observed paths and `unsuccessful` on unobserved eligible pairs (**the rev-3 asymmetry is gone**: same negative path classifies identically with and without a coexisting positive commitment); `noBasis`-only ⇒ empty result; observed (incl. negative-route) pair never in `unsuccessfulPairs`; opportunity-interval exclusion; multiple-commitments and topology-invariance examples under vector semantics; diagnostics populated (rootless count, integrity failures, Z map); property loop over randomized DAGs and random evaluation values: per-sender Σ = 1.0, no invented bins, disjoint observed/unsuccessful sets.

**Postgres integration (`@Tags(['pg'])`), `packages/server/test/data/repository/`:**

- `trust_source_context_test.dart` — source isolation; unknown-context and `legacy` apply raise; NaN/negative/oversized count raises; effective bins = Σ multiplier × deflated source bins (1e-9); zero-multiplier contexts excluded; repeated rebuild deterministic; VSIDS inflate/project round-trip; no double-decay; source writes leave `user_trust_edge` untouched until rebuild.
- `trust_evidence_writer_test.dart` — ledger row per applied item; idempotency-index duplicate skips item entirely; per-bin identity (4a) incl. **both propagated source types coexisting on one (request, pair)**; 4b one route-failure per pair; **atomicity: a batch with one failing item (e.g. malformed count injected) rolls back every item's ledger row and source bump**; **concurrency: parallel personal-vote and forward-evidence transactions on the same pair serialize on the pair lock, both land** (rev-3 blocker 2 test); metadata schema contains only `algorithm_version`, provenance-id arrays and the constrained attribution enum, with no free-form strings or intermediate math (decision 20).
- `trust_meritrank_boundary_test.dart` — `meritrank_init` bulk-loads `user_trust_edge` and never `user_trust_source_edge`; source writes are invisible to `mr_edgelist()` until effective rebuild; resync publishes effective rows only; **deferred publication** (shadowed `mr_put_edge` ⇒ evidence + ledger still commit, `prev_sent_weight` unchanged, later rebuild republishes); **deletion during outage: delete user with engine down ⇒ tombstone row; restore engine; maintenance drain ⇒ `mr_edgelist()` clean, tombstone gone** (rev-3 finding 5); re-created-pair tombstone discarded without deleting the live edge; Sybil/topology: `mr_node_score` of D for an external ego does not increase when `B→D` becomes `B→V→D`.
- `trust_maintenance_test.dart` (new) — first run is due; after success, `trustSweepInterval` controls; after a later failure, `trustSweepRetry` takes precedence without a tight loop; **sweep-vs-writer:** run a batched sweep concurrently with per-pair evidence writes and assert final effective rows equal serial recomputation (no stale overwrite); time-budget stops mid-run cleanly; explicit full repair forces every pair, drains tombstones, and resumes safely after a mid-run failure without reset/init. Migration harness: half-life re-anchor preserves the switch-time weight, set-based rebuild covers source-only and effective-only pairs, reset is last, and cold-start init restores the committed projection after both commit and reset-then-rollback (§10.2).
- `trust_migration_test.dart` — replay m0122 data-transform statements verbatim on synthetic legacy rows: legacy source copies exact, `user_trust_edge` rows byte-identical (untouched), rebuild after cutover reproduces the pre-migration weight to 0 tolerance; empty-table migration OK.
- `forward_outcome_finalization_test.dart` — end-to-end via `ReviewFinalizationCase` (mixed valences per §3, assert per-source-type ledger events + typed metadata); re-close idempotent (no new rows); **re-open rejected** (`ReviewAlreadyClosedException` from the re-scaffold path; repository backstop throws too); atomic abort: failing evidence item ⇒ window still open, zero ledger rows, retry succeeds; per-beacon expiry isolation: one poisoned beacon doesn't block the batch.
- `forward_attribution_repository_test.dart` — §8.5 list.

**Updates to existing tests:** `user_trust_edge_degree_test.dart` (unchanged schema — verify it still passes as-is), `user_trust_edge_case_test.dart` + mocks, evaluation close tests (use case, not repository), `merit_score_lookup_test.dart` and `realtime_notification_migration_test.dart` (~line 1534) migrate any `trust_apply_evidence(6-arg)` calls to the new functions (the old signature is dropped in m0122).

**Client:** attribution-prompt bloc test; closed-banner widget test (non-dismissible, shown for status 6 only); `flutter analyze`; `cd packages/tentura_lints && dart test`.

---

## 13. Acceptance-criteria mapping

Spec §Acceptance criteria: unchanged rows from rev 3 for 1–13, 15, 19–20, 26–29 (section numbers shifted: schema §5, writer §6, producers §7, attribution §8, pipeline §9, boundary/ops §10, docs §11, tests §12). Amended rows:

| # | Criterion | Current disposition |
| --- | --- | --- |
| 14/16/17 | consolidation/budget | as amended by patch 1 (vector consolidation) **and S1** (negativeRoute cells share the budget) — §9.1 |
| 21–23 | `no_effect` post-finalization; outcome gate; never both propagated & unsuccessful per pair | gate = ≥1 bin-mappable author evaluation (§3, S1 — "non-negative" dropped); exclusivity by construction (disjoint sets) + indexes + atomic episodes |
| 24–25 | per-(request, pair, bin) consolidation; auditable idempotent events | §5.4 (bin + source-type in identity), §6.4 (atomic writer) |

Correction-patch criteria (patch §13): P1–P5, P8, P9 as in rev 3 (sections renumbered). **P6 amended by S1:** neutral evaluated paths ≠ unobserved failed routes *and* negative-route paths ≠ unobserved failed routes. **P7 superseded by S1:** negative evaluations stay direct-only in their *valence* (the negative bins never propagate) but now contribute neutral route evidence via `negative_commitment_route_no_effect`.

Rev-3 review findings → resolutions (carried into rev 6): finding 1 → decisions 11/19 (§6.4, §9.2); finding 2 → decision 16 (§5.5, §5.6, runtime batch driver §10.3, tests §12); finding 3 → decision 14 (§9.2, §6.3); finding 4 → decision 8 (§8.2–8.3); finding 5 → decision 15 (§5.8, §10.3); finding 7 → decision 3 + constrained extension points (§5.2); finding 9 → this document (single normative text, typed metadata/diagnostics/methods, `InputField*`); S1 → §3 + decision 5; S2 → decision 10; S3 → decision 12 (§9.3, §9.5); S4 → decision 20.

Rev-4 overengineering findings → completed rev-6 resolutions: O1 (in-place widening) → decisions 1/2/6, §5.1, §5.3; O2 (runtime policy control plane) → decisions 3/17, §10.2, §6.5; O3 (duplicate transaction port) → decision 14, §6.3; O4 (mixed-fleet protocol) → decision 18, §5.7 and the one-release rollout in §15; O5 (`task_lease`) → §5.4 note, §10.3; O6 (audit-metadata bloat) → decision 20, §6.2; O7 (`model_kind`) → decision 2, §5.2; O8 (reverse-SQL rollback) → §5.11 and §15.

---

## 14. Explicit non-goals

No reverse/negative-valence propagation (S1's negative-route evidence is neutral `no_effect`, deliberately not punishment), no spam-feedback feature (`recipient_forward_relevance_feedback` fully omitted from v1 — no enum value, no writer support), no per-edge retrospective attribution prompts, no percentage UX, no group trust, no MeritRank-internal contexts, no nonlinear composition, no non-Dirichlet models (and no `model_kind` column until a second model exists — O7), no exploration quotas, no re-opening of closed requests (S3), no runtime policy reconfiguration (O2), no distributed-job leasing (O5). Extension seams that remain are *structural only*: the consolidator's provenance dimension, the source-type enum — extending any of them is a schema change with a review, not a config edit.

---

## 15. Suggested implementation order & sizing

| Phase | Content | Rough size |
| --- | --- | --- |
| 1 | m0122 SQL | 1 migration + triggers.sql mirror |
| 2 | Source-table Drift mapping, domain vocabulary, writer, env cleanup | ~10 files |
| 3 | producer rewiring | 3 files |
| 4 | attribution + API + client prompt | ~11 files |
| 5 | pure pipeline + finalization use case + no-reopen + banner | ~14 files |
| 6 | maintenance driver + bounded full-repair wiring | ~3 files |
| 7 | docs/telemetry | 2 docs |
| 8 | tests | ~14 test files |

Phases 1–3 form **one quiesced release**: `deploy.sh` stops the old container, m0122 and every new Dart call site ship together, migration succeeds atomically, then the new workers start. There is no compatibility shim, m0123, mixed-version interval, or reverse-SQL rollback artifact. Phases 4–5 ship the forward-learning feature; Phases 6–8 add the bounded repair/sweep path, documentation and verification without introducing a runtime policy-control plane or distributed scheduler.
