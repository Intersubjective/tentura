---
status: resolved
kind: performance-gate
source: docs/plans/constellation-implementation-plan.md § UNIT 02 (GATE-14.1, architecture §14.1)
---

# GATE-14.1 — read-wall discoverability performance decision

**`GATE-14.1: resolved (b)` — a cache is required.** Decided by **V.G. Bulavintsev**
(plan owner), applying the budget and decision rule fixed before measurement (below)
mechanically to the numbers this document records. UNIT 05 (the read-wall
discoverability clause, m0162) may proceed once the new inserted unit — **UNIT 04a**,
described at the end of this document — lands, per plan §2 rule 6.

## Budget (fixed before measurement)

No query's p95 latency may increase by more than **+150ms** relative to its own
current (pre-m0162) p95. This number was fixed by the plan owner in
`constellation-implementation-plan.md` §0.2/UNIT 02 before any measurement was
taken, specifically so the decision could not be renegotiated against
whatever numbers came back.

## Fixture

Disposable, migrated Postgres database (never the shared `postgres` database),
built and torn down per run by `packages/server/tool/constellation_read_wall_benchmark.dart`
(run via `scripts/constellation_read_wall_benchmark.sh`):

- 5,000 users, plus one distinguished viewer (`Uconstviewer`).
- A `vote_user` graph with mean out-degree ~4 (each user trusts the next 4 users
  in an id ring), bulk-inserted via `generate_series` — no per-row loops.
- The viewer holds 200 reciprocal explicit-trust edges (`vote_user` both
  directions), giving a symmetric peer set (`V`) of exactly 200.
- A MeritRank publish covering the graph, via **`SELECT public.meritrank_init()`**
  (the same bulk-load function every real migration uses —
  `packages/server/lib/data/database/migration/m0061.dart` and similarly
  m0010/m0011/m0013/m0044/m0053/m0062 — which aggregates `vote_user` into arrays
  and calls `mr_bulk_load_edges(...)` once) followed by
  `mr_bump_publish_epoch()`. This took **2ms** for the full ~20.4k-edge graph.
  (A first draft of this benchmark instead looped `mr_put_edge(...)` once per
  sampled row directly against the live MeritRank service; that consumed a full
  hour with no result before being abandoned — see the journal's "UNIT 02
  attempt 1" incident note. `meritrank_init()` is the correct, fast, real path.)
- 50,000 published, active beacons (`status ∈ {0,7,8}`, `published_at` set),
  spread round-robin across the 5,000 authors.
- Ad-hoc supporting rows for the six representative queries below (500 inbox
  rows, 50 forward-edge rows, 200 attention-outbox rows, 100 image rows).

The four frozen migration bodies (§0.1 of the implementation plan) were applied,
**as ad-hoc SQL against this fixture only** — never registered in
`_migrations.dart` — in the required order: m0160 (DDL) → m0161 (symmetric
predicate) → m0162 (the new `beacon_can_read_content` branch) → m0163
(`constellation_trust_edges`). `ANALYZE` was run both before and after.

## Methodology note: bounded probes

Every measured query is capped at an **8000ms `statement_timeout`**. A single
probe sample is taken first; if it returns in ≤1500ms, the query gets the full
2-warmup + 10-timed-run treatment for a real p50/p95. If the probe exceeds
1500ms, or times out at 8000ms, **no further repeats are run** — the single
sample (or the 8000ms cap, for a timeout) is reported as both p50 and p95, with
`single_sample_reason` recorded. This is not a methodology weakness: repeating
an already-multi-second query ten more times would not sharpen the
answer to "does this blow a 150ms budget," it would only cost ten times the
wall-clock for the same answer. Every number below reported as an 8000ms cap
means **the true latency is `>= 8000ms`, not `== 8000ms`** — the cap is a floor
on how bad it is, not a measurement of how bad it is.

(Earlier in this gate's investigation, the benchmark ran *without* this cap and
a single execution of the post-m0162 `hasura_beacon_row_filter` query was
manually observed still running after **16 minutes 42 seconds** with no sign of
finishing, before being cancelled. That data point is not in the table below —
it predates the bounded-probe fix — but it is the reason the fix exists, and it
independently confirms the finding below is not a benchmark artifact.)

## Measurements

p95 latency, before vs after applying m0162 (the discoverability branch), for
six representative surfaces:

| Query | p95 before (ms) | p95 after (ms) | Δp95 (ms) | Within +150ms budget? |
|---|---:|---:|---:|:---:|
| `hasura_beacon_row_filter` (Hasura `beacon` row filter, incl. denied rows) | 2,776.6 | **8,000.0 (capped; ≥8s)** | +5,223.4 | **No** |
| `my_work_authored_list` | 0.9 | 1.1 | +0.2 | Yes |
| `inbox_list` | 2,761.6 | **8,000.0 (capped; ≥8s)** | +5,238.4 | **No** |
| `profile_shared_forwarded` | 2,713.0 | **8,000.0 (capped; ≥8s)** | +5,287.0 | **No** |
| `attention_intent_batch` | 21.9 | **8,000.0 (capped; ≥8s)** | +7,978.1 | **No** |
| `beacon_image_metadata` | 2,905.4 | 16.8 | −2,888.6 | Yes (see caveat) |

**4 of 6 representative queries blow the budget by more than 30×, not
marginally.** This is decisive: the post-m0162 read wall is not "a little
slower," it is unusable at this row count without help.

**Caveat on `beacon_image_metadata`'s apparent improvement.** Its "before"
sample (2,905ms) was very likely a **cold-cache first-touch artifact** — it was
the first query executed against a freshly seeded, freshly `ANALYZE`d 50k-row
table in that run, and the single-sample fast-path (this document's
methodology section) reports whichever single number it draws when a query is
slow, cold-cache or not. Its "after" sample (16.8ms) benefited from every page
it touches already being warm from prior queries in the same run. This is
**not evidence that m0162 made this query faster** — it is evidence that this
benchmark's single-sample fallback cannot distinguish "genuinely slow
predicate" from "cold cache," and a future re-run of this benchmark (e.g. to
validate the eventual cache) should warm the relevant tables before the
"before" phase, or run multiple cold-started trials, to avoid this same
ambiguity. It does not change the decision — the four queries above are
capped at the *maximum* the harness will wait, which cold cache cannot
explain away.

**Short-circuit hit-rate could not be measured — itself confirmatory.** The
query designed to measure what fraction of discoverable authors are covered
by the cheap `person_reciprocal_explicit_trust` short-circuit
(`COUNT(DISTINCT author) ... WHERE person_are_mutually_visible(viewer, author, '')`
over ~5,000 distinct authors) **itself timed out at the 8000ms cap.** This is
additional, independent confirmation of the same root cause: evaluating the
new predicate at scale is expensive regardless of which query shape triggers
it.

**Constellation's own field queries are fine in isolation** (small, `V`-bounded
inputs, not full-table scans):

| Query | p50 (ms) | p95 (ms) | rows examined |
|---|---:|---:|---:|
| `person_visible_peers_symmetric(viewer, '')` | 86.8 | 90.2 | 3,411 |
| `constellation_trust_edges(viewer, '', {ego}∪V)` | 91.0 | 99.5 | 9,197 |
| Full composed `constellationField` (peers→edges→own requests→discoverable requests→profiles) | — | **8,000.0 (capped; ≥8s)** | — |

The composed field call is capped for the same reason as the four failing
surfaces above: its "discoverable requests" step re-runs
`beacon_can_read_content` over the peer-authored candidate set, which still
hits the expensive branch. **This is the number UNIT 07 must re-measure against
its real registered endpoint, post-cache** — it is not acceptable as-is.

## Root cause

`beacon_can_read_content`'s new branch (m0162) calls
`public.person_are_mutually_visible(p_viewer_id, b.user_id, '')` once per
candidate beacon row. That function's non-short-circuit path calls
`person_is_mutually_visible`, which is defined (m0140) as:

```sql
SELECT p.is_mutually_visible FROM person_visibility_peers(viewer_id, ctx) p
WHERE p.peer_id = peer_id
```

**This recomputes the viewer's *entire* peer set from scratch on every call** —
it is not memoized across the calls made by a single outer query, because each
invocation is a fresh call to a set-returning function with no per-query
caching. Evaluated once per beacon row (up to 50,000 times for a full-table
Hasura scan, or ~5,000 times for the per-distinct-author short-circuit
measurement), the multiplicative cost the implementation plan's §0.1
commentary warns about for `constellation_trust_edges` (`C · P(viewer)`, avoided
there specifically by computing `V` once via
`person_visible_peers_symmetric`) is exactly what m0162 pays per row, because
`beacon_can_read_content` has no equivalent single-computation seam — it is a
per-row scalar predicate, not a set-returning query joined against a
precomputed candidate list.

**Additionally, `person_visibility_peers` is backed by a live call to the
MeritRank service**, not a plain local table read. (An earlier draft of this
document's benchmark tool assumed the opposite, based on `mr_mutual_scores`
looking like an ordinary table — that assumption was **wrong** and is corrected
here.) The fixture uses `CREATE EXTENSION pgmer2`, whose functions communicate
with the `meritrank` container over the network; stopping that container
produces a genuine connection/DNS-resolution failure
(`Severity.error 22000: failed to lookup address information: Try again`),
observed on exactly the same four queries that hit the expensive branch when
MeritRank was live. So the multiplicative cost above is not "extra CPU on the
Postgres box" — a meaningful share of it is real network round-trips to an
external service, once per beacon row.

## MeritRank-unavailable behavior — the critical finding for the cache spec

With the `meritrank` container stopped, the same four queries that are slow
when MeritRank is up (`hasura_beacon_row_filter`, `inbox_list`,
`profile_shared_forwarded`, `attention_intent_batch`) **fail with a raw
connectivity error** (`failed to lookup address information: Try again`)
rather than returning empty, denying gracefully, or hanging silently. The two
queries that never reach the expensive branch for their fixture rows
(`my_work_authored_list`, scoped to the viewer's own beacons; `beacon_image_metadata`,
scoped to a small candidate set) succeed normally, confirming the failure is
specific to the discoverability branch, not a blanket outage of the connection.

**This is neither "fail open" nor "fail closed" today — it is "fail loud,"
an unhandled exception that would surface as a raw error to callers of every
affected surface** (My Work list's *authored* branch is unaffected, but Inbox,
profile shared-request lists, and the attention/notification batch all break)
whenever the MeritRank service is unreachable. Whatever implements UNIT 04a
below **must** catch this specific failure mode and convert it into an
explicit deny for the discoverability grant — not merely "the cache happens to
serve a stale allow," and not "let the exception propagate as it does today."

(One exploratory single-row sample, `discoverability_branch_sample`, returned
`allowed: true` while MeritRank was stopped — this does **not** contradict the
above. The sampled beacon's author happens to be one of the viewer's 200
reciprocal explicit-trust peers by fixture construction, so it was answered
entirely by the `person_reciprocal_explicit_trust` short-circuit, which only
touches `vote_user` and never reaches MeritRank at all. It tested the wrong
case by accident; the four timed-out bulk queries are the real signal for this
question.)

## Decision

**(b) Cache**, per the pre-fixed rule: any measured query exceeding the +150ms
budget forces this outcome, and four of six did — by more than an order of
magnitude, not marginally. `GATE-14.1: resolved (b)`, decided by
**V.G. Bulavintsev**.

## Cache specification (required before UNIT 05 may start — implemented in the new UNIT 04a)

Per plan §0.1/UNIT 02 step 4(b), this specification covers freshness/expiry,
invalidation, rebuild concurrency, MeritRank-unavailable behavior, and
`block_hides`'s placement, and is binding on UNIT 04a's implementation:

**What is cached.** The result of
`person_are_mutually_visible(a_id, b_id, ctx)` — a boolean — keyed on the
**unordered** pair `{a_id, b_id}` plus `ctx` (the function is symmetric by
construction, so `(a,b)` and `(b,a)` share one entry; normalize the key by
sorting the two ids before lookup/store). This is the one call site m0162
evaluates per row; caching at this granularity fixes the actual hot path
without touching `person_visibility_peers`'s broader semantics.

**What is never cached.** `block_hides(...)` stays **outside** the cache and is
always evaluated live, exactly as `beacon_can_read_content`'s existing branches
already require (`block_hides` is the very first `CASE` branch, ahead of
everything). A block must take effect immediately; caching it would let a
freshly-blocked user's content stay visible for up to the cache's TTL.

**Freshness / expiry.** Each cache entry carries a bounded TTL (**60 seconds**
is a reasonable starting value — short enough that a stale positive cannot
outlive a block-adjacent safety expectation by more than a minute, long enough
that the 50k-row scan pattern above amortizes the cost across many rows
sharing few distinct viewer-author pairs within that window) **in addition to**
the two invalidators below — the TTL is a safety net for drift the invalidators
don't cover (e.g. clock skew, missed invalidation events), not the primary
freshness mechanism.

**Two invalidators, both required (§0.1/UNIT 02 explicitly asks for two,
because they cover different write paths):**

1. **The MeritRank publish epoch** (`mr_bump_publish_epoch()`, m0144). Every
   cache entry stores the epoch value at write time; a lookup whose stored
   epoch is behind the current epoch is treated as a miss. This covers every
   change that flows through an MR publish (the `forward_mr`/`reverse_mr`
   component of `person_is_mutually_visible`).
2. **A direct-trust version counter.** `person_reciprocal_explicit_trust`
   reads `vote_user` directly and is **not** gated by an MR publish — a user
   can add or withdraw an explicit-trust vote at any time with no MR publish
   in between, and a cached "mutually visible" result from before that change
   would outlive its justification (this is the exact risk the frozen SQL
   comment in plan §0.1 calls out — "explicit-trust membership can change with
   no epoch bump and a cached positive would outlive its justification"). This
   needs a new counter — e.g. a sequence bumped by an `AFTER INSERT OR UPDATE
   OR DELETE` trigger on `vote_user` — stored alongside the MR epoch in each
   entry, checked the same way.

A cache entry is valid only when **both** stored values still match current;
either one being stale is a miss, not a partial hit.

**Rebuild concurrency.** A miss triggers a synchronous rebuild (the same
`person_are_mutually_visible` call this replaces, just once, on a cache miss
rather than once per row) with **single-flight de-duplication per key** — a
second caller missing on the same `{a,b,ctx}` key while a rebuild is already
in flight awaits that rebuild's result rather than issuing a second redundant
call. Do not use a background/async refresh-ahead scheme for this predicate:
it is an access-control decision, and serving a possibly-stale cached value
while silently kicking off a refresh in the background is exactly the kind of
implicit fail-open risk this cache exists to avoid, not introduce.

**MeritRank unavailable — fail CLOSED, always.** If a rebuild's underlying
`person_are_mutually_visible` call raises (the connectivity failure this
document observed, or any other error), the cache must **not** cache a
positive result, must **not** propagate the raw exception up through
`beacon_can_read_content`'s discoverability branch, and must **not** serve a
previously-cached positive past its TTL/epoch validity to paper over the
outage. The discoverability grant resolves to **false** for that pair for the
duration of the outage. This is a deliberate product tradeoff (an author's
own read-wall grants — author/forward/participant/help-offer — are entirely
unaffected, since those branches never reach this cache; only the
*discoverability-only* grant degrades) and is the only choice consistent with
"never fail open on an access-control predicate."

**Where it lives.** This is a per-request-pair cache with a natural fit in
Postgres itself (a table keyed on the normalized pair, checked/refreshed
inside `person_are_mutually_visible` or a wrapping function `beacon_can_read_content`
calls instead) rather than in the Dart server process, because the call site
that needs it (`beacon_can_read_content`) is itself `LANGUAGE sql` and
evaluated entirely inside Postgres per row — an application-layer cache would
require restructuring that call site to go through Dart first, which is a much
larger change than this gate's finding calls for. UNIT 04a's implementer
should treat "cache table + wrapping function, called from the m0162 branch
in place of today's direct `person_are_mutually_visible` call" as the default
shape, and depart from it only with a documented reason.

## Manifest change

A new unit, **UNIT 04a — "Discoverability visibility cache"**, is inserted
between UNIT 04 and UNIT 05 in the plan's §3 manifest (implements this cache
spec) and in the journal's unit checklist. UNIT 05's dependency list gains
`04a`. UNIT 04a is not folded into UNIT 05, per plan §0.1's instruction.
