# User→user trust edges (Dirichlet / VSIDS)

**Product:** MeritRank is a hidden procedural layer for routing and local trust calibration — not a public reputation score ([`../Tentura_current_status_quo.md`](../Tentura_current_status_quo.md) §10). User→user weights accumulate evidence from votes and finalized reviews; they are never shown as a global leaderboard.

## Engineering

User→user MeritRank weights are derived from a 5-bin Dirichlet model. Since migration **m0122**, storage is split:

| Table | Role |
|-------|------|
| `user_trust_source_edge` | Per-context **source accumulators** (`trust_context`, `subject`, `object`, `s_*`, fixed `anchor_at`). Evidence inflates the relevant bin (VSIDS-style: inflate the bump, not the whole star). Contexts: `personal`, `commitment`, `forward`, plus `legacy` (migration copy only — not writable at runtime). |
| `trust_context_config` | Per-context `evidence_multiplier` applied when projecting into the effective edge (defaults: `legacy`/`personal`/`commitment` = 1.0, `forward` = 0.20). |
| `trust_evidence_event` | Append-only **evidence ledger** (source type, request id, bin, count, metadata). Idempotent inserts; drives accumulator updates. |
| `user_trust_edge` | **Effective projection** for MeritRank: deflated bin sums for one `(subject, object)` pair, `anchor_at` reset on each rebuild, `prev_sent_weight` for epsilon-gated MR publish. |
| `trust_policy` | Singleton row (`half_life_seconds`, `epsilon`) — sole canonical decay/publish policy. |
| `meritrank_edge_tombstone` | Deferred `mr_delete_edge` failures when an effective row is removed. |

**Math lives in SQL only** (`trust_edge_weight` for the posterior mean; projection/rebuild in `trust_rebuild_effective_edge`). Dart passes bin keys, evidence magnitude, and trust context; it does **not** pass half-life or epsilon (SQL reads `trust_policy`).

**Dropped in m0122 (do not reference):** `trust_apply_evidence`, `meritrank_sweep`, `trust_recompute_all`, and the old two-argument `trust_resync_source(subject, half_life_seconds)`.

### Dart call graph (production)

| Path | SQL / effect |
|------|----------------|
| `TrustEvidenceRepository.record()` | Insert `trust_evidence_event` → `trust_apply_source_evidence` per item → `trust_rebuild_effective_edge` per affected pair. Used by votes (`UserTrustEdgeRepository`), review finalization (`ReviewFinalizationCase`), invite signup trust seeding (`UserRepository`), etc. |
| `UserTrustEdgeRepository.setVoteAmount*` | Updates `vote_user`, then `TrustEvidenceRepository.record()` with `TrustContext.personal` / `TrustSourceType.userVote`. |
| `UserTrustEdgeRepository.forceRefreshStar()` | `trust_resync_source(sourceUserId)` — rebuilds every outgoing pair for one star, epsilon bypass (`-1`). |
| `TrustMaintenanceCase.runDue()` | `trust_rebuild_effective_batch` in time/batch-bounded loops (scheduled decay drift + tombstone drain). Registered on `TaskWorkerCase`. |
| `UserTrustEdgeCase.forceRefreshAll()` | `TrustMaintenanceCase.forceRefreshAll()` — full bounded sweep with `epsilon_override = -1`. |
| `UserBlockRepository` (block/unblock paths) | `trust_rebuild_effective_edge(subject, object, epsilon)` — m0137 publishes weight `0` when `user_block` exists. |
| GraphQL `userVote` / `userSubscribe` / `userUnsubscribe` | `UserTrustEdgeCase` → repository chain above. |
| GraphQL `trustForceRefreshStar` / `trustForceRefreshAll` | `UserTrustEdgeCase` (requires `mrInit` privilege or admin). |
| GraphQL `meritrankInit` | `MeritrankCase.init()` — cold-load MR from `user_trust_edge.prev_sent_weight` via `meritrank_init()`; does not write trust rows. |
| App startup | `UserTrustEdgeCase.cutoverBackfillIfNeeded()` — one-time vote→ledger backfill if `user_trust_source_edge` is empty. |

## Config

### Database policy (`trust_policy` singleton)

| Column | Default (m0122 seed) | Meaning |
|--------|----------------------|---------|
| `half_life_seconds` | `15724800` (182 days) | Evidence decay half-life |
| `epsilon` | `0.1` | Min \|Δw\| before pushing to MeritRank |

SQL functions read this table directly. There is **no** `TRUST_EDGE_HALF_LIFE_DAYS` / `TRUST_EDGE_EPSILON` env override in current server code; changing policy requires a audited migration that updates `trust_policy` and rebuilds effective edges.

### Server env (maintenance sweep only)

| Variable | Default | Meaning |
|----------|---------|---------|
| `TRUST_SWEEP_INTERVAL_HOURS` | `24` | Minimum interval between successful `TrustMaintenanceCase` sweeps |
| `TRUST_SWEEP_RETRY_MINUTES` | `15` | Retry interval after a failed sweep |
| `TRUST_SWEEP_BATCH_SIZE` | `200` | Pairs per `trust_rebuild_effective_batch` call |
| `TRUST_SWEEP_TIME_BUDGET_MINUTES` | `5` | Max wall time per `runDue()` sweep |

## SQL functions

Core trust pipeline: **m0122** (structure), **m0137** (block-aware publish target), **m0144** (`mr_bump_publish_epoch` on successful publish). `trust_edge_weight` remains from **m0088**.

### `trust_apply_source_evidence(context, subject, object, bin, count)`

Inflates the matching bin on `user_trust_source_edge` for one context (VSIDS inflate using `trust_policy.half_life_seconds`). Rejects `legacy`. Called from `TrustEvidenceRepository` after a new ledger row is inserted.

### `trust_rebuild_effective_edge(subject, object, epsilon_override DEFAULT NULL)`

Locks the pair, deflates and sums all source contexts (respecting `trust_context_config.evidence_multiplier`), writes the effective row in `user_trust_edge`, computes `w = trust_edge_weight(...)`, and epsilon-gates `mr_put_edge`. Uses `trust_policy.epsilon` unless `epsilon_override` is set (`-1` forces publish). m0137/m0144: published weight is `0` when the subject blocks the object; successful publish bumps MR epoch (m0144).

### `trust_rebuild_effective_batch(after_subject, after_object, limit, epsilon_override DEFAULT NULL)`

Batched pair iteration for maintenance sweeps. Returns `(last_subject, last_object, processed)`. Called from `TrustMaintenanceCase`.

### `trust_resync_source(subject)` — **one star, admin**

All distinct outgoing objects for `subject` in `user_trust_source_edge`: `trust_rebuild_effective_edge(..., -1)` for each (epsilon bypassed). GraphQL: `trustForceRefreshStar`.

```sql
SELECT trust_resync_source('U…');
-- returns: number of pairs rebuilt
```

### `trust_pair_lock(subject, object)`

Transaction-scoped advisory lock for a subject→object pair (used by apply/rebuild).

### `trust_edge_on_effective_delete()` (trigger)

On `DELETE` from `user_trust_edge` when `prev_sent_weight <> 0`: calls `mr_delete_edge`, tombstones on failure.

### `meritrank_init()` — **cold start seed (read-only on trust table)**

Bulk-loads MeritRank from `user_trust_edge.prev_sent_weight` (plus polling edges). **Does not write** trust rows. After deploy, decay drift is corrected by `TrustMaintenanceCase` sweeps (`trust_rebuild_effective_batch`), not by re-running init.

## When to use which

| Goal | What to run |
|------|-------------|
| Normal evidence (vote / finalized review / forward attribution) | Automatic via app → `TrustEvidenceRepository.record()` |
| Periodic decay → MeritRank | `TrustMaintenanceCase.runDue()` (TaskWorker; `trust_rebuild_effective_batch`) |
| Debug / fix one user's star in MR | `trust_resync_source` or GraphQL `trustForceRefreshStar` |
| Full realign all pairs + MR | GraphQL `trustForceRefreshAll` (`epsilon_override = -1` sweep + tombstone drain) |
| Server cold start | `meritrankInit` / `meritrank_init()` only if MR graph empty |

## Notes

- `user_trust_source_edge.s_*` are **inflated** accumulators with a **fixed** per-row `anchor_at`; effective counts are deflated at rebuild time using that anchor and `trust_policy.half_life_seconds`.
- `user_trust_edge` stores the **projected** deflated sums; its `anchor_at` is set to the rebuild timestamp (not the source anchors).
- Overflow of inflation factors is accepted (~510 years at default half-life); no rescale guard.
- Hasura clients cannot write `vote_user`; votes go through V2 `userSubscribe` / `userUnsubscribe` / `userVote`.
- Subjective help-tag evidence reuses the **source-edge accumulator pattern** in `capability_evidence_edge`; see [`../adr/0012-subjective-help-tag-evidence.md`](../adr/0012-subjective-help-tag-evidence.md).
