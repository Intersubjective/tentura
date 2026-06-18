# User→user trust edges (Dirichlet / VSIDS)

User→user MeritRank weights are derived from a 5-bin Dirichlet model stored in
`user_trust_edge`. Evidence (votes, finalized reviews) inflates accumulators
`s_*` against a fixed per-edge `anchor_at`; decay is applied lazily (VSIDS-style:
inflate the bump, not the whole star).

**Math lives in SQL only** (`trust_edge_weight`). Dart passes bin keys, evidence
magnitude, and config from `Env`.

## Config (server env)

| Variable | Default | Meaning |
|----------|---------|---------|
| `TRUST_EDGE_HALF_LIFE_DAYS` | `182` | Half-life for evidence decay |
| `TRUST_EDGE_EPSILON` | `0.1` | Min \|Δw\| before pushing to MeritRank |

Half-life in seconds for SQL: `182 * 24 * 60 * 60` → **`15724800`**.

## SQL functions

All defined in migration `m0088` (mirrored in `sql/triggers.sql`).

### `trust_apply_evidence(subject, object, bin, count, half_life_seconds, epsilon)`

Single-edge update (votes, reviews). Inflates bump, epsilon-gates, calls
`mr_put_edge` in-process, updates `prev_sent_weight`. Called from the Dart
junction on every evidence event.

### `meritrank_sweep(half_life_seconds, epsilon)` — **scheduled decay drift**

Proactive maintenance: for each edge, recompute decayed `w`; if
`|w - prev_sent_weight| > epsilon`, push to MeritRank and update
`prev_sent_weight`. Does **not** change `anchor_at` or `s_*`.

**Usage:** schedule periodically (cron / pg_cron). Not run on server startup.

```sql
SELECT meritrank_sweep(15724800, 0.1);
-- returns: number of edges pushed
```

### `trust_resync_source(subject, half_life_seconds)` — **one star, admin**

All outgoing edges of one user: recompute `w`, **push every edge** (epsilon
bypassed), update `prev_sent_weight`. GraphQL: `trustForceRefreshStar`.

```sql
SELECT trust_resync_source('U…', 15724800);
```

### `trust_recompute_all(half_life_seconds)` — **full DB refresh (step 1 of 3)**

All edges: recompute decayed `w` and write **`prev_sent_weight` only**. No
`mr_put_edge`. Does not touch `s_*` or `anchor_at`.

**Usage:** admin full reload — always followed by MeritRank reset + init (see
below). GraphQL: `trustForceRefreshAll` runs all three steps.

```sql
SELECT trust_recompute_all(15724800);
-- returns: number of rows updated
```

Then reload MeritRank:

```sql
SELECT mr_reset();
SELECT meritrank_init();
```

Or use the V2 mutation `trustForceRefreshAll` (requires `mrInit` privilege).

### `meritrank_init()` — **cold start seed (read-only on trust table)**

Bulk-loads MeritRank from `user_trust_edge.prev_sent_weight` (plus polling
edges). **Does not write** trust rows. After deploy, decay drift is corrected by
`meritrank_sweep`, not by init.

## When to use which

| Goal | What to run |
|------|-------------|
| Normal evidence (vote / review) | Automatic via app → `trust_apply_evidence` |
| Periodic decay → MeritRank | `meritrank_sweep(H, ε)` on a schedule |
| Debug / fix one user's star in MR | `trust_resync_source` or GraphQL `trustForceRefreshStar` |
| Full realign DB + MR graph | `trust_recompute_all` → `mr_reset` → `meritrank_init` or GraphQL `trustForceRefreshAll` |
| Server cold start | `meritrank_init()` only if MR graph empty (app startup) |

## Notes

- `user_trust_edge.s_*` are **inflated** accumulators; effective counts are
  deflated at read time using `anchor_at`.
- Overflow of inflation factors is accepted (~510 years at default half-life);
  no rescale guard.
- Hasura clients cannot write `vote_user`; votes go through V2
  `userSubscribe` / `userUnsubscribe` / `userVote`.
