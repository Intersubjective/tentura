---
status: review-record
kind: adversarial-review
subject: docs/plans/constellation-edge-semantics.md, docs/plans/constellation-implementation-plan.md
date: 2026-09-08
---

# Constellation — review and revision history

The single audit trail for both Constellation documents. Neither normative
document carries its own history any more:
[`constellation-edge-semantics.md`](constellation-edge-semantics.md)
(architecture) and
[`constellation-implementation-plan.md`](constellation-implementation-plan.md)
(execution) state only what is currently true. Everything about how they got
there is here.

| Part | Artifact reviewed | Round | Date |
|---|---|---|---|
| **A** | architecture (`constellation-edge-semantics.md`) | first review, R1–R16 | 2026-09-07 |
| **B** | implementation plan (`constellation-implementation-plan.md`) | adversarial review, 12 findings | 2026-09-08 |
| **C** | implementation plan | revision history, revisions 2–10 | 2026-09-08 |

Nothing here is normative. Where a finding was resolved by a decision, the
decision itself lives in the architecture's §2 (`D…` numbers) or in the plan's
frozen contracts — those are the binding statements; the rows below only record
what prompted them.

---

## Part A — architecture review, 2026-09-07

### Blocking review findings (architecture §13, since removed)

Independent adversarial review, 2026-09-07, `codex exec` / `gpt-6-astra` (high reasoning, read-only), reviewing this document against the repository at `fd69d499b`. Findings verified against the code before acceptance. Factual and algorithmic corrections are already applied above; the items below are **product or security decisions that must be answered before U1 starts**.

| # | Finding | Status |
|---|---|---|
| **R1** | Membership truth table misstated; `person_is_mutually_visible` already exists (m0140) and is viewer-first; the predicate is not symmetric in practice | **Fixed** — §1, §8.3, §12/U2, and status-quo §11 |
| ~~R2~~ | `CoordinationCase.helpOffersWithCoordination` gates on `canReadContent` alone (`coordination_case.dart:99`) and returns helper identities, messages, withdrawal reasons, coordination responses, and `isDirectAuthorForward`. Widening the wall exposes all of it to discovery-only viewers. Hasura's own help-offer path uses `can_read_involvement`, so Hasura-only tests miss this | **Decided** — parity confirmed: a forwarded recipient sees this today, so a discoverer does too. No new gate, no new projection |
| ~~R3~~ | §5 ships the full explicit-edge set `E` to the client and prunes there, which contradicts §9.1: hiding edges after download still permits reconstructing the rejected social-audit view. Visible endpoints do not by themselves authorize disclosing every relationship between them | **Decided** — full-closure disclosure authorized (D13); §9.1 amended, drawing stays a tree |
| ~~R4~~ | `is_discoverable DEFAULT true` silently re-audiences **every existing active request**, including children created under the previous contract. A parent's opt-out or its author's block does not constrain a differently-authored child | **Decided** — backfill `true` for everything, children included (D12) |
| **R5** | MR publish epoch is an insufficient sole cache invalidator | **Fixed as a constraint** — §8.4; the cache design itself is still open |
| **R6** | Performance risk is unrestricted row scans across the whole application, not the helper in isolation; the `vote_user` short-circuit misses precisely the multi-hop MR audience | **Fixed as a constraint** — §8.4; gate remains open |
| ~~R7~~ | Discovery grants **durable** actions that outlive discoverability: `offerHelp`, `forward`, invitation creation, and `fork` all use the same content gate. A discoverer can offer, forward into another audience, or fork the text, then keep access after opt-out or closure | **Decided** — full parity with a forwarded recipient (D11): same reads, same actions, no new gate |
| ~~R8~~ | Nothing revokes a stale field: `realtime_beacon_recipients` (m0114) targets authors, participants, offerers, and forward endpoints — discovery-only viewers are absent. Image URLs are stable and served over ordinary HTTP, so tightening the SQL wall does not revoke already-disclosed media | **Decided** — refresh on open only (D15); media already disclosed is not revocable, stated as a property rather than fixed |
| **R9** | `computeRadialHopLayout` does not deliver the positional stability its docstring claims; sibling angles move on satellite insertion | **Fixed** — §5, §5.1, §6 |
| **R10** | Single-call layout cannot produce an outer ring or short satellites | **Fixed** — §5.1 |
| **R11** | Sorted-neighbour BFS implements first-discovery parents, a different tree than the specified `(tier, id)` predecessor | **Fixed** — §5 step 2 |
| ~~R12~~ | The unattributable ring may dominate. Illustrative topology: with average visible explicit out-branching of 2, at most 14 peers fit within 3 hops; against 200 request-holding MR peers that is ~93% unattributed (branching 3 → ~80%). These are conditional estimates, not measured data | **Decided** — tier-2 fallback (D1) rather than measure-first; the ring shrinks to the residual only. The R12 estimate assumed explicit-only paths and no longer bounds the outcome |
| **R13** | `mr_graph` is a ranked focus neighbourhood in a fixed 100-row window with known incomplete structural coverage — not a shortest/strongest-path API | **Fixed** — §7.2 |
| **R14** | Copy asserted facts the algorithm cannot know ("Bob has not seen or forwarded this") | **Fixed** — §9.3 |
| ~~R15~~ | §0 defines My Work as authored-or-committed, but the shipped product includes anyone who *offered help*, pending and declined included; `V` excludes ego, so own requests cannot enter `B` | **Decided** — show all, annotate state (D16); My Work restated as authored *or offered help* in §0 |
| **R16** | U3's test selector was `-x pg`, which *excludes* the `@Tags(['pg'])` suites it names | **Fixed** — §12/U3 |

#### Refused without an answer — status

The reviewer named five decisions it would not implement blind. Four are now answered:

1. ✅ Truth table (§1), argument direction (§8.3), global context and **symmetric** policy (D14).
2. ✅ Historical and child defaults (D12); discovery-only capability matrix — full parity (D11).
3. ✅ Full closure may cross the wire (D13).
4. ⚠️ **Still open.** Revocation latency is answered (D15: snapshot-on-open), but authorization-cache freshness, failure behaviour, and the performance gate are not — see §8.4 and §14.2. This is the one remaining hard gate on U3.
5. ✅ Overlap and action rules (D16, D11); ring share addressed by the tier-2 fallback (D1). Deterministic cap and truncation policy still to be written into U6 (§5.2).

---

## Part B — implementation plan adversarial review, 2026-09-08

Protocol: `adversarial-review` (R/C evidence-typed inner loop).

| Role | Who |
|---|---|
| M (owns artifact) | Claude Opus 5 |
| R (reviewer) | `cursor-agent --mode plan --model gpt-5.6-sol-xhigh` (read-only, full repo access) |
| C (critic) | Claude Opus 5, grounded independently **before** reading Review_1 |

> Provenance note: the skill's default R is codex running Astra (GPT-6). Codex usage was
> exhausted, so R ran on Cursor-hosted GPT-5.6 Sol xhigh instead. Cross-model diversity
> (GPT vs Claude) is preserved; the specific model differs from the skill default.

Inner loop terminated **consistent after 2 rounds** (cap 5). Artifact frozen throughout;
no edits were made during the loop. Verdicts: `NEEDS_CHANGES` → `DISAGREE_EVIDENCE` →
`NEEDS_CHANGES` (Review_2) → `AGREE`.

---

### Consistent review — 12 findings

Ordered roughly by severity. Every citation below was verified against live code by C.

#### 1. The D14 symmetry repair never reaches Constellation
`m0163`'s `visible` CTE and UNIT 07 step 1 both enumerate `person_visibility_peers`, which is
asymmetric: `m0151.dart:60-124` derives `is_mutually_visible` from `mr_mutual_scores(v_id, ctx)`,
which is ego-outbound. Only the read wall (`m0162`) uses the new symmetric
`person_are_mutually_visible`. An author admitted by the wall can therefore be absent from the
field's own peer and edge sets — readable request, invisible author, no path. UNIT 04 becomes
load-bearing for the wall only.

#### 2. `constellationField(context: String!)` contradicts the frozen `ctx = ''`
D14 (`constellation-edge-semantics.md:96`) and the plan's own §5 out-of-scope list both pin
`ctx = ''`, yet §0.3 exposes context as a caller-supplied argument and §0.2 threads it into the
port unpinned. `m0151` passes the value straight to `mr_mutual_scores`, so it is semantically
active, not decorative. *Scope note:* R initially claimed a caller could widen the authorized
peer set; on challenge it narrowed the flag — no fixture demonstrates widening. The defect is an
unpinned, semantically active input contradicting a frozen contract.

#### 3. The hop-capped path search lacks optimal substructure
A single winning `(derived, hops)` label per node is not sufficient under `maxHops`. A node
labelled `(0,3)` by a long all-tier-1 route blocks extension to a holder one hop further, while a
discarded `(1,1)` label would have reached it at `(1,2)`. Bounded-hop shortest paths need
`(node, hops)` states. Separately, the parenthetical "tier 1 wins ties by construction" is
**false**: with `ego→q2 (t1) = (0,1)` and `ego→q1 (t2) = (1,1)`, both `q1→p (t1)` and
`q2→p (t2)` realize `(1,2)`, after which min-parent-by-id can select the tier-2 edge. Tie-break
must be `(tier, id)`.

#### 4. The deque does not implement the key it specifies *(found by C)*
§0.4 specifies "0-1 BFS with a deque … cost(tier 1) = 0, cost(tier 2) = 1. The key is the
lexicographic pair `(derived, hops)`". A settle-once 0-1 deque orders by the scalar `derived`
alone; within one `derived` value it is a front-loaded DFS along tier-1 chains. Counterexample,
all tier-1: `ego→a, a→b, b→x, ego→c, c→x`. Relaxing `a` before `c` settles `x` at `(0,3)`;
relaxing `c` before `a` settles it at `(0,2)`. Same input sets, two results — falsifying both
§0.4's "the result is a function of the input sets alone" and UNIT 08's shuffle-50-times
determinism test. "Run to completion" could only repair this with explicit re-enqueue and
stale-entry semantics, which a literal-executor plan must spell out. Correct reduction:
`w(t1) = 1`, `w(t2) = maxHops + 2`, making `hops + (maxHops+1)·derived` exactly lexicographic —
not a 0/1 weight set, so it needs a bucket queue or Dijkstra. Distinct from finding 3.

#### 5. Cap contracts are mutually impossible, and applied in the wrong order
- §0.4 mandates resolving paths on the **full** peer set before truncation, but UNIT 11 step 4
  (`plan:1141-1143`) sequences `repository fetch → selectCappedPeers → resolveConstellationPaths`,
  and UNIT 07 step 1 truncates peers server-side before the edge query. The mandated order is
  inverted in both places.
- Hard cap + complete ancestor chains + "never demote a holder" cannot all hold when chains alone
  exceed `cap`. Dropped attributed holders are not in `ring` either (computed pre-cap), so they
  vanish into an undefined state; `selectCappedPeers` returns only `(keptPeerIds, capped)` and
  cannot express it. The stated ordering also permits keeping a partial chain.
- The request query's `ascending (user_id, id) limit kConstellationRequestCap + 1` cannot honour
  D16's "ego's own … always shown" when ego's `user_id` sorts late.

#### 6. Layout determinism claims conflict
`constellation-edge-semantics.md:212` is normative: "adding a node moves no existing node whose
depth and parent did not change." Equal sibling-sector redistribution and evenly-spaced residual
ring both move such nodes. The plan admits narrowing that rule, but not the second problem:
`holderIds` feeds the cap policy, so **adding a request can change the kept peer set and move
people**, falsifying §0.4's unconditional "adding, removing, filtering, grouping, or expanding
requests moves no person, ever". UNIT 12's position-preserving `relayout` additionally makes the
final layout expansion-order dependent.

#### 7. `GraphNodeWidget` cannot be reused under `ConstellationCubit`
`graph_node_widget.dart:115` is an unconditional `BlocSelector<GraphCubit, GraphState, int?>`.
Mounted with no `GraphCubit` ancestor it throws at build time. `GraphPersonContextCubit` and its
panel (UNIT 15 step 5) have the same coupling. §0.5's entire reuse rationale — "reuses
`GraphNodeWidget`, `EdgeDetails`, and the layout-algorithm seam" — requires a provider-neutral
seam that no unit owns or creates.

#### 8. V2 routing registration is missing
`build_client.dart:161-176` documents the required step ("When adding a new V2 query or mutation
on the server: 1. Add the operation name … to `[_tenturaDirectOperationNames]`"); the set is at
`:188`. UNIT 11 owns neither `build_client.dart` nor `schema.graphql`, so `ConstellationFieldFetch`
routes to Hasura, which has no such field. UNIT 19 likewise omits schema updates for the new
mutation arguments.

#### 9. UNIT 05's Dart policy cannot mirror `m0162` — with a predicted test break *(found by C, evidence sharpened by R)*
`m0162` requires four conjuncts; UNIT 05 step 2's expression
(`facts.isDiscoverable && facts.status.isOpenFamily && facts.isMutuallyVisibleWithAuthor`)
mirrors three. `published_at IS NOT NULL` and `user_id IS NOT NULL` have no Dart counterpart, and
`BeaconContentVisibilityFacts` (`beacon_visibility.dart:4-18`) carries no field for either; the
unit names only two fields to add. The author guard is arguably redundant for open-family rows
under `m0157`; the publication guard is not.

**Concretely predicted break:** `beacon_access_sql_parity_test.dart:105-112` inserts
`(id, user_id, title, description, status, created_at, updated_at)` — never `published_at`. Every
fixture beacon has `published_at IS NULL`, and the suite creates `BeaconStatus.open` beacons at
lines 166, 197, 263, 317, 375 and 424. After the planned change these are SQL-deny / Dart-allow.
Under §2/6 the executor is forbidden from editing the expectation, so this blocks UNIT 05 unless
the fixture gains `published_at` or the Dart facts gain the field.

#### 10. `m0163` leaks edges between mutually blocked peers *(found by C, evidence sharpened by R)*
`allowed` applies `NOT block_hides(v.id, n)` — viewer against each node only. `block_hides`
(`m0135.dart:36-41`) is symmetric in its arguments, but that only makes the *viewer* check
bidirectional; it says nothing about two peers blocking each other. Two peers both visible to ego
stay connected on the map after one blocks the other. This is worst for tier 1: `m0137` gates
withdrawal on `trust_rebuild_effective_edge` (zeroing `prev_sent_weight`, which excludes tier 2)
but deliberately leaves `vote_user` intact — so `m0163` still renders the explicit trust edge.
UNIT 06's block test conflates viewer-blocks with peer-peer blocks and would pass while this
ships.

#### 11. The unit manifest cannot be executed literally
- **UNIT 02** depends only on UNIT 00 but requires before/after measurements of `m0161`/`m0162`,
  which UNITs 04/05 produce — and UNIT 05 gates on UNIT 02. Circular unless the benchmark inlines
  the predicate without shipping the migration; the plan does not say so.
- **UNIT 03** names the V2 field `is_discoverable`, but live `gqlTypeBeacon`
  (`custom_types.dart:338-346`) is camelCase throughout (`addressLabel`, `primaryNeedSlug`,
  `coverImageId`). It also omits the Beacon entity, repository port/impl, mapper and mock needed
  to persist the flag.
- **UNIT 12** uses UNIT 09's filter types but does not depend on UNIT 09.
- **UNITs 13/14** omit `home_tab_branches.dart` (`:54-60` holds
  `HomeTabSpec(tab: HomeTab.updates, index: 2, …)`), `home_tab_reselect_cubit.dart`, and
  `my_work_empty_body.dart` — none are covered by the `root_router.dart` / `home_screen.dart`
  ownership lists.
- **UNIT 19** omits `beacon_create_state.dart`, `beacon_create_cubit.dart`, and
  `data/model/beacon_model.dart` (it owns only `data/gql/beacon_model.graphql`), so the toggle
  cannot be loaded or saved.

#### 12. Several Verify blocks do not exercise their unit's change
- **UNIT 04** step 3 says "re-baseline the forward-candidate suites", but Verify runs
  `dart test -t pg -j 1 test/data/database/` while those suites live in `test/data/repository/`
  (`forward_candidate_context_repository_pg_test.dart`, `forward_candidate_context_sql_test.dart`,
  `forward_candidates_sql_test.dart`) and `test/api/controllers/graphql/`.
- **UNIT 07** tests no query registration, authentication, or GraphQL argument handling.
- **UNIT 11**'s "payload carrying an unexpected score-shaped key is rejected loudly" is
  unobservable once Ferry has produced typed data.
- Router changes omit the existing router contract tests; required AutoRoute/Freezed/l10n
  generation is missing from affected Verify blocks.
- Successive `cd packages/server && …` lines fail on the second when a Verify block is run as one
  shell script, and `./scripts/check-custom-lints.sh packages/server` fails after the `cd`.

---

### Minor notes (not flags)

- `m0161`'s first branch is logically redundant — `person_visibility_peers` already returns
  `is_mutually_visible = true` whenever both explicit-trust directions hold (`m0151.dart:112-120`).
  It is a legitimate perf short-circuit, but UNIT 04's test "reciprocal explicit trust ⇒ true
  without any MR row present (short-circuit)" passes identically with the branch removed, so it
  does not verify the short-circuit is taken.
- UNIT 13 step 3 ("the bar stays at five destinations; leave the fifth slot empty … do not ship an
  intermediate four-destination build") is not implementable as written — a `NavigationBar`
  destinations list has no empty slot — and §2.1's one-commit-per-unit rule means UNIT 13 does
  produce a four-destination tree. Reads as a wording ambiguity around "ship" rather than a
  defect, since the plan also forbids pushing.

### Claims the plan makes that were checked and hold

Latest migration is `m0159`; `m0160`–`m0163` are free. `m0160`'s backfill/default/`NOT NULL`
ordering and partial-index predicate are valid. `m0161`'s NULL/self guards are sound. `m0162` is
inserted at the correct position with `block_hides` still first. `m0163`'s tier dedup is valid
(both tables are PK'd on `(subject, object)`). `block_hides` is symmetric (`m0135.dart:36`).
`user_trust_edge.prev_sent_weight` exists (`m0088.dart:15`). `GraphCubit` is exactly 1473 lines.
`GraphMode` is `trust | forwards | genealogy`. `clampLayoutPosition`, `amenityChordForRingGap`
and `preferredFanStep` all exist in `radial_hop_positions.dart`. `mr_bump_publish_epoch` is in
`m0144`. `UserProfileBatchLookup` and `ForwardCandidatesCase` exist as named. The Hasura `beacon`
filter is `can_read_content`, with no `is_discoverable` column yet. The `beacon_visibility.dart`
docstring does assert "MeritRank and vote-mutual friendship are not part of this predicate".
`lib/domain/entity/beacon_status.dart:16` is `static const openFamilyValues = {0, 7, 8}` — the
citation is correct; it resolves against the **repo-root** shared package, not
`packages/server/lib`. Keeping Constellation out of the weighted `GraphCubit` is sound direction.

---

### Protocol trace

| Round | R | C | Resolution |
|---|---|---|---|
| 1 | 9 flags, `NEEDS_CHANGES` | `DISAGREE_EVIDENCE` | All 9 flags verified real, none spurious. C named 3 code-grounded missed bugs (M1 deque/key mismatch, M2 Dart-mirror parity gap, M3 peer-peer block leak) and challenged flag 2's unsubstantiated impact claim. |
| 2 | 12 flags, `NEEDS_CHANGES` | `AGREE` | All 9 original flags preserved unchanged. Flag 2 narrowed to a contract defect after R found no fixture proving widening. M1/M2/M3 adjudicated real and incorporated as flags 10-12, with R adding two pieces of evidence C had not found: the `beacon_access_sql_parity_test` fixture omits `published_at`, and `m0137` leaves `vote_user` intact so the peer-peer leak is worst at tier 1. Both verified by C. |

Nothing was resolved by capitulation. Flag 2 was narrowed against evidence, not dropped; the three
critic findings were incorporated with evidence, not deferred. C ran its grounding pass before
reading Review_1, so the overlap on findings 1, 3, 5 and 6 is independent convergence.

---

### Outcome — three outer rounds (skill cap)

The plan was edited to revision 4. Full per-finding resolutions are in
Part C below; this is the round-level summary.

| Outer round | Artifact | R's verdict | New defects found |
|---|---|---|---|
| 1 | rev 1 | `NEEDS_CHANGES` | 12 (9 from R, 3 from C) |
| 2 | rev 2 | `NEEDS_CHANGES` | 4 new + 5 partials — **all introduced or left standing by the round-1 edits** |
| 3 | rev 3 | `NEEDS_CHANGES` | 7 more, same pattern |

**The headline result is that pattern.** Every edit round introduced fresh
defects, and each was caught only by re-running R against the edited artifact.
Round 2's most serious finding refuted a correctness argument M had constructed
and stated with confidence: M proved `depth(parent) == depth(p) - 1` by ruling
out `depth(p) > depth(q) + 1`, and never considered the opposite case, which is
exactly where the construction fails (`ego→a→b→v` with `key(v) = (0,3)`, then
`ego→v(t2)→h` giving `key(h) = (1,2)`, so `h` sits at ring 2 with a parent at
ring 3). Editing without re-review would have shipped that.

**Two items are open by design, not by omission:**

1. **`GATE-D1`** — derived-first keys and a well-defined `depth` are in genuine
   conflict; forcing consistency drops reachable holders. Both resolutions are
   costed in §0.4 with option (A) recommended. It is a product decision.
2. **The four architecture amendments** (UNIT 01 step 6). The plan declares
   `constellation-edge-semantics.md` normative and now diverges from it in four
   places; three land immediately, the key-ordering clause waits on `GATE-D1`.
   Revision 2 had also cited `§14.2` items 6-8 that do not exist in the
   architecture — they are new open items and are now marked *proposed* until
   UNIT 01 appends them.

Neither is something a further review round can close.

---

## Part C — implementation plan revision history

Revisions 2–11, all 2026-09-08. Each entry describes a document state that no
longer exists; the plan itself is the only statement of what is currently true.

**Revision 2 — 2026-09-08.** Adversarial review (record:
[`constellation-review-cursor-gpt.md`](constellation-review-cursor-gpt.md);
R = cursor-agent GPT-5.6 Sol xhigh, C = Claude Opus 5; consistent after 2 inner
rounds). Twelve findings, all resolved here:

| # | Finding | Resolution |
|---|---|---|
| 1 | D14 symmetry never reached Constellation — m0163/U07 used asymmetric `person_visibility_peers` | §0.1 adds `person_visible_peers_symmetric`; m0163 and UNIT 07 use it; the residual enumeration gap is documented as a subset guarantee |
| 2 | `constellationField(context:)` contradicted the frozen `ctx = ''` | §0.3 drops the wire argument; resolver pins `kConstellationContext`; UNIT 07 asserts it is absent from the built schema |
| 3 | Winner-take-all labels have no optimal substructure under `maxHops`; the tier tie-break claim was false | §0.4 keeps every `(node, hops)` cell; parent tie-break is `(tier, id)`; UNIT 08 pins both with named tests |
| 4 | A 0-1 BFS deque does not compute the stated `(derived, hops)` key and is edge-order dependent | §0.4 replaces it with a layered `d[p][h]` DP — a `min` over a fixed set, no queue |
| 5 | Cap contracts mutually impossible, and applied before resolution in U07/U11 | §0.4 collapses both into `resolveAndCapConstellation`; chain-atomic keeps; new `droppedHolderIds` third state; ego requests get their own uncapped query |
| 6 | Three determinism claims mutually inconsistent | §0.4's contract restated as four clauses, with the request/holder interaction and the residual ring made explicit |
| 7 | `GraphNodeWidget` unconditionally selects `GraphCubit`, so §0.5's reuse throws | UNIT 12 step 0 lifts the badge into a parameter before any reuse |
| 8 | `_tenturaDirectOperationNames` / `schema.graphql` unowned — query would route to Hasura | UNIT 11 step 4 owns both; UNIT 19 likewise |
| 9 | UNIT 05's Dart mirror dropped `published_at IS NOT NULL`; the parity fixture never sets the column | `isPublished` added to the facts; UNIT 05 step 3 fixes `insertBeacon` first, recorded under §2/7 as a fixture gap, not an expectation change |
| 10 | m0163 filtered only viewer-relative blocks, leaking peer↔peer blocked edges (worst at tier 1 via m0137) | `block_hides(src, dst)` added to `t1`/`t2`; UNIT 06 gains a distinct peer↔peer case |
| 11 | Manifest not literally executable (U02 circular; U03 snake_case + missing persistence path; U12 missing dep on 09; U13/14/19 missing files) | Each fixed in place; `home_tab_branches.dart`, `home_tab_reselect_cubit.dart`, `my_work_empty_body.dart`, `beacon_create_*`, `data/model/beacon_model.dart` now owned |
| 12 | Verify blocks did not exercise their changes | UNIT 04 runs the real forward-candidate suites; UNIT 07 adds registration/auth; UNIT 11 moves wire hygiene to the document and generated types; §2.9 states every Verify line runs from the repo root |

Also folded in: m0161's first branch documented as a performance short-circuit
only, with UNIT 04's test wording corrected to stop implying it verifies one; and
UNIT 13's "fifth slot" wording replaced with the real index-2 semantics plus an
explicit statement that its own commit has four destinations and is not a
release.

Not changed, deliberately: the peer/request caps, D11's action parity, the
`mr_graph` exclusion, and every §5 out-of-scope item. The review raised none of
them.

**Revision 3 — 2026-09-08.** Second adversarial round against revision 2. R
confirmed findings 2, 8, 9 and 10 resolved and found four defects the revision-2
edits had introduced or left standing:

| Defect | Resolution |
|---|---|
| Phase 3 collapsed state-specific predecessors into node-level parents, so a chain could be 4 hops for a node recorded at depth 2 (`ego→a→b→v` with `key(v)=(0,3)`, `ego→v(t2)→h` with `key(h)=(1,2)`) | Parents are now recorded **per state** (`parentAt[p][h]`), which fixes chain length. The residual conflict between derived-first keys and a well-defined `depth` is **not** an executor's call and is now **`GATE-D1`**, with both options costed and (A) recommended. UNITs 08 and 10 block on it |
| U07 still capped peers by id prefix *before* edges and client resolution, so a capped-away intermediary manufactured `paths.ring` | The peer cap is now a guard rail: on overflow the server returns `peersCapped` with empty edges/requests; under it, edges and requests cover the whole symmetric peer set. Path-preserving truncation happens only in `resolveAndCapConstellation` |
| Ring holders displaced by cap step 3 had no state, and were indistinguishable from genuine ring holders | Cap step 3 now also populates `droppedHolderIds`; UNIT 17 reads that, not `ring` |
| `person_visible_peers_symmetric` mixed raw and trimmed `viewer_id`, and re-evaluated `person_visibility_peers(viewer)` once per candidate | Normalization computed once in `n`; the forward direction now reads `c.is_mutually_visible` from the candidate row, so only misses pay a reverse call. UNIT 02's scope widened to the helper, m0163 and the whole endpoint |

Partials also closed: `GraphPersonContextCubit`/`graph_person_context_panel`
carry the same `GraphCubit` coupling as `GraphNodeWidget` and are now owned and
lifted in UNIT 12 unconditionally; UNIT 02's fixture must apply m0160's DDL
before m0162 (`beacon_can_read_content` is `LANGUAGE sql`, validated at creation);
UNIT 13 now owns `home_screen.dart`; and the codegen gap is closed per unit
(`build_runner` in 12, `build_runner` + `gen-l10n` in 13/14/19, `gen-l10n` in
15/17/18, plus `test/app/` router contracts in 13/14).

**Open and deliberately not resolved here:** `GATE-D1` (product decision) and the
architecture amendments it depends on. R was right that revision 2 diverged from
a document it declares normative and cited three `§14.2` items that do not exist;
UNIT 01 step 6 now owns all four amendments, and the `[resolves 14.2/6-8]`
markers are explicitly *proposed* until it lands.

**Revision 4 — 2026-09-08.** Third adversarial round, against revision 3. R
confirmed UNIT 02's m0160-first fixture and UNIT 13's `home_screen.dart`
ownership correct, and confirmed the rewritten symmetric SQL valid (qualified
`c.peer_id` cannot collide with the `RETURNS TABLE` output parameter, and the
dependent `CROSS JOIN` is implicitly lateral — `m0151.dart:41-44` uses the same
form). Seven further defects, all introduced or left standing by revision 3:

| Defect | Resolution |
|---|---|
| `GATE-D1` was not an executable fork — (A) contradicted frozen tests, (B) could not be represented by node-level `parent` maps | Each option now lists exactly what it changes: (A) the wording plus two named UNIT 08 tests; (B) a new `parentRing` map and a UNIT 10 pass-1 rewrite. UNIT 01 is explicitly **not** blocked by the gate |
| `droppedHolderIds` was self-contradictory — a ring holder landed in both `ring` and `droppedHolderIds` | Reverted: `droppedHolderIds` is **attributed-only**. §0.4 states the three disjoint holder states as a table; a cap-displaced ring holder stays a ring holder, and UNIT 08 gains a test for it |
| The peer-cap guard rail did not say what `peers`/`requests`/`requestsCapped` do on overflow | Specified as a table: on overflow everything is empty **except ego's requests** (D16 is unconditional), `peersCapped = true`, `requestsCapped = false` because that query never runs |
| The person-context seam stopped at `onExpand` and ignored the rest of the coupling | All four live touchpoints enumerated with line numbers: the constructor `GraphCubit`, `_graphCubit.state.me.id`, `patchLoadedProfile`, and the panel's required `GraphState` / `canPageMore` / `hiddenNeighborCounts` |
| The helper used `OR`, which does not short-circuit in Postgres, so the cost claim was unsupported | Rewritten as `CASE WHEN c.is_mutually_visible THEN true ELSE …` — the construct `person_are_mutually_visible` already relies on |
| Codegen ran `build_runner` before `gen-l10n`, contrary to `.cursor/rules/codegen.mdc:119-120` | Order flipped in UNITs 13, 14 and 19 |
| The §2 renumbering orphaned `§2/6` and `§2.8` | Updated to `§2/7` and `§2.9` |

Also: UNIT 17's test list said "three absence states" against a four-state
taxonomy and did not cover the two field-level cap states — both fixed.

**Stopping here.** This is the third outer round, the skill's cap. What remains
open is `GATE-D1` and the four architecture amendments UNIT 01 step 6 owns —
product and architecture decisions, not defects another review round can close.

**Revision 5 — 2026-09-08.** `GATE-D1` resolved **(A)** by explicit architecture
override from the plan owner: the path key becomes `(hops, derived)`, hops first.
Recorded as **O1 in §6**, which UNIT 01 step 6 must write into
`constellation-edge-semantics.md`.

Applied: §0.4 phase 2 swapped to hops-first with the
`depth(parent(p)) == depth(p) - 1` proof replacing the gate block; the layered
table re-justified (still needed — `derived` is a *per-layer* minimum a plain BFS
does not give); the tie-break example renumbered to the new key; UNIT 08's
*mixed paths* and *bounded-hop substructure* tests replaced by *hops first,
tier-1 within a layer*, *parent is always one ring in*, and a new *`derived` is
per-layer* case; UNITs 08 and 10 unblocked in the manifest; §2's two-gate rule
reduced to `GATE-14.1` alone; UNIT 01's path amendment made unconditional; and a
§5 prohibition added against an executor restoring derived-first.

**Architecture synchronised.** All six divergences (O1, A2, A3, N1, N2, N3) were
written into `constellation-edge-semantics.md` in the same revision, with an
amendment banner in its header and new §14.2 items 6-8. The two documents no
longer disagree, and UNIT 01 step 6 became a verification step.

`GATE-14.1` (UNIT 02, read-wall performance) remains the one open gate.

**Revision 6 — 2026-09-08.** Fourth adversarial round, the first covering **both**
documents (the architecture had never been reviewed). R independently reproduced
the O1 proof — non-empty predecessor set, both inequality directions, the
telescoping chain, and the walk-vs-simple-path subtlety at the minimum layer —
and confirmed it sound. Six defects plus three corrections, all propagation
failures rather than errors in O1 itself:

| Defect | Resolution |
|---|---|
| O1 not propagated: architecture `:132` and §12.1 still demanded "minimise derived edges before hops"; UNIT 08 still carried derived-first tuples `(1,2)`/`(0,2)` and a blanket tier-1 claim | All restated as **within-layer** preference; tuples corrected to `(2,1)`/`(2,0)`; §12.1's obligation rewritten. The disclosure cost of the change — the bound is now the shortest-path layer, not the residual ring — is stated explicitly at `:132` rather than glossed |
| The architecture's normative wall clause (§8.3) omitted `published_at IS NOT NULL` and `user_id IS NOT NULL`, which m0162 has — so the two documents authorized different reads | All four conjuncts now normative in §8.3, with the parity consequence spelled out |
| D14's promised forward-candidate widening was never implemented: UNIT 04 left `person_visibility_peers` in place and `forward_candidate_context_sql.dart:20-29` still calls it, so eligibility could not change and "re-baselining" had nothing to re-baseline | UNIT 04 now owns both forward SQL files and replaces the `EXISTS` with `person_are_mutually_visible`; this is the step the forwarding owner signs off on |
| N2 left the client cap with no source — the architecture's single 200-peer cap became all-or-nothing, making `resolveAndCapConstellation`'s displaced-holder path unreachable | Two caps now distinguished: `kConstellationPeerCap = 200` (transport guard rail) and `kConstellationRenderPeerCap = 120` (client render budget, the only one that selects), with the strict inequality stated |
| D13 authorized the "explicit-trust closure" while U5 and §9.1 sent both tiers — the tier-2 disclosure was never decided in the row that authorizes it | D13 rewritten to authorize both tiers explicitly, bounding the disclosure to the *existence* of a derived relation between peers ego can already see |
| UNIT 01 step 6 was half-converted — it said "verify" but its bullets still instructed authoring | Now a pure checklist of the eight amendments, with `BLOCKED` on divergence rather than re-authoring |

Corrections from R's own re-derivation, all applied: `key(p)` must range over
**finite** layers only (unrestricted, `(1, ∞)` beats `(2, 0)` lexicographically and
hands an unreachable node depth 1); `depth(ego) := 0` must be stated as a
convention, since ego is absent from the returned map and the invariant is
otherwise undefined at depth 1; and a `(src, dst)` pair arriving with both tiers
must have its tier-2 duplicate discarded, or one edge carries two costs.
`GATE-14.1` was also non-executable as worded — §2 said no executor may resolve
it while UNIT 02 requires an executor to run it; measurement and decision are now
separated, with the budget and the resolution line owned by a named person.

**Round cap.** The skill's outer cap is three rounds; this was the fourth, run at
the plan owner's request after the artifact changed substantially. Every round so
far has found defects introduced by the previous round's edits, and revision 6 is
itself unreviewed.

**Revision 7 — 2026-09-08.** Four open questions answered by the plan owner; all
four applied.

| Question | Decision | Applied |
|---|---|---|
| O1's tier-2 disclosure reach | **Two-stage: tier-1 first, tier-2 only for the residual** | Verified consistent before writing (the option was offered as unproven): stage 1 is a plain tier-1 BFS; stage 2 runs both tiers for unreached holders, and may relax *out of* a stage-1 node only at that node's `depth1`. That constraint is what preserves `depth(parent(p)) == depth(p) - 1` — for `q ∈ T` the rule forces it, for `q ∉ T` the minimality argument applies. D1 is restored to its original wording; §132's disclosure paragraph and §12.1's tier obligation reverted to the residual-only bound |
| `GATE-14.1` budget | **≤ +150ms added p95, per measured query** | Fixed in UNIT 02 step 4(a), with an explicit instruction not to renegotiate it against the measurements |
| Updates fold shape | **Third tab inside Inbox** | UNIT 13 step 1 no longer asks the question; the rationale recorded is read-state safety — a distinct home lets the badge and read-state store move unchanged, which the interleaved option risked |
| Peer-cap overflow | **Bounded subset + "some requests are hidden" + fallback plain list** | UNIT 07 returns the first `kConstellationPeerCap` peers by id with their edges and requests, rather than nothing; UNIT 17 gains a non-dismissible notice; UNIT 18 gains a fallback list mode — the Text view with path explanations suppressed, same query, same authorization |

The two-stage change reverses revision 6's O1 propagation work in the disclosure
direction: UNIT 08's *tier preference at equal length* test is replaced by
**tier 1 wins across stages, however much longer**, which is the test that pins
the bound — if it passes with `depth(h) == 1` the stages have been collapsed.

**Unreviewed.** Revisions 6 and 7 have not been through a round. The two-stage
algorithm is new logic, not a propagation fix, and its reachability cost is the
kind of thing prior rounds caught late.

**Revision 8 — 2026-09-08.** Three sign-offs recorded by the plan owner:
the D14 forward-candidate widening is **approved** (UNIT 04's journal entry now
records who verified the diff, not whether to widen); **D11 action parity is
re-confirmed deliberate**, so UNIT 05's `SECURITY-REVIEW:` line covers
implementation correctness only and must not reopen the decision; and
`kConstellationRenderPeerCap = 120` is recorded as a **provisional, unevidenced**
working value whose only binding property is `< kConstellationPeerCap`.

**Revision 9 — 2026-09-08.** Review round against revision 8. R independently
reproduced the whole O1a analysis — the parent-depth invariant (including why the
constraint's asymmetry saves the `q ∉ T` branch), the impossibility of a chain
leaving and re-entering `T`, Steiner coherence, `derived == 0` for `T` nodes, and
the reachability-loss class — and confirmed each, adding a concrete counterexample
and a proof that multiple incompatible `T` crossings reduce to the same single
loss class. **The two-stage algorithm survived review unchanged.** Five other
defects, three of them blocking:

| Defect | Resolution |
|---|---|
| **The fallback list could not recover anything.** UNIT 07 truncated *requests* to the peer prefix, while UNIT 18 forbids a second query and requires the same snapshot — so requests authored outside the prefix were never fetched and the promised route to omitted content did not exist | Overflow now bounds **the graph, never the content**: `edges` are limited to the peer prefix `P`, but peer `requests` still come from the whole symmetric peer set, and `peers` gains every returned request's author. Edges are the quadratic term and the real reason a cap exists; requests are linear and already separately capped. The omitted thing is now the *path*, so a same-snapshot fallback genuinely recovers the content |
| **Three peer-cap contracts contradicted each other** — §0.2 still said "all-or-nothing", the architecture forbade manufactured ring holders then accepted them, UNIT 07 called the behaviour forbidden then specified it | All three restated coherently; §0.2 now says the guard rail bounds transport but performs no path-preserving selection |
| **UNIT 01's checklist would have rejected the correct algorithm** — it still demanded the revision-6 "within-layer" wording that O1a superseded | Checklist now requires the across-stages wording and names the supersession |
| `attributed` had two incompatible normative meanings — holders-only in the architecture, holders-plus-ancestors in the plan — affecting cap membership and `isAttributed` | Unified on the normative names: `attributed` = reached holders, `keep` = attributed ∪ ancestors. `FieldPersonNode` carries `isKept`; the Steiner pruning test now asserts against `keep`, since asserting against `attributed` would pass vacuously |
| Stale executable baselines: lint baseline 115 vs the repository's 32 (`scripts/custom-lint-baseline.txt`), client version 7.1.0 vs 7.1.5 | Both corrected, with a pointer to re-read the ratchet file rather than trust the plan |

UNIT 07 also gains a test pinning the overflow shape exactly — flag, peer count,
edge containment, requests still drawn from the whole peer set, and every author
present — because asserting only the flag would let an empty-payload
implementation pass.

**Revision 10 — 2026-09-08.** Review round against revision 9. Two of the five
revision-9 fixes held outright (UNIT 01's checklist, the baselines); the other
three were incomplete, and six further defects surfaced. R and C independently
found the same top blocker.

| Defect | Resolution |
|---|---|
| **Ring semantics falsified by peer overflow** (found independently by both reviewers). Bounding the graph rather than the content moved the omission from the request to the *path* — but `ring` is precisely the state asserting a path is absent, so an author outside the graph set is mechanically a ring holder on a claim nothing supports | While `peersCapped` is set, **no ring node anywhere may carry "no permitted path exists" copy**; the whole ring degrades to *"path not shown"*, with an explicit test. The architecture's "caps must not manufacture unattributable peers" rule is restated honestly: the client budget honours it outright, the server graph cap cannot, so the obligation becomes *stop asserting* rather than *never happen* |
| **The overflow contract was not executable through the frozen port.** `visiblePeerIds` returned the capped set and `discoverableRequests` took those author ids, so requests could never come from the whole peer set | Port restructured: `visibleGraphPeerIds` (the first `cap` by id, for edges) and `discoverableRequests(viewerId, context, cap)`, which joins `person_visible_peers_symmetric` itself — no author-id list, no oversized `IN`, and the graph cap cannot narrow it. Added `peerProfiles` for graph peers ∪ request authors |
| **Overflow copy said the opposite of the design.** Both documents said "some requests are hidden" while the frozen l10n key is `constellationPathOmittedByCap` — "Some connection paths are not shown" | Corrected in both, with the reason stated so it does not drift back |
| **"Request set complete / never truncated" was false** whenever `requestsCapped` fires — that cap is independent of peer overflow | Claims softened to "the peer cap does not truncate the request query"; the two caps are documented as independent, may both be set, and need distinct copy |
| UNIT 17 named only two field-level states, omitting the client render-budget `capped` flag the architecture requires | All three named and tested separately |
| A residual `\|peers\| ≤ kConstellationPeerCap` contract, and UNIT 07's ambiguous `{ego} ∪ peerIds` edge call | `peers` is bounded by peer cap + request cap and nothing may assume otherwise; the edge call takes the **graph** set explicitly, and `visiblePeerIds` into path resolution is the graph set |
| Architecture placed **ego in `ring`** — ego is a holder under D16, and `ring := holders \\ tree` never excluded it | `ring := (holders \\ tree) \\ {ego}`, matching the plan |
| Glossary "Person (attributed)" meant every reachable peer while algorithmic `attributed` means holders only | D9 now carries the naming note explicitly |

Three repository errors also corrected. The sharpest reframes UNIT 05:
**`BeaconVisibility.canReadContent` is not on the runtime path.**
`BeaconAccessRepository.canReadContent` (`beacon_access_repository.dart:14-18`)
calls the SQL predicate directly, and no production code constructs
`BeaconContentVisibilityFacts` — the only non-test occurrence is the constructor.
The Dart policy is a specification mirror exercised solely by tests, which is why
the parity suite is load-bearing; UNIT 05 now owns the two test files that build
facts instead of a non-existent production assembly site. Also: UNIT 12 now owns
`graph_app_bar_actions.dart` (exhaustive `switch (mode)` at `:159`), and the
architecture's claim that the stability test "only pins the root" was wrong — it
pins root and one descendant, but only for chain extension, not sibling insertion.

**Revision 11 — 2026-09-08.** Review round against revision 10, the first run with
Fable 5.1 as M, `codex` GPT-6 Astra as R (asked to propose its own solutions and
consistency edits, not only to flag), and `cursor` Kimi K3 as C. Consistent after
one inner round: R = NEEDS_CHANGES, C = AGREE, no spurious flags, no missed bugs.
Eleven findings (6 BLOCKER, 5 SHOULD), two further SHOULD proposals and two
OPTIONAL consistency proposals — all applied.

**Two of the findings were regressions introduced by the revision-10
restructure.** That restructure de-duplicated the algorithm down to architecture
§5 and deleted the plan's copy. The deleted copy was the only one carrying the
stage-2 parent-candidate guard `q ∈ T ⇒ depth1(q) == depth(p)-1`, the explicit
`d2[ego][0] = 0` initialisation, and the names of UNIT 08's "five" tests — so
findings 1 and 11 exist *because* the wrong duplicate survived. C established this
from the pre-restructure backups; R could not, since neither document is tracked.
The OPTIONAL identifier proposal is the structural answer: a deleted clause now
leaves a dangling `ALG-…` reference rather than a silent gap.

| # | Finding | Resolution |
|---|---|---|
| 1 | **BLOCKER, regression.** Stage-2 parent selection checked only the cost equality, so a `T` node pinned at a deeper ring could be chosen as parent of a shallower child (tier 1 `ego→a→b→q→p, r→p`; tier 2 `ego→q, ego→r`; `q<r` ⇒ `parent(p)=q` at depth 3 for `p` at depth 2). The §5 proof's "the relaxation rule already forces" step was false — the rule constrains the table, not the reconstruction | Architecture §5 `ALG-PARENT` now states the guarded rule (`d2[q][depth(p)-1] < ∞ AND (q ∉ T OR depth1(q) = depth(p)-1) AND cost equality`), initialises `d2[ego][0] = 0` explicitly, and `ALG-EGO` excludes ego from parent assignment and every returned map; the proof cites the guard and carries the counterexample. UNIT 08 gains *illegal parent rejected* asserting `parent(p) == r` |
| 2 | **BLOCKER.** UNIT 08's "`derived` is per-layer" fixture put the person in `T` and demanded `(2, 1)`, contradicting O1a and its own "tier 1 wins across stages" test | Fixture replaced with R's: tier-2 `ego→a, a→h, ego→b`; tier-1 `b→c, c→h`; `T` empty; assert `(2, 2)`, so a shorter path with **more** derived edges beats the longer one — the discriminating case the old "hops first" test did not cover. Equal-length tier preference kept as a separate stage-2-only fixture |
| 3 | **BLOCKER.** UNIT 04 widened the two candidate SQL files but `ForwardCase` authorizes the actual send through `PersonVisibilityRepositoryPort.mutuallyVisiblePeerIds`, still filtering the old projection's `is_mutually_visible` — repaired pairs display eligible, then fail at send | UNIT 04 owns `person_visibility_repository.dart`, replaces its query with a bounded `person_are_mutually_visible` check over the supplied recipients (R's SQL verbatim), and adds a `pg` regression through the real repository **and** `ForwardCase`; architecture §8.3 and U2 name the send path |
| 4 | **BLOCKER.** D11's "same reads" contradicted the plan's preserved involvement wall (m0124 grants involvement to forward recipients, not discovery-only viewers); §0.3's claim that third-party participation requires `can_read_involvement` was false (`helpOffersWithCoordination` gates on content with admission fields redacted) | D11 narrowed to content-wall parity plus operation-gated actions, explicitly not `can_read_involvement` or discussion admission (R's sentence). §0.3 participation paragraph replaced with R's text; UNIT 05 step 2/5 and the §4 coverage row qualified the same way |
| 5 | **BLOCKER.** "Never silently convert to backup" was promised by a client-only unit while the live mutation accepts no expected kind and the server derives `offerKind` from the status it reads | UNIT 16 now owns the server mutation, use case, exception code, client document, repository plumbing, schema and tests. §0.3 freezes nullable `expectedOfferKind` (`0` normal, `1` backup; omitted ⇒ legacy); §0.2 freezes `offerKindChanged`. The server locks and re-reads the beacon inside the transaction and rejects a mismatched kind before any write; a no-writes regression flips coverage between preflight and submission. "Opted-out ⇒ do not submit" replaced by "current authorization denied ⇒ do not submit". Architecture §11.5, U10a and §12.1 carry the server property |
| 6 | **BLOCKER.** Cap step 3's "then remaining peers" fill re-admitted fragments of dropped chains and unrelated non-holders (`ego→a→h`, budget 1 kept `a`), violating D9 and UNIT 08's own no-fragment test | Steps 2-3 replaced with R's text: empty kept set, chain-atomic charging of not-yet-kept members, no capacity fill; `capped := ((attributed ∪ ring) \ keptPeerIds).isNotEmpty`. UNIT 08 gains the two-node-chain/budget-1 and no-holders cases |
| 7 | **SHOULD.** UNIT 07 required the server's graph set as `visiblePeerIds` but the wire cannot reconstruct it; `computeConstellationLayout` lacked `keptPeerIds` and `maxHops` | UNIT 07/11: all returned peer ids are `visiblePeerIds`, graph membership is never inferred from edge incidence. Layout signature gains `required Set<String> keptPeerIds` and `int maxHops = 3`; tree positions use `keep ∩ keptPeerIds`, ring `ring ∩ keptPeerIds`, ego always. UNIT 10 gains the cap-displaced-gets-no-position test; UNIT 12 passes the sets through |
| 8 | **SHOULD.** Architecture **B** omitted the publication conjunct; `nodes` attached requests only to `keep ∩ holders` and `ring`, so ego's satellites were formally absent | **B** now requires `published_at IS NOT NULL`, `is_discoverable` for peer-authored only; `nodes` includes `{ b ∈ B : author(b) ∈ {ego} ∪ keep ∪ ring }`. UNIT 08 gains *ego-only field*; the open-but-unpublished case went to UNIT 07 (see deviations) |
| 9 | **SHOULD.** The request query was independent of the block-filtered graph query, and `person_visible_peers_symmetric` filters no blocks | UNIT 07's `discoverableRequests` carries `NOT block_hides(viewer, author)` and `beacon_can_read_content(b.id, viewer)` before the limit and before `requestsCapped`; §0.2 port doc states it; `pg` test for a blocked author outside the graph prefix in both directions |
| 10 | **SHOULD.** Binding table claimed a finiteness fixture UNIT 08 lacked, omitted duplicate-pair and ego bindings; UNIT 20's limitations omitted the stage-2 cost; §0.1 promised UNIT 02 measurements its steps did not list; two untagged tests were absent from UNIT 05's `-t pg` Verify | Named UNIT 08 cases added (*unreachable first layer, reachable second*; *duplicate pair, tier 1 wins*; *ego is excluded*) and bound in §0.4; UNIT 20 lists the stage-2 cost; UNIT 02 measures the helper, m0163 and the full field composition, UNIT 07 records the endpoint against it; UNIT 05's Verify runs the two untagged suites first |
| 11 | **SHOULD, regression.** Stale citations left by the restructure: §0.4 cited architecture line 212 (now the `ring :=` line) for the absolute stability rule; UNIT 07 cited lines 220-229 (now O1) and called the accepted truncation forbidden; §6 promised "five named tests" that no longer had names; UNIT 17's tests still said "field too large" against three states; §5 forbade "any badge, dot, count", which would ban `+N more` | §0.4 points to A3 by name; UNIT 07 cites §5.2 N2 and drops the "forbidden" claim; §6 cites the binding table; UNIT 17 asserts `peersCapped`, `requestsCapped` and client `capped` independently and in combination; §5 forbids badges on the navigation item only and keeps overflow counts |
| + | **SHOULD.** `TimingFilter.withinDays` had no reference time in a pure function | `filterRequestIds` takes `required DateTime asOfUtc` (the snapshot's `loadedAt`); deadline-only by `endAt`, events by overlap, undated via `includeUnspecified`; boundary tests including a wall-clock-independence check |
| + | **SHOULD.** `remoteOrUnspecified` classified missing coordinates as remote | Replaced with `unspecified`; `any \| hasLocation \| unspecified`; remote filter deferred in §0.3, §5.3, UNIT 09/17/20 |
| + | **OPTIONAL.** Stable clause identifiers | Architecture §5 carries `ALG-HOLDERS`, `ALG-DEDUP`, `ALG-STAGE1`, `ALG-STAGE2`, `ALG-PARENT`, `ALG-EGO`, `ALG-PRUNE`; §0.4's binding table, UNIT 08's test names, U6, §4 and UNIT 01's checklist cite them |
| + | **OPTIONAL.** Centralised absence semantics | Architecture §5.2 holds the one normative table (holder states, server graph truncation, request truncation, client displacement, filter/space, and the `peersCapped` override column); §0.4 and UNIT 17 now reference it instead of restating "no permitted path exists" |

**Deviations from R's proposed text, all deliberate:**

- The finiteness example reads `(1, ∞)` vs `(2, 1)`, not `(2, 0)`: for a stage-2
  node `p ∉ T` a `derived == 0` cell cannot occur — an all-tier-1 walk of that
  length would have put `p` in `T`. The architecture comment and the binding table
  say so, and the new UNIT 08 fixture is realizable.
- The "open-but-unpublished request must not enter the field" test lives in
  UNIT 07 (the server query that builds **B**), not UNIT 08: the pure-domain
  resolver takes `holderIds` and has no notion of publication. UNIT 05 already
  pins the wall-side case.
- Stage 1's parent rule now admits `q = ego` explicitly (`{ego} ∪ T`,
  `depth1(ego) = 0`); the previous wording had no legal parent for depth-1 nodes.
  A consequence of `ALG-EGO`, not a new decision.

Not changed, deliberately: the two caps and their numbers, D11's action list,
the `mr_graph` exclusion, the two-stage algorithm itself (R and C re-derived it
and it survived a third review), and every §5 out-of-scope item other than the
badge sentence.

**Revision 12 — 2026-09-08.** Second outer round, against revision 11 (M =
Fable 5.1, R = GPT-6 Astra via codex-cli, C = Kimi K3 via cursor-cli; R asked to
propose its own replacement text, C to audit it against the repository). R:
NEEDS_CHANGES, six findings (3 BLOCKER, 3 SHOULD); C: AGREE — all six real,
none spurious, no missed bugs, plus one immaterial residual C raised alone. R and
C adjudicated all three revision-11 deviations **sound**; they stand. Of the
eleven revision-11 findings, ten are fully fixed. **Finding 5 (silent backup
conversion) was only partially fixed** — server ownership was added, but the
prescribed check sat inside the `_attention.runAction` scope that only the
new-offer branch reaches, and the live active-offer update branch
(`help_offer_case.dart:73-103`) returns before it. It returns here as BLOCKER 1.
R's proposed text applied throughout, with the one addition noted below.

| # | Finding | Resolution |
|---|---|---|
| 1 | **BLOCKER (round-1 #5, partial).** UNIT 16's expected-kind check could be bypassed by the existing active-offer update branch, and the contract did not distinguish creation (kind derived from status) from update (stored kind preserved) | UNIT 16 step 2 replaced: both branches enclosed in `_attention.runAction`; authorization, lifecycle, active-offer lookup, kind validation and all writes inside `BeaconRepositoryPort.runInBeaconStateTransaction`'s locked callback, using the supplied locked `BeaconEntity`; permissible kind = `1` iff locked status is `enoughHelp` for a new offer, the stored `offerKind` for an existing active offer; no branch writes or returns before the check. Ownership gains `help_offer_expected_kind_pg_test.dart`; tests gain the active-offer-update cases, the real-transaction competing-lock case (the unit harness's `action()` cannot prove it) and Verify runs it under `-t pg -j 1`. Architecture §11.5 gains the create/update sentence; §0.3's omission paragraph and §0.2's `offerKindChanged` comment (C's extra item) carry the same distinction |
| 2 | **BLOCKER.** §0.3 froze `beaconOfferHelp(id: ID!, …)`; the live argument is `String!` and the existing operation's `$beaconId: String!` variable is not accepted at an `ID!` position — the "additive" change would break every existing caller | Signature block replaced with `id: String!`, `message: String`, `helpTypes: [String!]`, `expectedOfferKind: Int`; a note records why `ID!` is forbidden. UNIT 16 step 2 gains the schema-compatibility paragraph (preserve `InputFieldId.field` and `$beaconId: String!`; validate and execute the pre-change operation against the updated schema) and a matching test |
| 3 | **BLOCKER.** UNIT 08's containment test discarded any edge with an endpoint outside `visiblePeerIds`, which rejects `ego→a` — ego is not a peer (architecture inputs 3-4 admit `{ego} ∪ V`) | Test replaced: accept edges only when both endpoints are in `{egoId} ∪ visiblePeerIds`; with `visiblePeerIds == {a}`, holder `a`, `ego→a (t1)`, assert `parent(a) == ego`, `depth(a) == 1`, `derived(a) == 0`; other-ID edges ignored even when they would shorten a path |
| 4 | **SHOULD.** The *no order dependence* fixture was all-tier-1 (stage 1 decides it, so stage-2 order dependence could pass); the *duplicate pair* fixture had no route from ego to `a` (assertions unobservable); the binding table omitted `ALG-HOLDERS` | Order-independence fixture replaced with R's stage-2-only case (tier-2 `ego→a, ego→c`; tier-1 `a→b, b→x, c→x`; assert `depth(x)==2`, `derived(x)==1`, `parent(x)==c` over all 120 permutations — R checked all 120). Duplicate-pair fixture gains `ego→a (t1)` and asserts depth/parent as well. Binding table gains the `ALG-HOLDERS` row (UNIT 07 eligibility, UNIT 11 `holderIds` construction); UNIT 11 gains *holder IDs follow returned requests* (`{a, ego}` from two requests by `a`, one by ego, profile-only `b`); §4's coverage row, which mapped all seven identifiers to UNIT 08, now names 07/11 for `ALG-HOLDERS` |
| 5 | **SHOULD.** UNIT 17 step 4 said the cap case means "path data was omitted" (truncation keeps `paths`; only rendering is omitted) and the ring case "says the opposite" of *no path exists* (exceeds §5.2's bounded claim; a four-hop or constraint-declined path may exist); `capped` with empty `droppedHolderIds` was untested | Step 4 replaced with R's text: cap-displaced = known connection omitted by the render budget, path data retained; ring = "Connection not explained within this map's path rules", "Path not shown" under `peersCapped`; never "no connection exists"; ring-not-kept gets a separate render-budget indication and never the cap-displaced class. Step 6 tests client `capped` with both an attributed dropped holder and a ring-only omission (two ring holders, budget 1) |
| 6 | **SHOULD.** UNIT 09's frozen signature took `Iterable<ConstellationRequestRef>`, a type defined nowhere; its unspecified-capability test treated a missing `primaryNeedSlug` as unspecified even with non-empty `needs` | `ConstellationRequestRef` record typedef added to UNIT 09's code block, owned by `constellation_filters.dart`, with the capability-union, location-presence and UTC rules; UNIT 11 maps `ConstellationRequest` into it without data-layer imports. Test replaced: unspecified iff `needs` empty **and** no non-empty `primaryNeedSlug`; a matching `needs` value matches without `primaryNeedSlug` |
| + | **C's residual.** §0.2's `offerKindChanged` comment described the permissible kind as "the kind the re-read, locked beacon permits" — the pre-fix rule that finding 1 corrects for updates | Comment now states the create/update distinction and that the check precedes both branches |

**Deviation from R's proposed text, deliberate:** the §0.3 replacement for the
omission paragraph is R's sentence **plus** the retained "existing clients keep
working and `kDefaultMinClientVersion` does not move" clause and the
`offerKindChanged` / §0.2 / §11.5 cross-references from the revision-11 text.
R's replacement dropped them; they are load-bearing for the version-gate
decision and contradict nothing R proposed. Everything else is R's text
verbatim or re-flowed to list indentation.

Not changed, deliberately: the three revision-11 deviations (adjudicated sound
by both R and C), the algorithm in architecture §5, the cap policy, and every
section no finding names.
