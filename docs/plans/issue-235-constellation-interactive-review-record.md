# Issue #235 architecture: review record

Plan: `issue-235-constellation-interactive-architecture.md`. The reviewer is codex CLI `gpt-6.1-sol` (reasoning effort high), running read-only. Claude verifies the reviewer's evidence against the code before applying any change.

## Round 1: rev 3 → rev 4 (2026-10-06)

Verdict: the split into store, outbox, interaction and scene is sound, but rev 3 was "not implementation-ready": revision coverage, cache validity and uncertain-write handling could lose updates or leave stale data.

Evidence spot-checked by Claude, all confirmed:
- `dart:ui` in `constellation_layout.dart:2`;
- `NodeDetails` in `constellation_anchor_composition.dart:2`;
- `ForwardRepository.offerHelp` at C:2268;
- `direct_trust_current_version()` = `SELECT last_value` (`m0193.dart:1617`);
- V2 routing list at `build_client.dart:265-268`.

| # | Sev | Finding | Resolution in rev 4 |
|---|---|---|---|
| 1 | blocker | An ack revision doesn't prove full coverage; a foreign write in between gets lost and its hint suppressed | **Accepted.** `beforeRevision`/`afterRevision`, store-owned `coveredRevision`; uncovered hints (incl. +1) → one resync; hints buffered during in-flight; FULL non-anchor data merged independently (§5.3, R6, F5) |
| 2 | blocker | The version stamp can falsely return `notModified` (non-MVCC sequence, missing dependencies, MR-failure snapshots) | **Accepted, scope changed.** Versioned reads moved out of implementation scope into a deferred design with the reviewer's correctness requirements (§7.4). I6 restated without them. |
| 3 | major | One op and one status per target can't represent queued plus in-flight | **Accepted.** Per-target `inFlight`/`latestPending` slots; status per `clientOpId`; settlement touches only the matching slot (R1) |
| 4 | blocker | Optional dedupe makes retry and Discard unsafe after commit-unknown | **Accepted.** Mandatory server op log in the same tx; `commitUnknown` status; Discard resolves via replay, then conditional compensation with `ifRevision` (R4, R7, R9) |
| 5 | major | R5 deletion ordering undefined; absence isn't deletion evidence | **Accepted.** Refresh never removes local intent; removal only by settlement, Discard or reset (R5) |
| 6 | major | "Flush all", indivisible clusters and the 32 cap conflict | **Accepted.** Bounded batches cut at cluster boundaries; cap 64 and cluster limit 64; envelope validation; per-op reject vs. full rollback on DB error (R2, §7.1) |
| 7 | major | Statement-level NOTIFY ≠ one hint per batch | **Accepted, mechanism chosen.** A deferred constraint trigger emits an identical commit-time payload, which Postgres collapses within the tx; covers mixed ops, absent deletes and cascades (§7.2) |
| 8 | major | A touched-target delta can't maintain support paths | **Accepted, simplified.** v1 returns the complete anchor projection computed in-tx; a compact delta is later and must pass the equality test (§7.1) |
| 9 | major | The freeze gate doesn't stop already-running visual work | **Accepted.** Freeze pauses transitions and invalidates jobs and tickets; all scene widgets read the gated revision; exactly-once release on drop, cancel, lost capture or tab hidden (§5.4) |
| 10 | major | `InteractiveViewer` has no per-pointer enable switch | **Accepted.** Extend the existing selective recognizer into a pointer-aware owner; synchronous transform gating; explicit pointer policies (§5.4, §5.7.1) |
| 11 | major | One step per node can't enforce the hard cap; idle tasks are starved during animation | **Accepted.** Bounded work units (≤ 0.5 ms worst case); deadline checked between units; fixed additive increase; independent wake-up with job token; no native isolate (§5.5, §5.6) |
| 12 | major | The "already pure" claim is false | **Accepted.** Domain geometry records and `LayoutNodeSpec`; UI adapters; Freezed DTOs; injected time, ids and delay (§4.1, §8) |
| 13 | major | Singleton account lifetime under-specified; `offerHelp` missed | **Accepted.** Account-owned cases plus screen leases; generation only on account replacement; `(account, generation)` captured per async step; `ForwardCase.offerHelp` (§4.1, §5.3, R8, F9) |
| 14 | major | Per-node listenables need coherent geometry; edge-cache invalidation | **Accepted.** Stable per-node listenables, coherent revisions, live-edge exclusion, caching only after measurement, existing tickets and tokens kept (§5.7) |
| 15 | major | Wire routing, realtime kind mapping and release gate missing | **Accepted.** `_tenturaDirectOperationNames`, `constellation_field` kind, revision decode, semver + cache-buster + `kDefaultMinClientVersion` together (§4.2, §4.4, §9) |

Claude's own adjustments beyond the findings:
- Versioned reads are deferred, not just hardened.
- The full in-tx projection replaces delta closure in v1.
- Cancel animates the cluster back within the combined transition.
- Tab hidden releases a drag as cancel.

## Round 2: rev 4 → rev 5 (2026-10-06)

Verdict: the layer direction is right, but rev 4 was "not implementation-ready" on uncertain-write compensation, idempotency lifetime, snapshot coherence and notification delivery. D1–D7 need no reversal, and deferring versioned reads and native isolates remains appropriate.

Evidence spot-checked by Claude, all confirmed:
- `withMutatingUser` sets no isolation level (`tentura_db.dart:194`), and `withReadSnapshot` is read-only;
- WS extra validation assumes seen timestamps (`websocket_path_entity_changes.dart:35-46`);
- `postgres_serialization_retry.dart` exists;
- the `AttentionAccountPort` precedent (`attention_case.dart:52-70,194`).

| # | Sev | Finding | Resolution in rev 5 |
|---|---|---|---|
| 1 | blocker | Discard can't compensate DELETE; a replay never proves "not committed" | **Accepted.** Replay returns the recorded result or executes the op. `resultingTargetRevision` on every OK (DELETE too). A per-target watermark table survives deletion. `ifRevision` checked against the watermark under the cursor lock. `preOpConfirmed` captured just before first dispatch. Unsent compensation is cancellable; dispatched compensation settles first (R7) |
| 2 | major | Slot promotion and Retry-after-reject unspecified | **Accepted.** Terminal settlement releases the slot. Retry of a rejection uses a new id; retry of unknown keeps its id. Successor waits for the predecessor; an exhausted unknown blocks only its target (R1) |
| 3 | blocker | 7-day retention breaks idempotency | **Accepted.** Op log retained until account deletion; no purge on the mutation path (R9) |
| 4 | major | Coverage still had delta semantics; projection is parameter-dependent | **Accepted.** The complete projection replaces anchors and advances coverage; `beforeRevision` is diagnostic only. Params-bound projections, with params sent on the mutation. FULL ordered by its own read sequence (§5.3, §7.1, F5) |
| 5 | blocker | In-tx projection isn't one coherent snapshot | **Accepted.** New `withMutatingRepeatableRead` (REPEATABLE READ, READ WRITE, set before the first query); whole-tx retry via `postgres_serialization_retry.dart` (§4.4, §7.1) |
| 6 | major | Deferred NOTIFY needs a canonical envelope and fan-out changes | **Accepted.** Canonical envelope (event always `update`, revision as decimal string), strict publisher, Dart absent-delete notify removed, skip on viewer deletion, per-kind fan-out validation, client keeps the highest revision (§4.4, §7.2) |
| 7 | major | Account ownership is a convention, not a GetIt scope | **Accepted.** Application-lifetime singletons with account-scoped contents via `ConstellationAccountPort`; Injectable-bound clock, id and wake-up ports; logout with zero leases clears everything (§4.1, §8) |
| 8 | major | Freeze must cover queued publication callbacks | **Accepted.** Non-destructive pause that keeps destinations (no reuse of `controller.dart:731`); every queued callback re-checks generation, ticket and freeze; release rebases on frozen displayed geometry (§5.4, §5.7) |
| 9 | major | Blanket camera gating conflicts with allowed wheel zoom | **Accepted.** Camera arbitration by source (gesture / signal / programmatic) owned by the package (§5.4) |
| 10 | major | Synchronous `plan()` outside the budget; `scheduleTask` isn't once-per-frame | **Accepted.** Planning is a phase of one resumable job; frame permit shared by idle and promoted callbacks; composition measured separately (§5.5, §5.6) |
| 11 | major | Visibility invalidation has no producer or recipient algorithm | **Accepted, with a change.** Global payload-free field hint on trust and MR publication; block → both parties. Claude adds non-urgent 30 s spacing plus jitter client-side to avoid synchronized refetch storms (§7.3) |
| 12 | minor | Migration registration and codegen inputs incomplete | **Accepted.** `_migrations.dart` part plus registry, schema refresh before Ferry codegen, explicit sequencing (§4.4, §10) |

## Round 3 (server performance): rev 5 → rev 6 (2026-10-06)

Focus: server performance. Verdict: correctness protocol defensible, but "not performance-ready". Its central risk is coupling expensive projection work to serialized writes while global invalidations generate population-wide reads.

Evidence spot-checked by Claude, all confirmed:
- Drift pool fixed at `maxConnectionCount: 1` per worker isolate (`tentura_db.dart:148`, `env.dart:764`), with workers spawned per isolate (`app/app.dart:50`);
- the serialization helper retries once, immediately (`postgres_serialization_retry.dart:8`);
- per-op `person_visible_peers_symmetric` in authorization (`:42`).

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | blocker | Per-person authorization bypasses the visibility memo; MR calls ≈ (P+1)(1+U) per batch | **Accepted.** Shared tx visibility per (viewer, context); batch-loaded dedupe and watermarks; MR count gate (ARCH §4.4, §7.5; U13) |
| 2 | major | Projection time = cursor-lock time; one DB connection per worker caps throughput | **Accepted.** Prepare-before-lock in the same RR tx; jittered bounded retry plus deadline; admission; don't raise the pool size (ARCH §4.4, §7.6; U11, U13) |
| 3 | major | No safe "position-only" cheap response | **Accepted.** Complete projection retained; the cheap scheme requires §7.4 baselines; cost cut by tx-local reuse (ARCH §7.1) |
| 4 | major | Discoverable readability before LIMIT; double pinned readability; O(V²) trust edges | **Accepted.** Priority list: partial index plus keyset scan, reuse, lean profiles, EXPLAIN-gated trust edges (ARCH §7.5; new U42, U44) |
| 5 | major | Cross-request caching unsafe with current stamps | **Accepted.** Tx-local only now; requirements for later caches (ARCH §7.4) |
| 6 | blocker | Global hints bound timing, not load (≈ 333 FULL/s at 10k sessions) | **Accepted.** Server dirty-generation coalescing, batched broadcast, FULL admission with `RETRY_LATER`, per-(viewer, params) single-flight, load-test release gate (ARCH §7.3; new U43; U26) |
| 7 | major | Op log permanent growth; write amplification ≈ 4B tuples | **Accepted.** Minimal bounded rows, no secondary indexes, measured WAL and bytes, partitioning as escalation (ARCH R9, §7.6; U10, U13) |
| 8 | minor | NOTIFY dedupe doesn't dedupe deferred executions | **Accepted.** Tx-local publication marker → one publisher call per viewer per tx (ARCH §7.2; U15) |
| 9 | major | Acceptance measures client frames only | **Accepted.** Server perf fixtures, recorder, calibrated budgets, gates at U26 and U40 (ARCH §7.6, §9; new U41) |

Claude's addition: budgets are "initial targets, calibrated against the U41 baseline before becoming gates". The owner states the declared active-session population before U26.

## Round 4 (server performance): rev 6 → rev 7 (2026-10-06)

Verdict: round 3's optimisations were sound, but "not yet sufficient for a performance-ready release". Remaining blockers: concurrency amplification, enforceable deadlines, sustained capacity.

Evidence spot-checked by Claude, all confirmed:
- `MERITRANK_RECV_TIMEOUT_MSEC=60000` in both compose files;
- m0222's memo re-checks a `last_value` stamp inside the tx (`m0222.dart:104-119`);
- fan-out is isolate-local (`websocket_path_entity_changes.dart:7`).

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | blocker | Prepare-before-lock under RR → failed, expensive transactions with concurrent writers | **Accepted in part.** Prepare-first stays the default, gated by a contention benchmark (2/4/8 tabs; >1% exhausted or >20% wasted prep → switch to lock-first). Backoff after rollback, outside the connection. **Rejected:** the cross-isolate per-viewer writer queue. Same-viewer concurrency is already bounded by the client outbox (one in-flight request per tab); a cross-isolate queue is disproportionate for multi-tab/device collisions (ARCH §4.4; U11, U13) |
| 2 | blocker | 2 s deadline unenforceable: 60 s MR receive timeout, connector retry, blocking DNS | **Accepted.** New U45 in the `meritrank-rust` connector (absolute deadline, request budget, attempt counter), a precondition for U26; degraded MR ≠ empty visibility, so a retryable error and never a logged rejection (ARCH §4.4, §7.5) |
| 3 | major | m0222 memo invalidated by unrelated trust churn inside an RR tx | **Accepted.** New U46: frozen memo mode for constellation transactions that don't mutate trust (ARCH §7.4) |
| 4 | blocker | FULL-only admission can't protect writes on the single connection | **Accepted.** Worker-wide constellation DB scheduler: write priority, reserved refresh share, fairness, all constellation tx admitted before Drift (ARCH §7.6; U43) |
| 5 | major | Isolate-local single-flight; admission doesn't create capacity (10k sessions ≈ 333 FULL/s vs ≈ 27 tx/s) | **Accepted, owner decision raised.** Single-flight scope declared isolate-local, before admission, duplicate factor counted. Capacity resolved by **D8 (provisional)**: 1,000 declared sessions, global hints lazy with ≤ 5 min staleness, ≈ 3.3 FULL/s. The owner must confirm before U26 (ARCH §0, §7.3) |
| 6 | major | U42 needs an executable keyset contract; a universal 50% gate is unsound | **Accepted.** Keyset contract, predicate reconciliation, gate = candidate-query gain plus a whole-FULL regression limit (ARCH §7.5; U42) |
| 7 | major | Preparation under-specified for new pins and support closure | **Accepted.** Prepared inputs include the upsert targets; closure from trust edges; readability cached per beacon; final re-read (ARCH §4.4; U13) |
| 8 | major | Refresh retry semantics can multiply load or starve freshness | **Accepted.** One pending refresh plus an immutable retry-not-before per params; in-flight satisfies coalesced triggers; jittered unknown-write replay with write priority (ARCH §5.3; U21, U23) |
| 9 | major | Op-log size and HOT budgets not enforced | **Accepted.** Schema-enforced sizes (`varchar(64)`, 32-byte `bytea` digest, result ≤ 256 B); HOT and storage measured; escalation thresholds (ARCH §7.6; U10) |
| 10 | minor | Publication markers don't reduce commit serialization or callbacks | **Accepted.** Concurrent notifying-commit benchmark, slow listeners, event-loop delay (ARCH §7.2; U15) |
| 11 | major | Measurement ownership and release deps | **Accepted.** Measurement rules (admission → encoding latency, actual RPCs, WAL attribution, p95 uncertainty); U42, U44 and U45 → U26 (ARCH §7.6; U41) |

## Measurement run 1 (2026-10-06): effect on review findings

The owner updated local MR (v0.11.1, Nagle fix) and Postgres (postgres-tentura v0.8.2). Results are in `issue-235-constellation-interactive-measurements.md`.

- **Round 3 #1** (per-op MR in authorization): the impact estimate drops from about 5.7 s to about 0.06–0.4 s for a 64-op batch, because an MR RPC now costs 0.02–0.62 ms. **Severity downgraded from blocker to major.** The U13 fix is unchanged.
- **Round 3 #2 and round 4 #4/#5** (single connection per worker): **confirmed empirically.** One worker saturates at ≈ 37 FULL/s and ≈ 150 ANCHORS/s, and further concurrency only adds queueing latency.
- **Round 4 #2** (MR failure deadlines): **unchanged.** The latency fix doesn't bound blackhole or stalled cases; U45 stays a release precondition.
- **Round 3 #4 / U42** (discoverable): the per-call readability cost is 0.25–0.36 ms locally vs ~1 ms on dev. Gate numbers wait for a dev re-measurement.

## Measurement runs 2–3 and owner answers (2026-10-06)

**Owner answers:**
- D8 confirmed;
- commit the docs;
- copy dev data locally and add synthetic data if dev is too small;
- implement and publish the connector deadline now;
- add client ports to `architecture.mdc`;
- re-sync the beads.

**Run 2 (dev copy):** FULL p50 55 ms; one worker saturates at ≈ 22 FULL/s.

**Run 3 (synthetic, V ≈ 1,000):** `mr_mutual_scores` takes 5–7 s, so FULL, ANCHORS and person upsert take ≈ 7 s.
- **New finding, not raised by any review round:** the MR score computation itself dominates at dense reach.
- **Resolution:** ARCH §7.4a promotes the cross-request visible-set cache to required (new U48), plus new external U47 for MR.
- **Round 4 #2:** connector deadline shipped (pgmer2 0.8.3, upstream #89). U45 becomes adoption.
