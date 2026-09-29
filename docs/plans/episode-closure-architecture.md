# Episode closure and trust update — technical architecture

**Status:** draft, rev 6 (2026-09-29). Rev 2 applied the Codex (gpt-6-astra, high) architecture review; rev 3 applied the inherited findings of the Codex review of the step plan; rev 4 adds U58 (helper → author edge at episode completion, §5.9a); rev 5 reframes support as the helper's own judgement and documents its self-scaling (§5.5.2).; rev 6 adds U59 (support edge helper → supported colleague, §5.9b). See §15.

**Normative source:** `episode-closure-implementation-plan.md` (Russian, rev 23). That document holds the product decisions (U1–U57, P1–P11), their rationale and the rejected alternatives (§1.4). This document is the engineering translation: components, data model, algorithms, interfaces, jobs, migration, deployment and test strategy. Where the two disagree, the Russian plan wins and this file must be fixed.

**Related:** `post-request-closure-social-design.md` (social rationale) · `episode-closure-simulator.html` (reference implementation of the settlement math; §12.3) · `~/MY_SRC/meritrank-rust/NEGATIVE_EDGES_FEATURE.md` (MeritRank walls, service v0.11.0).

Path abbreviations: **S** = `packages/server/lib/`, **C** = `packages/client/lib/`, **M** = `packages/server/lib/data/database/migration/m0193.dart` (squashed schema baseline). **TT** = Tentura trust layer (Postgres + Dart server). **MR** = MeritRank service. **Epoch** = one closure attempt of a request.

---

## 1. Scope

### 1.1 Goals

1. Replace the 5-point person review with: author outcome per accepted offer, an author-weighted split of the author's attention, and an impartial peer adjustment through a single "support" toggle.
2. Replace valence bins with event-type trust bins backed by a retractable evidence ledger.
3. Keep the existing forward back-propagation engine as the routing-credit stream.
4. Phase 0: stop publishing negative trust weights to MR (MR v0.11.0 interprets them as walls).
5. Phase B: publish bans as walls (−1) and add a "noisy contact" wall from unanswered forwards.

### 1.2 Non-goals

- Read-side privacy hardening of existing graph reads (`graph()` `positive_only`, `graph_edges_between`, oracles) — deferred (U17). New closure surfaces must still satisfy U36/U57 (§7).
- Re-invite ranking correction, exploration slots in the main list, σ controller, sponsor alarm, mismatch-claim channel, inherited walls (MR #86) — phase C.
- Legacy client compatibility — web-only client, no users; one release, then raise `kDefaultMinClientVersion` (S/env.dart:79).

### 1.3 Delivery phases

| Phase | Content | Ships as |
|---|---|---|
| 0 | Clamp published weight to ≥ 0; pgmer2 0.8.1 + `mr_sync` barrier; score-scale audit | separate PR, immediately |
| A | Trust ledger + kinds + publication queue; closure data model, settlement, API, notifications, client screens; delete review subsystem; one-shot trust cutover task | one PR, one quiesced release (§11) |
| B | Ban → −1 wall; noisy-contact wall; "I pinged them" display factor; invariant suites | separate PR |

---

## 2. Current system (facts the design depends on)

**Trust pipeline**
- Write path: `TrustEvidenceRepository.record` (S/data/repository/trust_evidence_repository.dart:22) inserts `trust_evidence_event` (M:5833) → `trust_apply_source_evidence` (M:4138, anchor-inflated accumulator into `user_trust_source_edge`) → `trust_rebuild_effective_edge` (M:4256) → `mr_put_edge(subject, object, weight, '', 0)` when `|target − prev_sent_weight| > ε` (ε = 0.1). Publication errors are caught and deferred (M:4315).
- `trust_edge_weight` (M:4205) is **signed**. A block publishes 0 only if the pair row exists (M:4304). Deleting an effective edge fires `trust_edge_on_effective_delete` (M:4184, trigger M:7192) → `mr_delete_edge` or a tombstone in `meritrank_edge_tombstone`.
- `meritrank_init()` (M:2138) bulk-loads `prev_sent_weight` and polling edges; called from S/app/app.dart:83 when `mr_edgelist()` is empty. Startup also calls `cutoverBackfillIfNeeded()` (S/app/app.dart:31 → S/data/repository/user_trust_edge_repository.dart:95), which reads `user_trust_source_edge`; `trust_resync_source()` reads it too. pgmer2 is upgraded **after** schema migration (S/app/app.dart:27). Test templates run migrations **without** the pgmer2 extension (packages/server/test/support/disposable_pg_target.dart:90).
- `mr_sync` is never called. Postgres image `postgres-tentura:v0.8.0` = pgmer2 0.8.0. MR service pinned to `meritrank-service:v0.11.0` (walls implemented; λ = 0; MR returns walls from reads).
- `TrustMaintenanceCase` runs from `TaskWorkerCase` every 24 h (batch 200).

**Closure lifecycle**
- `BeaconStatus`: open(0), cancelled(1), deleted(2), draft(3), reviewOpen(5), closed(6), needsMoreHelp(7), enoughHelp(8); open family {0,7,8}.
- `EvaluationCase` (S/domain/use_case/evaluation_case.dart) owns close / close-now / extend / reopen and the review package; `ReviewFinalizationCase.closeAndFinalize` (S/domain/use_case/evaluation/review_finalization_case.dart:70) writes evidence and close-acks; `AttentionExpirySweepCase` finalizes due windows every minute (partial index on `closes_at`, M:6635).
- Reopen paths: `reopenFromReview` (:397, `kMaxReviewReopens = 1`) and `CoordinationCase.setBeaconStatus(reviewOpen → needsMoreHelp)` (coordination_case.dart:693).
- Participants: `beacon_help_offer` (M:5073), `beacon_commitment_event` (M:4952) with kinds offered, acknowledged, acknowledgementSoftened, withdrawnByHelper, releasedByAuthor, removedFromChat, readmittedToChat, blockedCleanup, unansweredAtClose; state helpers in S/domain/commitment/commitment_state.dart. Approval entry point: `CoordinationCase.acceptHelpOffer()` (coordination_case.dart:324); withdrawal: `HelpOfferCase` (help_offer_case.dart:296). `EvaluationParticipantGraphBuilder` excludes the author at line 108.
- Forward chain: `beacon_forward_edge` (M:5054), `forward_decision_attribution` (M:5544). `fetchHelpOffererPathChain({beaconId, helpOffererId, viewerId})` (S/data/repository/forward_edge_repository.dart:178) is a **display** query: it returns the union of helper and viewer ancestor paths and has no before-offer cutoff — not suitable for causal attribution.

**Forward engine** (S/domain/trust/forward/): `ForwardCausalGraphBuilder` → `ForwardMassPropagator` → `ForwardLocalNormalizer` → `ForwardRequestConsolidator` (per-sender budget 1.0 per request); evidence on **sender → recipient** of every hop.

**Notifications:** `AttentionIntentCase` → `AttentionDispatchRepository.record` (idempotent on `source_event_key`, immutable-payload check at S/data/repository/attention_dispatch_repository.dart:42) → `notification_outbox`. `access_policy` ∈ {beacon_content, beacon_tombstone, recipient_safe, profile}; `recipient_safe` allows only presentation keys room_member_removed, offer_declined, offer_removed (M:5698). `AttentionEventType.staleReminder` exists without a producer. Periodic work: `TaskWorkerCase._tasks`; pattern `DeadlineReminderSweepCase`.

**Hasura / client coupling:** `beacon_review_window` is tracked in Hasura with a beacon relationship (hasura/metadata.json:15, 1914) and read by the common client fragment C/data/gql/beacon_model.graphql:43.

**Client:** `C/features/evaluation` owns review UI and lifecycle mutations; archive affordance on My Work cards depends on `showArchiveAffordance` (C/features/my_work/ui/widget/my_work_cards.dart:356). Client version lives in `packages/client/pubspec.yaml`, `packages/client/web/index.html` (bootstrap cache-buster) and the server floor `kDefaultMinClientVersion` (S/env.dart:79, guarded by `packages/server/test/release_client_version_floor_test.dart`); `web/manifest.json` is generated at build.

---

## 3. Architecture overview

```
client (Flutter web)
  features/closure ── GraphQL V2 ──▶ API controllers (closure resolvers; no Hasura exposure of closure tables)
                                         │
                                         ▼
                                   ClosureCase ── one advisory lock per beacon for every closure mutation (§5.2)
                                   ├── EpisodeSettlement (pure)
                                   ├── ForwardRoutingSettlement (pure, adapted engine)
                                   ├── MembershipReducer (pure: commitment events → member state, §5.3)
                                   ├── ClosureRepository ─────────▶ beacon_closure*, support, marks, results
                                   ├── TrustEvidenceRepository ──▶ trust_evidence, trust_kind_config,
                                   │                                user_trust_edge (projection), trust_publish_queue
                                   ├── CapabilityEvidenceRepository (close-acks)
                                   └── AttentionIntentCase (receipts)
TaskWorkerCase ── TrustPublisher (queue → mr_put_edge → mr_sync → ack), ClosureFinalizeSweep,
                  ClosureDraftReminderSweep, StaleRequestReminderSweep, TrustMaintenance,
                  (phase B) ContactResolutionSweep
Startup ── TrustCutoverCase (one-shot, restartable, after migrations and pgmer2 upgrade, §11)
```

Layering follows `.cursor/rules/architecture.mdc`: domain (pure entities, settlement, reducer, ports) ← data (repositories, SQL) ← api/ui.

**Consistency model.** Every closure write and lifecycle transition commits in one Postgres transaction together with its evidence rows, close-acks, final results and receipts. External MR effects are **never** issued inside that transaction: the transaction only marks affected pairs dirty in `trust_publish_queue`; `TrustPublisher` publishes committed state afterwards (§4.3).

---

## 4. Trust evidence subsystem

### 4.1 Tables

```sql
CREATE TABLE trust_kind_config (
  kind            smallint PRIMARY KEY,
  slug            text NOT NULL UNIQUE,
  polarity        smallint NOT NULL CHECK (polarity IN (0, 1)),   -- 0 trust, 1 wall
  half_life_s     double precision NULL CHECK (half_life_s IS NULL OR half_life_s > 0),
  k_sat           double precision NOT NULL CHECK (k_sat > 0),
  mix_weight      double precision NOT NULL CHECK (mix_weight >= 0),
  wall_levels     jsonb NULL,         -- [{"min_n": 3, "level": 0.1}, {"min_n": 6, "level": 0.3}, {"min_n": 10, "level": 0.6}]
  linear_window_s double precision NULL CHECK (linear_window_s IS NULL OR linear_window_s > 0),  -- U58: linear decay to 0 over the window (instead of half-life)
  counts_for_immunity boolean NOT NULL DEFAULT true                                            -- U58: false = excluded from T_recent
);

CREATE TABLE trust_evidence (
  id              text PRIMARY KEY,                -- 'T' || 12 hex
  subject_user_id text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  object_user_id  text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  kind            smallint NOT NULL REFERENCES trust_kind_config(kind),
  count           double precision NOT NULL CHECK (count > 0 AND count <= 1e6),
  source_key      text NOT NULL UNIQUE,            -- idempotency + retraction address
  beacon_id       text NULL,
  closure_epoch   int  NULL,
  related_user_id text NULL,
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  retracted_at    timestamptz NULL,
  metadata        jsonb NOT NULL DEFAULT '{}',     -- ids and algorithm version only
  CHECK (subject_user_id <> object_user_id)
);
CREATE INDEX trust_evidence_pair_live   ON trust_evidence (subject_user_id, object_user_id) WHERE retracted_at IS NULL;
CREATE INDEX trust_evidence_object      ON trust_evidence (object_user_id);
CREATE INDEX trust_evidence_kind_dedup  ON trust_evidence (kind, subject_user_id, object_user_id, occurred_at) WHERE retracted_at IS NULL;
CREATE INDEX trust_evidence_episode     ON trust_evidence (beacon_id, closure_epoch);

CREATE TABLE trust_publish_queue (
  subject_user_id text NOT NULL,
  object_user_id  text NOT NULL,
  enqueued_at     timestamptz NOT NULL DEFAULT now(),
  attempts        int NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error      text NULL,
  PRIMARY KEY (subject_user_id, object_user_id)
);

CREATE TABLE trust_publisher_lease (           -- fencing for the single publisher
  id          smallint PRIMARY KEY CHECK (id = 1),
  owner       text NULL,
  token       bigint NOT NULL DEFAULT 0,
  lease_until timestamptz NOT NULL DEFAULT 'epoch'
);

ALTER TABLE user_trust_edge            -- columns subject, object, prev_sent_weight stay
  DROP COLUMN s_very_bad, DROP COLUMN s_bad, DROP COLUMN s_no_effect,
  DROP COLUMN s_good, DROP COLUMN s_very_good, DROP COLUMN anchor_at,
  ADD COLUMN trust_w    double precision NOT NULL DEFAULT 0,
  ADD COLUMN wall_d     double precision NOT NULL DEFAULT 0,
  ADD COLUMN target_w   double precision NOT NULL DEFAULT 0;   -- desired published value (projection)
-- prev_sent_weight stays: the value MR is known to hold (acknowledged after mr_sync).
```

Dropped in phase A: `trust_evidence_event`, `user_trust_source_edge`, `trust_context_config`, `trust_policy.half_life_seconds`, `trust_apply_source_evidence`, `trust_resync_source`, `trust_rebuild_effective_edge`, `trust_rebuild_effective_batch`, and the Dart `cutoverBackfillIfNeeded()` path. Existing column names of `user_trust_edge` (`subject`, `object`) are kept.

The effective-edge deletion trigger `trust_edge_effective_delete_mr` is kept, but its function `trust_edge_on_effective_delete` is rewritten: instead of calling MR inside the deleting transaction it inserts the pair into `trust_publish_queue` when `OLD.prev_sent_weight <> 0` (the publisher then finds no row, treats the target as 0 and calls `mr_delete_edge`). This covers user-FK cascades. `meritrank_edge_tombstone` and its drain path are dropped; the queue is the only publication path.

Seeded kinds (phase A: 1–5 and 8 in `m0202`, 9 in `m0204`; phase B: 6–7):

| kind | slug | polarity | written by | subject → object | hl | k | mix |
|---|---|---|---|---|---|---|---|
| 1 | `vouch` | trust | not written — read from `vote_user` (amount > 0 ⇒ s = 1) at rebuild | voter → target | — | 1 | 1.0 |
| 2 | `helped` | trust | finalize: final share | author → helper | 365 d | 1 | 1.0 |
| 3 | `marked` | trust | finalize and later toggles: bookmark | marker → target | 365 d | 0.5 | 0.2 |
| 4 | `routed` | trust | finalize: routing engine | sender → recipient of each hop | 182 d | 1 | 0.5 |
| 5 | `useful_forward` | trust | offer approval (stream 2) | helper → its arrival forwarder | 182 d | 2 | 0.5 |
| 8 | `worked_with_author` | trust | finalize: every member present until closure, `count = 1/√n` (U58, §5.9a); not in `T_recent` | helper → author | linear to 0 over 180 d | 1 | 0.08 |
| 9 | `supported_colleague` | trust | finalize: counted support of a voter, `count = 1/√|U_i|` per supported member (U59, §5.9b); not in `T_recent` | supporter → supported | linear to 0 over 180 d | 1 | 0.1 |
| 6 | `engaged` | trust | phase B: forward engagement | recipient → sender | 90 d | 2 | 0.2 |
| 7 | `noisy` | wall | phase B: forward ignored until deadline | recipient → sender | 14 d | — | — |

### 4.2 Projection (in-transaction)

SQL `trust_project_pair(subject, object)` computes the desired value and enqueues publication; it never calls MR. It takes the existing pair lock `trust_pair_lock(subject, object)`. Callers that project several pairs sort them by `(subject, object)` before locking.

```
s_k      = Σ live rows of kind k: count · decay_k(age)
           decay_k = max(0, 1 − age/linear_window_k) if linear_window set (U58)
                   = 2^(−age/hl_k) if hl set;  1 if both NULL
s_vouch  = 1 if vote_user(subject → object).amount > 0 else 0
T        = Σ_trust-kinds mix_k · s_k / (k_k + s_k)
T_recent = same fold over rows with age ≤ 180 d of kinds with counts_for_immunity, plus vouch   (U39, U58)
n_noisy  = s_noisy                                                  (phase B)
wall     = 1              if user_block(subject → object)           (phase B; phase A: ban ⇒ target 0)
         = level(n_noisy) else if T_recent < 0.05 and n_noisy ≥ 3  (phase B)
         = 0
target   = −1 if ban (phase B) | −wall if wall > 0 | T if T > 0 | 0
upsert user_trust_edge(subject, object) set trust_w, wall_d, target_w
  (delete the row only if target_w = 0 and prev_sent_weight = 0; otherwise keep the zero-target row until the publisher acknowledges it)
if needs_publish(target_w, prev_sent_weight): upsert trust_publish_queue(subject, object)
needs_publish = |target − prev| > ε  or  sign(target) ≠ sign(prev)  or  wall level changed
```

`level(n)` = the highest `wall_levels` entry with `min_n ≤ n` (3 → 0.1, 6 → 0.3, 10 → 0.6). Phase A ships with `wall_publish_enabled = false` (config row), so only the ban→0 and T branches run.

### 4.3 Publication (out of transaction)

`TrustPublisher` (TaskWorker, every 10 s; nudges only shorten the wait, they never start a second run). The connection pool makes session advisory locks unreliable, so a single publisher is enforced by a **lease with a fencing token**:
1. Acquire: `UPDATE trust_publisher_lease SET owner = @me, token = token + 1, lease_until = now() + interval '2 minutes' WHERE id = 1 AND (lease_until < now() OR owner = @me) RETURNING token`. No row ⇒ another publisher is active; return.
2. Read a batch: `SELECT q.subject_user_id, q.object_user_id, coalesce(e.target_w, 0) FROM trust_publish_queue q LEFT JOIN user_trust_edge e ON e.subject = q.subject_user_id AND e.object = q.object_user_id WHERE q.next_attempt_at ≤ now() ORDER BY q.enqueued_at LIMIT 200`.
3. Before each MR call check the lease is still ours and not expired (cheap `SELECT` with the token); stop if not. Call `mr_put_edge(subject, object, target, '', 0)`, or `mr_delete_edge` when target = 0.
4. Call `mr_sync()` once for the batch (pgmer2 0.8.1 barrier).
5. Acknowledge in one transaction that first re-checks the token (`SELECT … FROM trust_publisher_lease WHERE token = @token AND lease_until > now() FOR UPDATE`; missing ⇒ abort without ack): for every pair re-read the current `target_w` (missing row = 0); if it equals the published value, set `prev_sent_weight = target` (or, for a missing row, nothing) and delete the queue row; a row that is now `target_w = 0 AND prev_sent_weight = 0` is deleted (the trigger does not enqueue because `OLD.prev_sent_weight = 0`); otherwise keep the queue row (it will be republished). Then `mr_bump_publish_epoch()` equivalent (the existing epoch-bump used by maintenance).
6. On failure: increment `attempts`, exponential `next_attempt_at`, store `last_error`; nothing is acknowledged.
7. A crash after step 4 and before step 5 only causes a harmless republish of the same values.

The maintenance sweep keeps re-projecting pairs whose decayed value crosses ε (existing keyset sweep, retargeted to `trust_project_pair`).

### 4.4 Dart side

- `TrustEvidenceKind` (S/domain/trust/trust_evidence_kind.dart) replaces `TrustSourceType`, `TrustBin`, `TrustContext`; delete S/domain/trust/trust_math.dart.
- `TrustEvidence {subject, object, kind, count, sourceKey, beaconId?, epoch?, relatedUserId?, occurredAt?}`.
- `TrustEvidenceRepository`: `record(list)` (insert `ON CONFLICT (source_key) DO NOTHING`, then `trust_project_pair` for affected pairs in canonical order), `retract(sourceKey)`, `unretract(sourceKey)`, `project(pairs)`.
- `UserTrustEdgeCase.setUserVote` stops writing evidence; it only projects the pair. Reciprocal `vote_user` rows on invite already exist (created by callers such as S/data/repository/user_repository.dart:920); remove the evidence write in `_applyReciprocalTrustEdges` (:937).

---

## 5. Closure subsystem

### 5.1 State machine

```
open family ──close──▶ reviewOpen (epoch e, status evaluating)
   │   (never had a committer → closed directly, no epoch)
   │                 ├──reopen (≤ 1, only while evaluating) ──▶ open family  (epoch e → cancelled; drafts kept)
   │                 ├──closeNow (P3) ──┐
   ▼                 └──closes_at < now ─┴──▶ finalize ──▶ closed (epoch e → final)
 closed
```

- **Close-now (P3):** allowed when the author has an **explicit** outcome (not NULL) for every member **and** (every member of the readiness set has a commit row **or** ≥ 48 h since `opened_at`). Readiness set = voters when `|M| ≥ 3`; empty when `|M| ≤ 2` (no voting). The author never learns who is ready (U53).
- Extend: +7 days, max 2.
- Reopen: only from an evaluating epoch, `kMaxReviewReopens = 1`; `reviewOpen → needsMoreHelp` routes to the same operation (P9). Committed supports and commit rows are deleted (drafts kept, U12).
- No reopen after finalize (P10). After finalize the only writes allowed are the viewer's own bookmarks (U37, U40).

### 5.2 Serialization protocol

Every closure mutation (author or voter), every lifecycle transition (close, closeNow, extend, reopen, finalize, the expiry sweep) and every commitment-event write on a request (acknowledge, withdraw, release, remove, readmit, blocked cleanup) runs in one transaction (`MutatingUnitOfWorkPort.run`) that first takes the per-request lock `pg_advisory_xact_lock(hashtextextended(beacon_id, 4242))` — the same key the current review code uses — **before** writing anything, then re-reads `beacon.status` and the live epoch. Closure mutations reject the call if `expectedEpoch` (a required argument) differs from the live epoch or if the epoch is not evaluating (bookmarks: final allowed). The expiry sweep passes the `(beacon_id, epoch)` it selected and finalizes only if that same epoch is still evaluating and `closes_at ≤ now()` under the lock; otherwise it is a no-op.

Lock order: the global hierarchy scope lock (`tentura.beacon_hierarchy.v1`, only in operations that already take it) → per-request lock → trust pair locks in canonical `(subject, object)` order. There are no other lock orders.

### 5.3 Membership reducer

`MembershipReducer` (pure, S/domain/closure/membership_reducer.dart) maps a helper's ordered commitment events to `{member, active, departure, readmitted}` using the existing `CommitmentState` semantics:

| Event | Effect |
|---|---|
| `acknowledged` (and not rolled back within 24 h grace) | member = true; active = true; departure = none |
| `acknowledgementSoftened` | no change to membership or activity |
| `withdrawnByHelper` | active = false; departure = voluntary |
| `releasedByAuthor`, `removedFromChat`, `blockedCleanup` | active = false; departure = removed |
| `readmittedToChat`, or a later `acknowledged` | active = true; departure = none |
| `offered`, `unansweredAtClose` | no membership effect |

The author is never a member (as in `EvaluationParticipantGraphBuilder`:108). No evidence may have subject = object.

Snapshot at close: members = every user with member = true; `departure` from the reducer; `active_at_open = active`. **Voter** is derived, never stored: `voter = active_at_open AND departure IS DISTINCT FROM removed` (U49: active when evaluation opens and not removed by the author; a voluntary leave during the window keeps the vote). During the epoch, a commitment-event write runs under the per-request lock and updates `departure` from the reducer (removed, voluntary, or NULL after readmission); `active_at_open` never changes. `M_route` = members whose departure ≠ voluntary.

### 5.4 Data model

```sql
CREATE TABLE beacon_closure (
  beacon_id           text NOT NULL REFERENCES beacon ON DELETE CASCADE,
  epoch               int  NOT NULL CHECK (epoch >= 1),
  status              smallint NOT NULL CHECK (status IN (0, 1, 2)),   -- evaluating, final, cancelled
  opened_at           timestamptz NOT NULL,
  closes_at           timestamptz NOT NULL,
  extensions_used     smallint NOT NULL DEFAULT 0 CHECK (extensions_used BETWEEN 0 AND 2),
  finalized_at        timestamptz NULL,
  finalize_reason     smallint NULL CHECK (finalize_reason IN (1, 2)), -- authorCloseNow, expired
  settlement_version  int NULL,
  settlement_params   jsonb NULL,                                      -- frozen at finalize
  PRIMARY KEY (beacon_id, epoch)
);
CREATE UNIQUE INDEX beacon_closure_one_live ON beacon_closure (beacon_id) WHERE status IN (0, 1);
CREATE INDEX beacon_closure_due ON beacon_closure (closes_at) WHERE status = 0;

CREATE TABLE beacon_closure_member (
  beacon_id        text NOT NULL,
  epoch            int  NOT NULL,
  user_id          text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  arrival_edge_id  text NULL REFERENCES beacon_forward_edge ON DELETE SET NULL,
  departure        smallint NULL CHECK (departure IN (1, 2)),         -- voluntary, removed
  active_at_open   boolean NOT NULL,                                  -- voter = active_at_open AND departure <> removed
  PRIMARY KEY (beacon_id, epoch, user_id),
  FOREIGN KEY (beacon_id, epoch) REFERENCES beacon_closure ON DELETE CASCADE
);

-- Drafts live per request and survive reopen (U12).
CREATE TABLE beacon_closure_outcome (
  beacon_id   text NOT NULL REFERENCES beacon ON DELETE CASCADE,
  helper_id   text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  outcome     smallint NULL CHECK (outcome IN (1, 2, 3)),  -- NULL unanswered; 1 done, 2 not done, 3 can't judge
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (beacon_id, helper_id)
);
CREATE TABLE beacon_closure_author_split (          -- absent rows = exact equal share
  beacon_id   text NOT NULL REFERENCES beacon ON DELETE CASCADE,
  helper_id   text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  pct         smallint NOT NULL CHECK (pct BETWEEN 0 AND 100 AND pct % 5 = 0),
  PRIMARY KEY (beacon_id, helper_id)
);
CREATE TABLE beacon_closure_support (
  beacon_id   text NOT NULL REFERENCES beacon ON DELETE CASCADE,
  voter_id    text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  target_id   text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  version     smallint NOT NULL CHECK (version IN (0, 1)),   -- 0 draft, 1 committed
  pressed_at  timestamptz NOT NULL DEFAULT now(),            -- scapegoat order (U56)
  PRIMARY KEY (beacon_id, voter_id, target_id, version),
  CHECK (voter_id <> target_id)
);
CREATE TABLE beacon_closure_commit (                -- single readiness authority; may be empty (Skip)
  beacon_id    text NOT NULL REFERENCES beacon ON DELETE CASCADE,
  voter_id     text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  committed_at timestamptz NOT NULL,
  PRIMARY KEY (beacon_id, voter_id)
);
CREATE TABLE beacon_closure_mark (
  beacon_id   text NOT NULL REFERENCES beacon ON DELETE CASCADE,
  marker_id   text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  target_id   text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (beacon_id, marker_id, target_id),
  CHECK (marker_id <> target_id)
);
CREATE TABLE beacon_closure_story (
  beacon_id   text PRIMARY KEY REFERENCES beacon ON DELETE CASCADE,
  body        text NOT NULL CHECK (length(body) <= 2000),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE beacon_closure_result (                -- immutable per-viewer result, written at finalize
  beacon_id   text NOT NULL,
  epoch       int  NOT NULL,
  user_id     text NOT NULL REFERENCES "user" ON DELETE CASCADE,
  outcome     smallint NOT NULL CHECK (outcome IN (1, 2, 3)),     -- unanswered stored as 3
  band        smallint NOT NULL CHECK (band IN (0, 1, 2, 3)),     -- none, raised, asIfSilent, lowered
  draft_flag  smallint NOT NULL DEFAULT 0 CHECK (draft_flag IN (0, 1, 2)),  -- none, notCounted, lastEditNotCounted
  helped      double precision NOT NULL,                          -- server-only; never exposed by any API
  PRIMARY KEY (beacon_id, epoch, user_id),
  FOREIGN KEY (beacon_id, epoch) REFERENCES beacon_closure ON DELETE CASCADE
);
```

Dropped: `beacon_evaluation`, `beacon_evaluation_ack_tag`, `beacon_evaluation_participant`, `beacon_evaluation_visibility`, `beacon_review_status`, `beacon_review_window` (with its Hasura tracking and relationship, §11). Before dropping, `m0203` moves every request with `status = 5` (reviewOpen, legacy window) to `needsMoreHelp(7)` and retires its legacy review obligations; no evidence is minted for legacy windows (old data is discarded by product decision). Account erasure (`UserErasureRepository`) stops deleting the dropped tables; the Drift table classes and `TenturaDb` registrations of all dropped tables are removed.

None of the closure tables are tracked in Hasura; all access goes through the GraphQL V2 resolvers (§7).

Write rules (under the beacon lock):
- **Author split.** A = members with outcome done, can't-judge or unanswered. Split rows absent ⇒ exact equal. Otherwise rows cover exactly A, sum to 100, each ≥ 5 when 2 ≤ |A| ≤ 20; |A| = 1 ⇒ that member 100; |A| = 0 or |A| > 20 ⇒ rows are deleted (null mode) and the UI disables custom split (U50). On outcome change, and when a new epoch is created, the vector is renormalized over the current A (a newcomer to A gets weight `100/|A|`, the rest keep their weights) and re-apportioned (§5.5.1).
- **Support.** Mutations are atomic toggles (`closureToggleSupport(target, on)`) on version 0 with `pressed_at = now()`. If a toggle would make the draft cover all other members, the server removes the row with the earliest `pressed_at` among the others and returns the released target (U56); a committed version covering all others is treated as silence by settlement. Only `voter = true` members may write support.
- **Done** copies version 0 to version 1 (replacing it) and upserts the commit row. **Skip** deletes version 1 rows and upserts the commit row. **Reopen** deletes version 1 rows and commit rows.
- **User deletion** cascades that user's rows only; other members' `beacon_closure_result` rows are never recomputed.

### 5.5 Settlement algorithm (pure Dart)

File S/domain/closure/episode_settlement.dart; no I/O; `settlementVersion = 1`.

```
Input:
  M            members, sorted by user id (results must not depend on order)
  outcome[i]   done | notDone | cantJudge | unanswered   (unanswered is treated as cantJudge, U55)
  a[i]         author split in % over A, or null (exact equal)
  voter[i]     bool (U49)
  support[i]   committed set ⊆ M∖{i}, or none
  marks        list (marker, target); marker may be the author
  params       B = 1.0, ρ = 0.3, α_A = 0.5, β = 0.5, t = 0.5, bandThreshold = 0.15
Output: helped[j], band[j], lost, marks, C (close-ack set)

A = {i : outcome[i] ≠ notDone};  C = {i : outcome[i] = done}
if a is null: a[i] = 100/|A| for i ∈ A;  a[i] = 0 for i ∉ A
pool_h = (1 − ρ)·B
if |A| = 0: helped ≡ 0; lost = 0; band ≡ none; return          # nothing minted
n = |M|;  α = α_A if n ≥ 3 else 1
authorPart[j] = α·pool_h·a[j]/100
slice[i]      = (1 − α)·pool_h·(β/n + (1 − β)·a[i]/100)          # Σ slice = (1 − α)·pool_h
for i in M:
  O = M∖{i};  S = Σ_{k∈O} a[k]
  U = support[i] if voter[i] and n ≥ 3 else ∅
  if U = O: U = ∅                                                 # all supported = silence (U56)
  if S = 0:                                                       # author gave everything to i
    if U ≠ ∅: imp[j] += slice[i]·t/|U| for j ∈ U;  lost += slice[i]·(1 − t)
    else:     lost += slice[i]
    continue
  base(k) = a[k]/S for k ∈ O
  if U = ∅: dir = base
  else:
    N = O∖U
    take = Σ_{k∈N} t·base(k);  dir(k) = (1 − t)·base(k) for k ∈ N
    dir(j) = base(j) + take/|U| for j ∈ U
  imp[k] += slice[i]·dir(k) for k ∈ O
helped[j] = authorPart[j] + imp[j]
silent = the same computation with support ≡ none
band[j] = none        if n ≤ 2, or (helped[j] = 0 and silent[j] = 0)
          raised      if silent[j] = 0 < helped[j], or helped[j] > (1 + bandThreshold)·silent[j]
          lowered     if helped[j] < (1 − bandThreshold)·silent[j]
          asIfSilent  otherwise
```

**Invariants (property tests with a seeded generator, n = 1…8, plus fixed vectors):**
- Impartiality: changing i's support or marks never changes `helped[i]`.
- Monotonicity: support never gives j less than i's silence would; an unsupported member never gets more from i than i's silence.
- Supporting works: if some unsupported member has base > 0, a supported member gets strictly more than under i's silence.
- All supported ≡ silence.
- Conservation: for non-empty A, `Σ helped + lost = pool_h`; for empty A, everything is 0.
- Permutation invariance; marks never affect shares; not-done members get no author part; silence with equal author split over all members ⇒ equal shares; n = 2 ⇒ author split; n = 1 ⇒ `pool_h` if in A.

Reference vectors (α = β = t = 0.5, n = 3, % of pool_h, order Masha / Petya / Olya): author 70/20/10 silent → 55.1/29.6/15.3; Masha supports Olya → 55.1/21.0/23.9; equal author, mutual pair support → 37.5/37.5/25.0; author 50/50/0 (Olya not done), both support Olya → 39.6/39.6/20.8; done/notDone/notDone, silence → 66.7/0/0 with 33.3 lost.

#### 5.5.1 Author split apportionment

`apportion(total, weights, min)` — proportional with a lower bound (water-filling), so members above the minimum keep their proportions: (1) `target_j = rem·w_j/Σw` over not-yet-fixed members, `rem = total − min·|fixed|`; every member with `target_j < min` is fixed at `min`; repeat until nobody new is fixed. (2) `units_j = floor(target_j/5)`; the remaining `total/5 − Σunits` units go to the largest fractional parts, ties broken by `sha256(beacon_id + ':' + helper_id)` hex ascending; `pct_j = 5·units_j`. Used for renormalization and for the moved-slider update (the moved member's value is clamped to `[min, 100 − min·(|A|−1)]`, rounded to 5, and the others share `100 − value`). (Rev 2 reserved the minimum for everyone first and split the rest; that version moved a 70 % member to 50 % when a fourth member returned, so it was replaced.) Hand-computed vectors including |A| = 19, 20, 21 are part of the tests (the simulator caps at 8 members and is not the oracle for this).

#### 5.5.2 Support scales with the hidden author split (rev 5)

The helper never sees the author split (blind round, U40), so the support toggle must not ask "whom did the author underrate". It asks for the helper's own judgement ("whose work was important"), and the rule performs the correction relative to the author: the bonus from voter i to a supported j is `slice_i · t · Σ_{k∈N} base_i(k) / |U_i|`, so it is larger when j's author share among i's colleagues is small; an unsupported k pays `slice_i · t · base_i(k)`, in proportion to what the author gave k. No code change — this is a property of §5.5, pinned by vectors V16–V20 in the step plan (unit A7a).

Vectors (α = β = t = 0.5, n = 3, % of pool_h, order Masha / Petya / Olya; author gives Masha 30; Masha supports Olya, others silent): 30/70/0 (Olya not done) Olya 0 → 7.9, Petya 56.7 → 48.8; 30/50/20 Olya 22.9 → 28.5; 30/35/35 Olya 34.6 → 38.6; 30/10/60 Olya 50.8 → 51.9; 30/0/70 (Petya not done) no change.

Residual social risks (plan §4.2): salience/halo (support tends to agree with the author; damped by the shrinking bonus), "just in case" support of a quiet member, no ingratiation motive (the author never sees votes, U36), perceived vote futility (the helper never sees the effect; metric in §13), pair collusion (U43).

### 5.6 Arrival edge (stream 2 and member snapshot)

`selectArrivalEdge(beaconId, helperId, offerCreatedAt)` (new repository method): the `beacon_forward_edge` with `recipient_id = helperId`, `beacon_id = beaconId`, `created_at ≤ offerCreatedAt`, and not cancelled at that time (`cancelled_at IS NULL OR cancelled_at > offerCreatedAt`), ordered by `created_at DESC, id DESC`, first row. Its value is frozen at approval (stored on the evidence row as `related_user_id` = forwarder and in `metadata.arrival_edge_id`) and copied into `beacon_closure_member.arrival_edge_id` at close. The routing engine keeps using the full DAG.

### 5.7 Stream 2 (approval edge)

- In `CoordinationCase.acceptHelpOffer()`: `edge = selectArrivalEdge(…)`; F = `edge.sender_id`; if F ≠ author, under `trust_pair_lock(helper, F)`: if a row with `source_key = approval:<beacon>:<helper>` exists → `unretract`; else if no live `useful_forward` (helper→F) with `occurred_at > now − 30 d` → record `helper→F useful_forward 1` with that key.
- On `withdrawnByHelper` and on acknowledgement rollback within the 24 h grace → `retract('approval:<beacon>:<helper>')` and project. Removal by the author and `blockedCleanup` do not retract (U11).
- Re-acknowledgement after withdrawal (a later `acknowledged` event in `acceptHelpOffer()`) → `unretract` (original `occurred_at` preserved).
- Tests: approve → edge; voluntary withdraw → retracted; re-accept → restored with original date; author removal → kept; helper who came without a forward → no edge; 30-day dedup across two requests, concurrently.

### 5.8 Routing settlement (stream 1)

Rename `ForwardOutcomeFinalizer` → `ForwardRoutingSettlement`:
- Seeds: `M_route` (members except voluntary leavers), mass 1.0 each; outcome ignored (U15, I4).
- Budget per sender per episode = ρ·B.
- Output: `routed` evidence on sender → recipient, `source_key = closure:<beacon>:<epoch>:routed:<sender>:<recipient>`.
- Delete `forward_outcome_policy.dart`, the `negativeRoute` provenance and `unsuccessfulRequestForward`.

### 5.9 Finalize

One transaction under the beacon lock:
1. Re-check the epoch is the expected one and evaluating (sweep: and `closes_at ≤ now`); set status final, `finalized_at`, `finalize_reason`, `settlement_version`, `settlement_params`; `beacon.status = closed`; lifecycle activity event.
2. Load members, outcomes, split, committed supports, marks, forward DAG; run `EpisodeSettlement` and `ForwardRoutingSettlement`.
3. Insert `beacon_closure_result` for every member (outcome, band, draft flag, helped). Draft flag: `notCounted` if the voter has a draft and no commit; `lastEditNotCounted` if the draft differs from the committed version.
4. Record evidence (`helped`: `closure:<b>:<e>:helped:<j>`; `routed`; `marked`: `closure:<b>:<e>:mark:<x>:<y>` with `occurred_at = finalized_at`; `worked_with_author` per §5.9a; `supported_colleague` per §5.9b) and project affected pairs (enqueue publication).
5. Close-ack capability events for C over the offer's helpTypes.
6. Story → room system message kind 3 `closureStory` if non-empty.
7. Receipts (§9) with per-recipient source keys.
8. Preserve the current close effects: `recordBeaconStatusTransition`, `BeaconLifecycleEffectsCase.recordEligibleSourceTransition` (parent/child requests), `unansweredAtClose` events for pending offers and `supersedeAuthorHelpOfferObligationsOnBeaconClose` — in whichever of close / direct close / finalize the current code runs them (S/domain/use_case/evaluation_case.dart:169–234, review_finalization_case.dart:76–105).

After commit the finalize path nudges `TrustPublisher`. MR being down only delays publication; no closure state depends on it.

### 5.9a Helper → author edge (U58)

Written only by finalize (never on a cancelled epoch):
```
P = { members of the epoch with departure IS NULL at finalize time }   # present until closure
for i in P:  i → author  worked_with_author  count = 1/√|P|
             source_key closure:<b>:<e>:author_edge:<i>,  occurred_at = finalized_at
```
- Independent of the author's outcome and split (otherwise the author gains by marking "done").
- The total inbound mass per episode for the author is bounded by √|P| (count units), so a large episode does not turn the author into a hub.
- Protection for the helper: leaving before closure (voluntary withdrawal) writes no edge; the author removing someone also writes none. For obvious abuse the ban overrides the pair at projection (phase A: target 0; phase B: −1).
- Kind 8 has `counts_for_immunity = false`: working for an author never grants the author immunity from the noisy-contact wall.
- Not retracted after finalize; later removal of the edge only via ban. A bookmark on the author strengthens it.
- Strength: one edge ≈ 0.08·c/(1+c) with c = 1/√|P| (|P| = 1 → 0.04; 4 → 0.027; 9 → 0.02); pair ceiling 0.08; linear decay to 0 over 180 days.

### 5.9b Support edge (U59)

Horizontal edges come only from the supporter's own choice; the settlement consensus still writes only the author's `helped` edges.
```
for i in V, if |M| ≥ 3 and ∅ ≠ U_i ≠ M∖{i}        (the support that entered the settlement: committed version, voter)
  for j in U_i:  i → j  supported_colleague  count = 1/√|U_i|
                 source_key closure:<b>:<e>:support_edge:<i>:<j>,  occurred_at = finalized_at
```
- Written even when the support gave j zero bonus (e.g. every unsupported colleague is not done): a conditional edge would leak other members' outcomes.
- Independent of j's outcome and departure; a cancelled epoch writes nothing; ban overrides at projection.
- Outgoing budget per episode √|U_i|; one support ≈ 0.05, two ≈ 0.041 each; linear decay to 0 over 180 d; `counts_for_immunity = false` (immunity only from bookmarks and help).
- Copy under the ▲▼ legend and in (i): "Поддержка ещё и чуть усиливает твою связь в сети с теми, кого ты выбрал. Им не придёт уведомление".
- Rejected alternative (plan §1.4): equal-peer range-vote split with every member writing edges to all others by share — compelled endorsement, Sybil channel, per-episode cliques, preferential attachment.

### 5.10 Bookmarks after closure

`closureSetMark(beaconId, expectedEpoch, targetId, on)` on a final epoch: `on` → record or unretract `closure:<b>:<e>:mark:<me>:<target>` with `occurred_at = finalized_at`; `off` → retract; project the pair. Allowed: helpers mark other members and the author; the author marks members. Former members keep this right (§7).

---

## 6. Phase 0 and phase B details

**Phase 0**
- `m0201`: `trust_rebuild_effective_edge` sets `_target = CASE WHEN blocked THEN 0 ELSE greatest(_w, 0) END` (block override kept); operator runs `trustForceRefreshAll` after deploy.
- Bump `postgres-tentura` to the pgmer2 0.8.1 tag in compose.dev.yaml, compose.prod.yaml and CI; call `mr_sync()` before `mr_bump_publish_epoch()` in the rebuild batch and maintenance.
- Audit absolute score thresholds (`merit_score_lookup`, `mr_score_value`, visibility thresholds, clusters) for the ~6× scale change of MR 0.11.0.

**Phase B**
- Ban: projection yields −1 even without a trust row; sign/level changes bypass ε; `TrustCutoverCase`-style bootstrap loads negatives.
- Noisy contact. `beacon_forward_edge` gets `contact_outcome smallint NULL` (1 engaged, 2 declined, 3 ignored), `contact_resolved_at`, `contact_deadline_at` (= `created_at + 7 d + jitter`, jitter ∈ [−1 d, +1 d] from `hash(edge_id)`; set only for edges created after `m0204`; no backfill). Index `(contact_deadline_at) WHERE contact_resolved_at IS NULL`.

  | Transition | Writer | Evidence |
  |---|---|---|
  | edge created, sender = recipient or recipient = request author | forward case | none; `contact_outcome` left NULL, `contact_deadline_at` NULL |
  | recipient offers on the request, or forwards it on, before deadline | help-offer / forward cases | `engaged` recipient→sender, key `contact:<edge>:engaged`; resolve |
  | recipient declines ("не могу помочь") | inbox case | none; resolve as declined |
  | sender cancels before resolution | forward case | none; resolve (outcome NULL, resolved_at set) |
  | deadline passes unresolved | `ContactResolutionSweepCase` (1 h, `FOR UPDATE SKIP LOCKED`) | `noisy` recipient→sender, key `contact:<edge>:noisy`; resolve as ignored |
  | engagement after `ignored` | help-offer / forward cases | retract `contact:<edge>:noisy`, record `engaged`; outcome → engaged |
  | Watching | — | neutral (U19) |

  All writers lock the edge row (`FOR UPDATE`) before resolving.
- Display factor for forward candidates: `score × (1 − min(0.8, Σ 2^(−age/1 d)))` over own forwards to the candidate in the last 7 days; never published.
- λ stays 0.

---

## 7. API (GraphQL V2) and authorization

Every closure mutation takes `beaconId` and `expectedEpoch` (except `beaconClose`) and runs the protocol of §5.2.

| Mutation | Args | Who | Rules |
|---|---|---|---|
| `beaconClose` | `beaconId` | author | open family; creates epoch or closes directly |
| `beaconCloseNow` | + `expectedEpoch` | author | P3 |
| `beaconExtendClosure` | + `expectedEpoch` | author | max 2 |
| `beaconReopen` | + `expectedEpoch` | author | evaluating; ≤ 1 |
| `closureSaveOutcome` | `helperId, outcome` | author | evaluating |
| `closureSaveAuthorSplit` | `split: [{helperId, pct}] \| null` | author | §5.4 rules |
| `closureToggleSupport` | `targetId, on` | voter | draft; returns `{released: ID?}` (U56) |
| `closureDone` | — | voter | draft → committed |
| `closureSkip` | — | voter | empty committed version |
| `closureSetMark` | `targetId, on` | member or author | evaluating or final |
| `closureSaveStory` | `body` | author | evaluating |

**Read authorization.** `closureState` and `closureResultForViewer` authorize by closure role, not by `beaconContent`: the author of the request, or a user with a `beacon_closure_member` row for the relevant epoch (including former and removed members, and blocked members for their own result only). Outsiders get "not found".

| Field | Author | Voter | Former / non-voter member |
|---|---|---|---|
| members (name, avatar, offer helpTypes/text) | all, with departure detail | all, `notInRequest` flag only | all, `notInRequest` flag only |
| outcomes, split | own writes | — | — |
| own draft / committed support, "В расчёте" text | — | yes | — |
| own marks | yes | yes | yes |
| deadline, `earlyCloseAt`, `canCloseNow`, `canReopen` | yes | deadline, `earlyCloseAt` | deadline |
| story | yes | after finalize | after finalize |
| result: own outcome, own band code, draft flag | — | yes | yes |

- `closureResultForViewer` returns only `{outcome, band: raised | asIfSilent | lowered | none, draftFlag, marks, story}`. **No numeric share field** exists in the schema (contract test, U57). `helped` never leaves the server.
- No resolver returns another user's support, split value, mark or result.
- Room content access is unchanged: membership in a closure does not grant room read access.

Removed: all `evaluation*` operations, `reviewWindowStatus(es)`, `evaluationsWrittenAboutMeBy`, `evaluationReceived`.

---

## 8. Client architecture

### 8.1 Feature module

Rename `C/features/evaluation` → `C/features/closure`: `ClosureRepository`, `ClosureCase`, entities `ClosureState`, `ClosureMember`, `ClosureOutcome`, `ClosureSupport`, `ClosureMark`, `ClosureResult`; cubits per screen. `BeaconViewCase` and `MyWorkCase` use the new repository. Route `/beacon/closure/:id` (author or helper screen by role); remove `/beacon/review` and `/beacon/reviews-received`. Remove `beacon_review_window` from `C/data/gql/beacon_model.graphql` and regenerate GraphQL code.

### 8.2 Screens and acceptance criteria

- **Author "Подвести итоги" (A10):** member rows (leavers last, "ушёл"/"исключён"), outcome picker (vertical list on narrow screens; hint "«Не выполнено» убирает человека из твоего распределения; «Не могу судить» оставляет его в равной доле"), bookmark 🔖; split section locked until "Изменить распределение" (unlock does not change values), "Вернуть поровну", live preview bars with names "если коллеги промолчат"; story with hint; deadline, extend, close-now with explanation "Можно закрыть раньше после <время>, или когда все помощники ответят" (no list of who answered); for two helpers "Долю каждого распределяешь ты. Каждый из двоих поймёт по своему итогу, как ты разделил".
- **Helper "Поддержать коллег" (A11):** always (also for 1 or 2 members) the U58 notice "Когда запрос закроется, в сети появится слабая связь от тебя к автору: вы работали вместе. Не хочешь её — выйди из запроса до закрытия"; header "Чья работа, по-твоему, была важной? Твоя часть от этого не меняется" (not "beyond the author's decision": the helper does not see it); one toggle per colleague "☆ Поддержать / ★ Поддерживаю"; ▲/▼ indicators after the first press with legend "▲ получат добавку — ▼ её отдадут те, кого ты не выбрал" followed by the U59 line "Поддержка ещё и чуть усиливает твою связь в сети с теми, кого ты выбрал. Им не придёт уведомление"; scapegoat hint "Поддержать всех — то же, что никого. Кто-то должен отдать: снята самая ранняя (…)"; status line "В расчёте: поддержаны …" / "В расчёт ещё не входит" / "На экране иначе — «Готово» заменит расчёт"; Done; "Пропустить — не отмечаю никого" with "Твоя часть не меняется никогда" and a confirm if a committed version exists; "Автор может закрыть после <время> — или раньше, когда ответят все"; privacy line "В приложении твой выбор не видят. По своим итогам другие могут о нём догадаться"; bookmark copy "Закладка чуть усиливает твою связь с этим человеком в сети. Ему не придёт уведомление, части в этом запросе не меняются. Поставить и снять можно и позже". The (i) sheet (`share_flow_diagram.dart`, `CustomPainter` + `TenturaAvatar`) draws **equal grey example flows labelled "пример"**, never real author allocations (U20); under the diagram the text «Ты не знаешь, как решил автор, — и знать не нужно. Поддержи тех, чья работа, по-твоему, была важной. Если автор уже оценил человека высоко, добавка будет маленькой; если низко — заметной. Отдают в основном те, кому автор дал больше. Автор твой выбор не видит».
- **Results card (A12):** outcome line; band sentence ("Коллеги подняли твою часть" / "Твоя часть — как если бы коллеги промолчали" / "Коллеги опустили твою часть"); "Автор отметил: не выполнено — части в итогах нет" only when the outcome is not done **and** the band is none (a not-done member supported by colleagues gets a positive part and the raised sentence); draft line ("Твои отметки не вошли…" / "В расчёте прошлая версия…"); own bookmarks with toggles.
- **My Work (U6):** the archive affordance is shown for helper cards on **open** requests too (derivation change around `showArchiveAffordance`); archiving only hides the card for the viewer — no departure, no evidence.

All styling via the design system (`material-3-flutter` skill); desktop affordances (hover toolbar, keyboard) per the cross-platform gesture rule.

### 8.3 Removal

Delete review screens, cubits, widgets, presenters, `ReviewPackageState`, `ReviewWindowInfo`, `EvaluationValue`, the profile "reviews about me" sliver and review receipt copy; replace ~183 `evaluation*` / `review*` l10n keys with `closure*` (en + ru).

---

## 9. Notifications and jobs

| Event / job | Recipient | Source event key | Access policy |
|---|---|---|---|
| `closureOpened` | author ("подведи итоги", obligation); voters when \|M\| ≥ 3; other members ("можешь поставить 🔖") | `closure_opened:<beacon>:<epoch>:<recipient>` | author/voters: beacon_content; others: recipient_safe |
| `closureDraftReminder` | voters with (non-empty draft and no commit) or (a commit and a draft target set different from the committed one), 24 h before `closes_at` | `closure_draft_reminder:<beacon>:<epoch>:<voter>` | beacon_content |
| `closureFinalized` | every member (payload: outcome, band code, draft flag) | `closure_finalized:<beacon>:<epoch>:<recipient>` | beacon_content, or recipient_safe for removed/blocked members |
| `closureCancelled` | members | `closure_cancelled:<beacon>:<epoch>:<recipient>` | as above |
| `requestStale` | author | `stale_request:<beacon>:<ISO week-year>-W<week>` | beacon_content |

- Extend the `recipient_safe` presentation-key allowlist (M:5698) with `closure_opened_bookmark_only`, `closure_finalized`, `closure_cancelled`.
- `StaleRequestReminderSweepCase` (1 h): open family and (`end_at < now` or last activity < now − 14 d), where last activity = max of `beacon_room_message.created_at`, `beacon_activity_event.created_at`, `beacon_help_offer.updated_at`, `beacon_commitment_event.created_at`, `beacon.status_changed_at`, falling back to `beacon.created_at`. No helpers required (U18).
- `ClosureDraftReminderSweep` (1 h) and `ClosureFinalizeSweep` (replaces the review path in `AttentionExpirySweepCase`, uses `beacon_closure_due`; selects `(beacon_id, epoch)` and passes the epoch to finalize, §5.2).
- Receipts are written inside the finalize / open / cancel transaction.
- Remove `reviewOpened`, `reviewAllPackagesIn`, `reviewWindowCancelled`, `trustGivenChanged`, `trustReceivedChanged`; update `AttentionPolicy`, destination map, `updates_event_contract_test`.

---

## 10. Migrations

Migrations are SQL-only and must succeed on a database **without** pgmer2 (test templates). They never call MR.

| Migration | Content |
|---|---|
| `m0201` (phase 0) | `trust_rebuild_effective_edge` publishes `greatest(w, 0)` |
| `m0202` (A) | trust ledger, kinds, publish queue, publisher lease; projection function; rewritten deletion-trigger function (enqueue, no MR call); drop old trust tables/functions and `meritrank_edge_tombstone`; **empty** `user_trust_edge` (all rows, trigger disabled for the wipe); insert `trust_cutover_state(status = 'pending')` |
| `m0203` (A) | closure tables and indexes; legacy `status = 5` requests → 7; drop review tables; extend `recipient_safe` allowlist (room system kind 3 needs no constraint change, only constants) |
| `m0204` (A) | seed kind 9 `supported_colleague` (U59) — `m0202` is already implemented |
| `m0205` (B) | forward-edge contact columns and index; wall levels config; `wall_publish_enabled = true` is flipped by config after deploy |

Never edit a shipped migration; verify the next free number at implementation time.

---

## 11. Deployment and trust cutover (phase A)

`TrustCutoverCase` runs at server startup after migrations and after the pgmer2 upgrade (S/app/app.dart:27 ordering), only when `trust_cutover_state.status = 'pending'`, with `TrustPublisher` paused (it checks the state row). Mutual exclusion uses the same lease-with-token pattern as the publisher (columns `owner`, `token`, `lease_until` on `trust_cutover_state`, lease 10 min, renewed between steps, token re-checked in the final transaction), because session advisory locks do not survive the connection pool:
1. Project every pair that has `vote_user.amount > 0` into `user_trust_edge` (nothing else exists after the wipe).
2. `mr_reset()`.
3. `meritrank_init()` — loads `target_w` of all projected pairs plus polling edges (updated to read `target_w`), then `mr_sync()`.
4. Set `prev_sent_weight = target_w` for all rows; clear the publish queue; `status = 'done'`.

It is restartable: each step is idempotent; a crash leaves status `pending` and the next start repeats from step 1.

Release sequence (one maintenance window; testers only):
1. Stop the web client (maintenance page) and server workers.
2. Apply migrations `m0202`, `m0203`.
3. Apply Hasura metadata without `beacon_review_window` and without any closure table.
4. Start the server (runs pgmer2 upgrade, then `TrustCutoverCase`, then workers).
5. Deploy the web client built with the new GraphQL schema; bump `packages/client/pubspec.yaml` version and the `packages/client/web/index.html` bootstrap cache-buster; raise `kDefaultMinClientVersion` (S/env.dart:79) to the new version (keep `release_client_version_floor_test` green).

---

## 12. Test strategy

### 12.1 Levels

| Level | What |
|---|---|
| Pure unit (server) | `EpisodeSettlement` invariants (§5.5) with a seeded generator; reference vectors; apportionment vectors 19/20/21; `MembershipReducer` event table; `ForwardRoutingSettlement` with the new seeds; projection formula |
| pg (`--tags pg`) | ledger idempotency, retract/unretract, projection from ledger, vouch as state; publish queue enqueue; closure write rules (U50, U56 scapegoat, voter rules, Done/Skip/reopen); serialization races (voter Done vs finalize, stale `expectedEpoch`); finalize end-to-end (results, evidence, receipts, close-acks) with MR absent; stream 2 approve/withdraw/re-accept/remove; user deletion leaves others' results intact |
| pg+mr (`--tags mr`, `-j 1`, nightly) | TrustPublisher: publish, `mr_sync`, ack, retry on failure; cutover task end-to-end; phase 0 no negative weights; phase B ban wall, bootstrap, locality (A9) |
| API | contract tests: `closureResultForViewer` has no numeric share; role-dependent `closureState`; outsiders get not found; no other user's support/split/mark visible |
| Widget | A10/A11/A12 states and copy, scapegoat hint, "В расчёте", Skip confirm, narrow + 12 members, semantics; My Work archive on open helper cards |
| e2e (web) | close with 3 helpers, support + bookmark + Done, auto-close, results; reopen prefill; bookmark toggle after close |

All local runs via `scripts/run_with_test_cleanup.sh`, serially.

### 12.2 Comprehension test

Before launch, per plan §8 (RITE rounds, then 20 per role; questions and pass criteria listed there).

### 12.3 Simulator

`docs/plans/episode-closure-simulator.html` implements §5.5 (`settle()`, `bandOf()`, `toggleSupport()`) for n ≤ 8. It is a design aid and a cross-check for the fixed vectors, not an oracle for apportionment beyond 8 members.

---

## 13. Observability

Pilot metrics (plan §8): effect of supports vs the same episode in silence (from `beacon_closure_result.helped` vs a silent recomputation with the frozen parameters); share of Skip / no Done; edits after Done without re-commit; author split changes < 10 pp within 2 s of unlock; bookmarks per episode and removals after close; (i) opens; vote efficacy — share of voters who commit Done with at least one support, by the ordinal of the episode for that person (decline = "my vote does nothing"); share of supports that go to the member with the largest author share among the voter's colleagues (halo); room messages with numbers or "спасибо" after close; return rate by band. Publisher health: queue depth, oldest `enqueued_at`, attempts, `last_error`.

---

## 14. Risks and open points

| Risk | Mitigation |
|---|---|
| Pair projection from ledger is slow | Few rows per pair; partial index; measure on the seed-society dump |
| Publisher lag or MR outage | Queue with retry; closure state independent of MR; health metrics |
| Author power (α_A, outcomes, removals, two-helper case) | By design (U49); pilot α_A and β |
| Pair collusion | Accepted (U43); band threshold hides a single pair |
| Support edge (U59) adds a "support people I want in my network" motive | Own share still independent of the vote; weak, √-budgeted, 180-day decay; metric: supports to members with prior mutual bookmarks |
| Helper cannot know the author split, so support feels like guessing or futile | Support asks for own judgement; the rule self-scales (§5.5.2); (i) text; comprehension question 12; vote-efficacy metric (§13) |
| Helper → author edge (U58) lends mass to a fake author | Each edge costs real help; weak, √n-budgeted per episode, saturates per pair, linear decay 180 d; exit before closure and ban; no wall immunity |
| Users misread the UI | Single toggle, indicators, scapegoat hint, "В расчёте", comprehension test |
| Score scale ×6 in MR 0.11.0 | Phase 0 audit |
| Cutover partially applied | Restartable `TrustCutoverCase`, publisher paused until done |

---

## 15. Review log

- rev 6 (2026-09-29) — plan rev 23: U59 support edge (kind 9 `supported_colleague`, §5.9b, migration `m0204`; phase B migration becomes `m0205`); rejected equal-peer all-to-all scheme recorded in plan §1.4.
- rev 5 (2026-09-29) — plan rev 22: support is the helper's own judgement, not a guess about the author; §5.5.2 self-scaling with vectors; new helper header and (i) text; vote-efficacy and halo metrics; risk row.
- rev 4 (2026-09-29) — U58 (plan rev 21): kind 8 `worked_with_author`, helper → author at finalize for members present until closure, `count = 1/√|P|`, linear decay over 180 d, excluded from `T_recent`; kind config gets `linear_window_s` and `counts_for_immunity`.
- rev 3 (2026-09-29) — inherited findings from the Codex review of the step plan: real `user_trust_edge` column names and trigger name; deletion trigger enqueues instead of calling MR, tombstones dropped; publisher and cutover exclusivity via lease + fencing token (pooled connections); per-request lock key `hashtextextended(beacon_id, 4242)` also taken by commitment-event writers, with a defined lock order; sweep finalizes only the selected epoch; `voter` derived from `active_at_open` and `departure`; legacy reviewOpen requests → needsMoreHelp; Drift/erasure cleanup; apportionment switched to water-filling; empty/singleton A; current close effects preserved; draft-reminder audience narrowed; not-done result text conditional on band.
- rev 2 (2026-09-29) — Codex gpt-6-astra (high) architecture review, all findings applied: MR reset/bootstrap moved out of migrations into a restartable `TrustCutoverCase` (1); live dependencies on dropped tables removed and a quiesced release sequence added (2); single per-beacon lock and `expectedEpoch` on every mutation (3); full projection wipe incl. non-vote pairs, tombstones kept (4); publication moved to a durable queue acknowledged after `mr_sync` (5); immutable `beacon_closure_result` and frozen settlement params (6); unanswered outcome as NULL, split in its own table, P3 requires explicit answers (7); causal `selectArrivalEdge` instead of the display path query (8); unretract on re-acknowledgement, pair-locked dedup (9); `MembershipReducer` event table, author excluded (10); closure-role read authorization and field allowlist, receipt policies (11); all-supported = silence with server-side scapegoat via atomic toggles (12); phase B transition table and wall levels (13); U6 open-request archive (14); small-group readiness and `canReopen` (15); conservation for empty A and apportionment spec with 19/20/21 vectors (16); FKs, domain checks, due indexes, single readiness authority (17); receipt source keys, activity sources, ISO week-year (18); U20/U36/U44/U53 copy and exact version files (19); nonexistent kind 8 removed (20); code references corrected (`acceptHelpOffer`, `fetchHelpOffererPathChain` signature, reciprocal vote creation site).
- rev 1 (2026-09-29) — initial translation of plan rev 20.
