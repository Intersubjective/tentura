# Issue #235: server measurements (local stack)

## Run 1: 2026-10-06, after the owner updated local MeritRank and Postgres

### Environment

| Component | Value |
|---|---|
| Postgres | `vbulavintsev/postgres-tentura:v0.8.2` (PostgreSQL 17.11, extension `pgmer2` 0.8.2); schema at m0222 |
| MeritRank | `vbulavintsev/meritrank-service:v0.11.1`, which contains `meritrank-rust` 3489378 "rpc: one write per frame + TCP_NODELAY (fix ~88 ms stall per call)" |
| Server | `scripts/run-server-local.sh`, **`DEBUG_MODE=true`**: a **single web worker**, JIT (`dart run`), not AOT. Absolute numbers are pessimistic vs a release build; ratios and saturation behaviour still hold. |
| Data | 3,144 users, 1,674 beacons, 297 anchors, 3,253 trust edges |

The local trust graph is **sparse**: the largest visible set is **V = 6**, and the largest discoverable candidate set for a QA-loginable viewer is **C = 30**. On dev, #233 reports C ≈ 192–225 for the heaviest viewer. Local numbers therefore **cannot** validate dev-scale or worst-case budgets; they validate per-unit costs and the concurrency model.

**Setup note.** The freshly recreated MR container had an empty graph (`Node not found` for every viewer). `SELECT meritrank_init()` was run once, which is exactly what server startup does in `App._uploadGraph` when `mr_edgelist()` is empty; it loaded 3,253 edges. Without this step every MR-dependent number is meaningless.

### Per-unit SQL costs

Each viewer was measured in its own transaction, in two runs; the range spans both.

| Measure | Result | Before (source) |
|---|---|---|
| `mr_mutual_scores` per RPC | **0.03–0.62 ms** | ~88 ms stall per call (#231) |
| `mr_node_score` per RPC | **0.02–0.05 ms** | ~88 ms (#231) |
| `person_visible_peers_symmetric` (V ≤ 6) | 0.8–6.4 ms | — |
| `constellation_trust_edges` (E ≤ 10) | 1.8–5.6 ms | 27 ms on dev (#233) |
| `beacon_can_read_content` per call (200 calls per viewer) | **0.25–0.36 ms** | ~1 ms on dev (#233) |

### End-to-end GraphQL (V2 direct, 20 runs after warm-up)

| Viewer | Op | p50 | p95 |
|---|---|---|---|
| `U4551ffecd7eb` (V = 5, 1 request) | FULL | 30.5 ms | 54.7 ms |
|  | ANCHORS | 7.9 ms | 16.4 ms |
|  | upsert (person) | 9.5 ms | 28.3 ms |
| `Ufb5ceb101001` (C = 30, 8 requests) | FULL | 29.8 ms | 46.4 ms |
|  | ANCHORS | 6.3 ms | 9.9 ms |

FULL's minimum is about 24 ms regardless of C (1 vs 30). At this scale FULL is dominated by fixed per-request work (query count, profile lookups, JIT), not by discoverable readability. The test anchor written by the upsert run was deleted afterwards (verified: 0 rows left).

### Throughput (one worker, viewer `Ufb5ceb101001`)

| Op | Concurrency | Throughput | p50 | p95 |
|---|---|---|---|---|
| FULL | 1 | 32.5 req/s | 26.7 ms | 49.5 ms |
|  | 8 | 35.7 req/s | 208 ms | 272 ms |
|  | 32 | 38.1 req/s | 820 ms | 974 ms |
| ANCHORS | 1 | 135 req/s | 6.3 ms | 11.6 ms |
|  | 8 | 145 req/s | 46 ms | 79 ms |
|  | 32 | 153 req/s | 200 ms | 247 ms |

**Reading.** Throughput saturates at about 1 / (service time) as soon as there is any concurrency. Extra concurrency only adds queueing latency (p50 grows linearly with the queue). This empirically confirms ARCH §7.6's single-connection-per-worker model.

### Consequences for the plan

1. **The #231 latency is fixed locally.** An MR RPC is now sub-millisecond. Round 3's "65 calls × 88 ms ≈ 5.7 s" for a 64-op person batch becomes about 64 × (1–6 ms) ≈ **0.06–0.4 s** of per-op `person_visible_peers_symmetric`. The shared-memo fix (U13) stays worthwhile but is **major, not a blocker**.
2. **MR failure bounds are still open.** A fast happy path doesn't bound blackhole or stalled cases: the 60 s receive timeout and the connector retry are unchanged. **U45 stays a release precondition.**
3. **Readability per call is about 3–4× cheaper locally than the dev figure** (0.25–0.36 vs ~1 ms). That could be hardware, data shape, or the v0.8.2 image. **Re-measure on dev**, which now has `pg_stat_statements` + `auto_explain`, before setting U42's gate numbers.
4. **Capacity.** One worker serves about 37 FULL/s or about 150 ANCHORS/s at this graph size (JIT, debug). Under D8 (1,000 sessions, lazy ≤ 5 min → about 3.3 FULL/s) a single worker has more than 10× headroom at local scale. Eager 30 s refresh (about 33 FULL/s) would already saturate one worker, which supports D8's lazy policy.
5. **Local fixtures are too small.** U41 must generate dense fixtures (V up to 1,000, C up to 10k) synthetically, or via `scripts/seed_society` with denser trust. The real-data baseline must come from **dev**.

### Raw artifacts

These were in the session scratchpad, which is not committed: `bench.sql`, `gqlbench.py`, `load.py` and the run outputs. U41 turns them into the committed perf suite.

## Run 2: 2026-10-06, a copy of dev data

**Data.** `pg_dump` of dev (`root@dev.tentura.io`, 23 MB: 328 users, 236 beacons, 613 trust edges, 74 anchors, schema m0222) restored into a **separate local database `tentura_devcopy`**. The local `postgres` database and its QA fixtures are untouched.

**Setup.**
- MR was reloaded from the copy (`mr_reset(); meritrank_init()`: 675 edges).
- The local MR runs with the repo defaults (`MERITRANK_ALPHA=0.85`, `NUM_WALKS=1000`). Dev runs alpha 0.15 / 10,000 walks, so visible sets differ from what dev users see.
- The server was started against the copy with `scripts/perf/run_server_db.sh tentura_devcopy` (same `.env`, `DEBUG_MODE=true`, one worker). `RESEND_API_KEY` is unset and FCM is mocked, so no mail or push can reach real users.
- To log in, the heaviest viewer `U66728b9dba8d` got a QA credential `perf-heavy@test.tentura.local` **in the copy only**.

**Heaviest viewer:** V = 76, C = 61, payload 39 KB (76 peers, 36 requests, 204 edges).

| Measure | Result |
|---|---|
| `mr_mutual_scores` per RPC | 0.18–0.29 ms |
| visibility (V = 75–81) | 1.1–4.0 ms |
| trust edges (E ≈ 200) | 5.1–7.1 ms |
| `beacon_can_read_content` per call | 0.25–0.30 ms |
| FULL | p50 54.5 ms / p95 87.5 ms |
| ANCHORS | p50 9.8 / p95 14.2 ms |
| upsert | p50 12.5 / p95 17.0 ms |
| One-worker saturation | FULL ≈ **22 req/s** (p50 1.45 s at concurrency 32); ANCHORS ≈ **120 req/s** |

## Run 3: 2026-10-06, synthetic dense data (`tentura_perfsynth`)

**Data.** `tentura_perfsynth` is cloned from `tentura_devcopy` and extended by `scripts/perf/constellation_synth.sql` (deterministic):
- 3,000 synthetic users in 3 clusters of 1,000;
- about 30 reciprocal trust edges per user inside the cluster, about 88.8k synthetic edges in total;
- the heavy viewer joined to cluster 0 with 50 reciprocal edges;
- 14,000 discoverable Requests cloned from a readable dev Request.

MR was reloaded: 89,475 edges. The heavy viewer then has **V = 1,011, C = 9,940**, which is the plan's dense target.

| Measure | Result |
|---|---|
| `mr_mutual_scores` (~1,000 mutual peers), repeated, warm | **5.1–6.8 s per call** |
| `mr_scores` (998 rows) | 5.5 s |
| `mr_node_score` | 0.4 s |
| `mr_neighbors` | 0.24 s |
| FULL (n = 5) | p50 **7.2 s** |
| ANCHORS | p50 **6.8 s** |
| upsert (person) | p50 **6.7 s** |
| delete (no visibility check) | 10 ms |

MR sits at about 100% CPU during a call.

**Reading.** At V ≈ 1,000, a single MR mutual-scores computation costs more than 5 s, and every visibility-dependent operation (FULL, ANCHORS, person upsert authorization) pays it once. That is two orders of magnitude over the ARCH §7.6 budgets. The cost is in the **MeritRank service's score computation**, not the RPC, the connector or Postgres. The synthetic graph (random, roughly 30-regular clusters, an expander) is likely a pessimistic shape, because walks reach every node of the cluster. Still, "a viewer with about 1,000 visible peers" is exactly the plan's dense case.

**Consequences:**
1. Server-side caching of the visible set, deferred in ARCH §7.4, is no longer optional at this density. The transaction-local memo already removes per-op repeats (round 3 #1), but a FULL that runs every few minutes per viewer still costs about 6 s of MR CPU, serialized per MR instance.
2. MeritRank needs its own investigation: score-computation profile at about 1,000-node reach, `NUM_WALKS`/alpha sensitivity, and incremental or cached mutual scores per publish epoch. This is a new external unit (U47).
3. The local copies stay available: `tentura_devcopy` and `tentura_perfsynth`. **MR holds one graph at a time:** after a run against a copy, reload the `postgres` database's graph (`SELECT mr_reset(); SELECT meritrank_init();` in db `postgres`). This was done at the end of run 3.

## Connector deadline (U45), implemented upstream

`Intersubjective/meritrank-rust` PR #89, merged as `2e8f4f0a0`: pgmer2 **0.8.3**, which publishes `vbulavintsev/postgres-tentura:v0.8.3`.
- One absolute per-call deadline covering DNS, connect, write, full read and the retry.
- Waits in ≤ 50 ms slices with `CHECK_FOR_INTERRUPTS`, so `statement_timeout` / cancel can bound a statement or a transaction.
- `mr_rpc_attempts()` for counting real round trips.
- Tests: 15 unit tests (fake peers: blackhole, trickle, stalled write, unreachable, reuse, recovery) plus the pgrx suite; CI 7/7 green.

**Housekeeping.** Before this PR, the fork `ichorid/meritrank-rust` `main` lagged the upstream `main` (it lacked the #88 merge); it was fast-forwarded to `289f939`. Upstream had not been reverted.

## Run 4: 2026-10-06, `mr_mutual_scores` and the walks cache

**Question (owner).** First calls are slow while the graph warms up. Each mutual-scores call needs the reverse scores in every peer's frame, and frames are evicted, but caching exists. After warm-up, are reverse scores served from cache?

**Answer: no, not when one read's working set exceeds `MERITRANK_WALKS_CACHE_SIZE`.**

- **Configuration.** Local `compose.dev.yaml:92`, `compose.prod.yaml:120` and the dev host all set **`MERITRANK_WALKS_CACHE_SIZE=200`**. Dev additionally runs `NUM_WALKS=10000`.
- **Over-capacity path.** `state_manager.rs` `ego_read` reads in two passes: it records the peer frames the first pass touched, pins them and reads again. When the peers exceed the capacity, it pins them **in portions of `capacity`**, and the portions evict one another, so **every such read recalculates the frames**. The service logs this sparsely; seen locally: `A read needs 1018 peer frames but MERITRANK_WALKS_CACHE_SIZE is 200: frames are recalculated on every such read`.
- **No reverse-score cache.** The service consistency rework removed the old score cache on purpose (`SERVICE_CONSISTENCY_PLAN.md` §2.7: it served stale reverse scores or 0). `MERITRANK_SCORES_CACHE_SIZE`/`_TIMEOUT` are ignored with a start-up warning. Only `cached_score_clusters` remains: per copy, keyed by `(ego, kind, gen, zero_rev)`, and it works (`mr_node_score` 402 → 56 ms on repeat).

**Experiment.** On `tentura_perfsynth` (rebuilt from a fresh dev dump, because the earlier copy had been pruned by the server's trust jobs), the heavy viewer has about 1,019 mutual peers. The local MR container was recreated with only `MERITRANK_WALKS_CACHE_SIZE` changed, and restored to 200 afterwards.

| Walks cache | Cold call | Warm repeats (×5) | Other cluster egos | MR memory |
|---|---|---|---|---|
| **200** (current) | 4.9 s | **5.6–6.1 s** (no gain) | 5.7–6.0 s | 314 MiB |
| **1,200** | 2.4 s | **47–58 ms** | 2.0 s first, then 81–85 ms | 681 MiB |
| **0** (unlimited) | 2.4 s | **50–61 ms** | 1.95 s first, then 70–75 ms | 680 MiB |

End-to-end on the same data with cache 1,200 (server via `scripts/perf/run_server_db.sh`, `constellation_gql_bench.py --base http://127.0.0.1:2080`, n = 10):

| Operation | p50 | p95 | At cache 200 |
|---|---|---|---|
| FULL | **154 ms** | 163 ms | 7.2 s |
| ANCHORS | **18 ms** | 20 ms | 6.8 s |
| person upsert | **47 ms** | 59 ms | 6.7 s |

**Conclusions:**
1. The dense-scale slowness in run 3 was **walks-cache thrash**, not intrinsic MR cost. Sizing the cache to cover one read's working set (largest visible set + 1, here ≥ 1,020) gives about a 100× speed-up after warm-up, and FULL at V ≈ 1,000 then fits the ARCH §7.6 budget.
2. **The cold cost remains:** about 2–2.4 s for the first read of a new ego (its frame plus the peer frames not yet resident). It recurs after an MR restart (the graph reloads empty) and for frames whose walks a write dirtied.
3. **Memory is the trade-off.** Here (NUM_WALKS = 1000) about 1,000 extra resident frames cost about 370 MiB. `LOAD_TEST_ANALYSIS.md` puts a frame at about 1 MB at 10k walks (dev's setting), so 1,000 frames ≈ 1 GB (more if both buffer copies hold walks; to verify). The cache size is a memory budget decision per host.
4. **MR improvement, if eviction must stay below the working set:** a *generation-checked* reverse-score cache keyed `(peer, ego, gen[peer], zero_rev)`, the same key discipline as `cached_score_clusters`. It would let reverse scores survive frame eviction without the staleness that got the old cache removed. Only frames whose generation changed would need recalculation.

**Housekeeping.** The local MR is back at `WALKS_CACHE_SIZE=200` with the `postgres` graph loaded. `tentura_perfsynth` was rebuilt and is intact again (88.8k synthetic edges). Running the Tentura server against it for minutes lets the trust jobs prune synthetic edges that have no `trust_evidence`; keep server runs short, or rebuild the DB.
