---
status: draft
kind: implementation-plan
source: docs/plans/constellation-edge-semantics.md
source_revision: "2026-09-08 UX amendment"
plan_revision: 11
---

# Constellation — implementation plan

Execution plan for [`constellation-edge-semantics.md`](constellation-edge-semantics.md)
(architecture + UX amendment of 2026-09-08). It is written for a literal executor:
every unit has fixed ownership, exact symbols, ordered steps, tests, and a stop
condition.

**The architecture document is normative.** An executor must not make additional
product choices. Where this plan resolves something the architecture left open
(§14.2 items), the resolution is written into §0 as a frozen contract and marked
`[resolves 14.2/n]`. If live code contradicts a frozen contract, stop and record
`BLOCKED` instead of improvising.

> **For agentic workers:** execute units in manifest order. One unit, its Verify
> block, its journal entry, and one focused local commit before the next. Do not
> push.

**Goal:** ship Constellation — an ego-centred map of the discoverable field of
active requests — as the fourth graph mode in the navigation slot vacated by
Updates, on top of a widened, symmetric, opt-out discoverability read wall.

**Tech stack:** Postgres migrations (`packages/server/lib/data/database/migration/`),
Drift table defs, Dart V2 GraphQL (`graphql_server2` hand-built types), Flutter
client with Freezed cubit states, `force_directed_graphview` render seam,
AutoRoute navigation.

**Blast radius warning:** UNIT 05 changes `beacon_can_read_content`, which is the
row filter for the Hasura `beacon` select permission
(`hasura/metadata.json` → `beacon.select_permissions[user].filter.can_read_content`)
and the guard behind 20+ server call sites. It is an access-control change and is
reviewed as one, not as a feature commit.

---

## Global constraints

- User-facing copy: **Request** / **Chat** / **discussion**. Internal: Beacon /
  room. Never add a `Request` domain entity. Run
  `bash scripts/check-user-facing-terminology.sh` whenever copy changes.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
  `*.config.dart`, `*_g/`, generated l10n, `di.config.dart`). Edit sources, run
  codegen (`dart run build_runner build -d` in the touched package;
  `flutter gen-l10n` for `.arb`).
- Client feature UI uses design-system tokens only: `context.tt`,
  `TenturaText.*`, existing buttons. No raw `Color`/`Colors.*`, `fontSize:`,
  `EdgeInsets`/`BorderRadius` from raw numbers under `features/**` / `ui/**`.
- Dependency direction: client `lib/domain/` and `features/**/domain/` must not
  import `data/` or `ui/`; cubits must not import `data/service/`; server use
  cases depend on ports only. Cubits coordinating ≥2 repositories inject a
  `*Case`.
- Preserve unrelated dirty files. Stage explicit paths only. No push, no
  `--force`, no `git reset`, no `git stash`.
- `@Tags(['pg'])` suites run with `dart test -t pg -j 1` against a **migrated
  disposable** database. `-x pg` *excludes* them and will go green without
  exercising any of this work (R16). Never reset the shared `postgres`.
- After Dart edits under `lib/`, run `./scripts/check-custom-lints.sh <package>`
  for the touched package. Baseline: **client 32, server 0**
  (`scripts/custom-lint-baseline.txt`) — the ratchet has moved since this plan was
  first written, so re-read that file rather than trusting this line.
- **Do not raise `kDefaultMinClientVersion`.** Every schema delta here is
  additive (`beacon.is_discoverable`, new `constellationField` query, new
  `ConstellationField` types); old binaries keep working. The read-wall widening
  changes which rows old clients receive — that is data, not schema.
- Client user-visible work ends at version **7.2.0** (UNIT 20). Live start was
  `7.1.5` at plan-writing time and drifts; UNIT 00 re-reads it. The web cache-buster in `packages/client/web/index.html`
  (`flutter_bootstrap.js?v=`) must be committed with the bump.

---

## 0. Frozen contracts (do not rename)

### 0.1 Migrations

Four new migrations, in this order. Register each in `_migrations.dart`.

```text
m0160   beacon.is_discoverable column + backfill + partial index
m0161   person_reciprocal_explicit_trust + person_are_mutually_visible (symmetric)
m0162   beacon_can_read_content — discoverability clause
m0163   constellation_trust_edges — two-tier, ids-only, self-authorizing
```

**m0160**

```sql
ALTER TABLE public.beacon ADD COLUMN IF NOT EXISTS is_discoverable boolean;
UPDATE public.beacon SET is_discoverable = true WHERE is_discoverable IS NULL;   -- D12
ALTER TABLE public.beacon ALTER COLUMN is_discoverable SET DEFAULT true;
ALTER TABLE public.beacon ALTER COLUMN is_discoverable SET NOT NULL;

CREATE INDEX IF NOT EXISTS beacon_discoverable_author_idx
  ON public.beacon (user_id)
  WHERE is_discoverable AND status IN (0, 7, 8) AND published_at IS NOT NULL;
```

**m0161**

```sql
CREATE OR REPLACE FUNCTION public.person_reciprocal_explicit_trust(
  a_id text, b_id text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT EXISTS (
    SELECT 1 FROM public.vote_user vu
    WHERE vu.subject = a_id AND vu.object = b_id AND vu.amount > 0)
  AND EXISTS (
    SELECT 1 FROM public.vote_user vu
    WHERE vu.subject = b_id AND vu.object = a_id AND vu.amount > 0);
$$;

CREATE OR REPLACE FUNCTION public.person_are_mutually_visible(
  a_id text, b_id text, ctx text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT CASE
  WHEN nullif(trim(coalesce(a_id, '')), '') IS NULL THEN false
  WHEN nullif(trim(coalesce(b_id, '')), '') IS NULL THEN false
  WHEN a_id = b_id THEN false
  WHEN public.person_reciprocal_explicit_trust(a_id, b_id) THEN true          -- §8.4/1
  WHEN public.person_is_mutually_visible(a_id, b_id, coalesce(ctx, '')) THEN true
  ELSE public.person_is_mutually_visible(b_id, a_id, coalesce(ctx, ''))       -- D14 OR-closure
END;
$$;

CREATE OR REPLACE FUNCTION public.person_visible_peers_symmetric(
  viewer_id text, ctx text
) RETURNS TABLE (peer_id text) LANGUAGE sql STABLE AS $$
WITH n AS (
  SELECT nullif(trim(coalesce(viewer_id, '')), '') AS v_id,
         coalesce(ctx, '')                          AS v_ctx
)
SELECT c.peer_id::text
FROM n
CROSS JOIN public.person_visibility_peers(n.v_id, n.v_ctx) c
WHERE n.v_id IS NOT NULL
  AND c.peer_id::text <> n.v_id
  AND CASE
        WHEN c.is_mutually_visible THEN true                    -- forward: already in the row
        ELSE public.person_is_mutually_visible(c.peer_id::text, n.v_id, n.v_ctx)
      END;                                                      -- reverse: forward misses only
$$;
```

`CASE` short-circuits in Postgres, so the reversed MeritRank evaluation runs only
on a double miss. `a_id = b_id → false` matches `person_visibility_peers`, which
excludes self; every caller handles the self case before reaching here.

**`person_visible_peers_symmetric` is the one peer-set source Constellation uses**
(m0163 and UNIT 07), so the field's peer set and the read wall now agree on the
same predicate. It enumerates **candidates** from `person_visibility_peers(viewer)`
— all rows, not just `is_mutually_visible` — and confirms each symmetrically.

**Normalization is computed once, in `n`, and every later reference uses it** —
enumeration, self-exclusion and confirmation must not mix the raw parameter with
the trimmed one, or a padded id enumerates as one identity and validates as
another.

**Cost, and why this shape and not `person_are_mutually_visible` per row.** The
forward direction is already materialized in the candidate row as
`c.is_mutually_visible`, so it is free. The test is a **`CASE`, not an `OR`** —
`OR` has no guaranteed evaluation order in Postgres, so an `OR` formulation would
not support the claim below; `CASE` is the same construct
`person_are_mutually_visible` relies on. Only a **forward miss** pays a reverse
`person_is_mutually_visible(peer, viewer)`, which is one
`person_visibility_peers(peer)` evaluation including its MR projection
(m0140:168-183, m0151:30-124). Calling `person_are_mutually_visible(viewer, c.peer_id)`
per row instead would re-evaluate `person_visibility_peers(viewer)` **once per
candidate** — a multiplicative `C · P(viewer)` that this formulation removes.
Worst case is `P(viewer) + Σ_miss P(peer)`. SQL inlining is **not** assumed.
UNIT 02 measures this helper, `m0163`, and the whole `constellationField` call —
not just the read wall (§14.1).

**[resolves 14.2/6] Known residual gap, deliberate.** A peer `b` reaches ego's
candidate list only through a `vote_user` edge in either direction or a row in
ego's own `mr_mutual_scores` walk. A `b` whose *own* MeritRank walk reaches ego,
with no `vote_user` edge either way and no row in ego's walk, satisfies the
symmetric wall (`m0162` evaluates the reversed direction) but is **not**
enumerable from ego's side without scanning every user. Such an author's request
is therefore readable by the wall yet absent from the field. This is accepted:
**Constellation membership is a subset of wall-readable, never a superset.** It
is a display gap, never an authorization leak. Record it in U20's limitations
list; do not "fix" it with an unbounded scan.

**m0162** — `beacon_can_read_content` re-created from the m0136 body with exactly
one new branch, placed **after** the help-offer branch and **before** `ELSE false`:

```sql
    WHEN b.is_discoverable
      AND b.status IN (0, 7, 8)                              -- D10
      AND b.published_at IS NOT NULL
      AND b.user_id IS NOT NULL                              -- m0157 erasure tombstones
      AND public.person_are_mutually_visible_cached(p_viewer_id, b.user_id, '')  -- D14, ctx = ''; GATE-14.1(b), UNIT 04a
      THEN true
```

**[amended by `GATE-14.1: resolved (b)`]** The predicate call is
`person_are_mutually_visible_cached`, not the direct
`person_are_mutually_visible` this section originally specified before the
gate resolved — see
[`constellation-read-wall-performance.md`](constellation-read-wall-performance.md)
and UNIT 04a. The uncached function is not deleted (UNIT 04a's cache still
calls it once per genuine miss) and every other frozen contract in this
section is unchanged; only this one call site gains the cache seam.

Nothing else in the function changes. `block_hides` stays the first branch.

**m0163**

```sql
CREATE OR REPLACE FUNCTION public.constellation_trust_edges(
  p_viewer_id text,
  p_ctx       text,
  node_ids    text[]
) RETURNS TABLE (src text, dst text, tier smallint)
  LANGUAGE sql STABLE AS $$
WITH viewer AS (
  SELECT nullif(trim(coalesce(p_viewer_id, '')), '') AS id, coalesce(p_ctx, '') AS ctx
),
visible AS (
  SELECT s.peer_id::text AS id
  FROM viewer v
  CROSS JOIN public.person_visible_peers_symmetric(v.id, v.ctx) s   -- D14, symmetric
  WHERE v.id IS NOT NULL
),
allowed AS (
  SELECT DISTINCT n AS id
  FROM viewer v
  CROSS JOIN unnest(node_ids) AS n
  WHERE v.id IS NOT NULL
    AND nullif(trim(coalesce(n, '')), '') IS NOT NULL
    AND (n = v.id OR n IN (SELECT id FROM visible))          -- D6
    AND NOT public.block_hides(v.id, n)      -- block_hides is symmetric (m0135)
),
t1 AS (
  SELECT vu.subject::text AS src, vu.object::text AS dst
  FROM public.vote_user vu
  INNER JOIN allowed a ON a.id = vu.subject
  INNER JOIN allowed b ON b.id = vu.object
  WHERE vu.amount > 0 AND vu.subject <> vu.object
    AND NOT public.block_hides(vu.subject, vu.object)   -- peer↔peer block, not just viewer
),
t2 AS (
  SELECT e.subject::text AS src, e.object::text AS dst
  FROM public.user_trust_edge e
  INNER JOIN allowed a ON a.id = e.subject
  INNER JOIN allowed b ON b.id = e.object
  WHERE e.prev_sent_weight > 0 AND e.subject <> e.object     -- positive_only, hard-coded
    AND NOT public.block_hides(e.subject, e.object)     -- peer↔peer block
)
SELECT t1.src, t1.dst, 1::smallint FROM t1
UNION ALL
SELECT t2.src, t2.dst, 2::smallint FROM t2
WHERE NOT EXISTS (SELECT 1 FROM t1 WHERE t1.src = t2.src AND t1.dst = t2.dst);
$$;
```

The function is **self-authorizing**: it computes `V` itself with one
`person_visible_peers_symmetric` call, so no caller can widen the endpoint set.
It returns **no weight and no score column** (§9.1). `graph_edges_between`
(m0136) is untouched — it returns weights and belongs to the existing trust
graph.

**Blocks are filtered twice, deliberately.** `allowed` drops nodes the *viewer*
blocks or is blocked by; `t1`/`t2` additionally drop any edge whose **two
endpoints** block each other. The second filter is not redundant: `block_hides`
is symmetric in its arguments (m0135), but that only makes the viewer check
bidirectional — it says nothing about two peers who are both visible to ego.
This matters most at **tier 1**: m0137 gates withdrawal on
`trust_rebuild_effective_edge`, which zeroes `prev_sent_weight` (removing the
tier-2 edge) but deliberately leaves `vote_user` intact, so without this filter a
blocked pair would still render as explicit trust.

### 0.2 Server Dart

```dart
// packages/server/lib/domain/entity/constellation_field.dart          (NEW)
class ConstellationFieldSnapshot {
  final DateTime loadedAt;
  final String context;
  final List<ConstellationPeerRecord> peers;
  final List<ConstellationEdgeRecord> edges;     // tier 1 or 2, ids only
  final List<ConstellationRequestRecord> requests;
  final bool peersCapped;
  final bool requestsCapped;
}
class ConstellationEdgeRecord { final String src, dst; final int tier; }
```

```dart
// packages/server/lib/domain/port/constellation_field_repository_port.dart (NEW)
abstract interface class ConstellationFieldRepositoryPort {
  /// The **graph** peer set: the first [cap] symmetric (D14) peers by id, via
  /// `person_visible_peers_symmetric`. `capped` is true iff more existed.
  /// These are the only ids edges may span.
  Future<({Set<String> ids, bool capped})> visibleGraphPeerIds({required String viewerId, required String context, required int cap});
  Future<List<ConstellationEdgeRecord>> trustEdges({required String viewerId, required String context, required Set<String> nodeIds});
  /// Ego's own active requests. Never subject to `is_discoverable` and never
  /// subject to the peer-request cap (D16 — they are ego's, always shown).
  Future<List<ConstellationRequestRecord>> ownRequests({required String viewerId});
  /// Peers' discoverable requests, over the **whole** symmetric peer set — it
  /// joins `person_visible_peers_symmetric` itself rather than taking author ids,
  /// so the graph cap cannot narrow it and no oversized `IN` list is built. Never
  /// returns ego's own. Carries its **own** authorization predicate, independent
  /// of the graph query (UNIT 07): `NOT block_hides(viewer, author)` and
  /// `beacon_can_read_content(b.id, viewer)`, applied before the limit.
  Future<List<ConstellationRequestRecord>> discoverableRequests({required String viewerId, required String context, required int cap});
  /// Profiles for the graph peers ∪ every returned request's author.
  Future<List<ConstellationPeerRecord>> peerProfiles({required Set<String> ids});
}
```

```dart
// packages/server/lib/domain/use_case/constellation_field_case.dart   (NEW)
@Singleton(order: 2)
final class ConstellationFieldCase extends UseCaseBase {
  Future<ConstellationFieldSnapshot> load({required String viewerId, required String context});
}
```

Caps, server-side (§5.2): `kConstellationPeerCap = 200`,
`kConstellationRequestCap = 150`, in
`packages/server/lib/consts/constellation_consts.dart`.

```dart
// packages/server/lib/domain/exception_codes.dart                      (edit, UNIT 16)
enum HelpOfferCoordinationExceptionCode { …, offerKindChanged }
// raised by HelpOfferCase.offerHelp when a supplied expectedOfferKind differs
// from the permissible kind under lock — for a new offer, the kind the locked
// beacon's status derives; for an existing active offer, its stored kind. It
// precedes both branches; no offer, commitment, or receipt row is written
// (architecture §11.5).
```

**Two caps, only one of which selects.** `kConstellationPeerCap` is a **transport
guard rail** — it bounds what crosses the wire but performs **no path-preserving
selection** (UNIT 07). The cap that
`resolveAndCapConstellation` consumes is a separate, smaller **client render
budget**, `kConstellationRenderPeerCap = 120`, in
`packages/client/lib/features/constellation/domain/constellation_consts.dart`
(owned by UNIT 08). It must be **strictly less than** `kConstellationPeerCap`, or
the displaced-holder path is unreachable and the three holder-absence states of
§0.4 collapse to two. Do not pass the server cap into the client policy.

**120 is provisional and deliberately unevidenced.** It was set by the plan owner
as a working value, not derived from measurement, and is expected to change. The
only binding property is the strict inequality above; treat the number itself as
a tunable constant, and do not build a test that asserts `== 120`.

### 0.3 GraphQL (V2, additive)

```graphql
constellationField: ConstellationField!        # no context argument — see below

type ConstellationField {
  loadedAt: String!                       # ISO-8601 UTC
  context: String!                        # echoes the server-pinned '' (D14)
  peers: [ConstellationPeer!]!
  edges: [ConstellationEdge!]!
  requests: [ConstellationRequest!]!
  peersCapped: Boolean!
  requestsCapped: Boolean!
}
type ConstellationPeer { id: String!, displayName: String, handle: String, image: image }
type ConstellationEdge { src: String!, dst: String!, tier: Int! }     # 1 | 2 only
type ConstellationRequest {
  id: String!
  authorId: String!
  title: String!
  status: Int!
  needs: [String!]!
  primaryNeedSlug: String
  startAt: String
  endAt: String
  addressLabel: String
  hasCoordinates: Boolean!
  isMine: Boolean!
  viewerHasActiveHelpOffer: Boolean!
  viewerIsRoomParticipant: Boolean!
  viewerHasForwardEdge: Boolean!
  helpOfferCount: Int!
  coverThumb: image
}
```

One existing mutation gains one **additive, nullable** argument (UNIT 16):

```graphql
beaconOfferHelp(
  id: String!
  message: String
  helpTypes: [String!]
  expectedOfferKind: Int
): Boolean!
```

`id` stays `String!` — the live argument type (`schema.graphql:3433`,
`input_field_id.dart:4`) and the type the existing operation's
`$beaconId: String!` variable requires; a variable is not accepted at an `ID!`
position, so changing it would break every existing caller. `expectedOfferKind`
is `0` normal, `1` backup. Omission preserves existing behavior: new offers
derive their kind from current request status, while active-offer updates retain
their stored kind — so existing clients keep working and
`kDefaultMinClientVersion` does not move. Constellation supplies the kind the
user explicitly chose; a mismatch is rejected before any write with
`offerKindChanged` (§0.2, architecture §11.5).

**Wire hygiene (§9.1, testable):** the serialized payload contains no key
matching `/score|weight|_mr$|meritrank|rank/i`, in either tier. `tier` is the
only edge attribute and carries no magnitude.

**[resolves 14.2/7] `ctx` is pinned server-side and is not a query argument.**
D14 and §5 both fix `ctx = ''`. `ctx` is not inert — `person_visibility_peers`
passes it straight to `mr_mutual_scores`, and m0144 publishes context-specific
MR edges — so a caller-supplied context would be a semantically active,
unvalidated input against a frozen contract. The resolver therefore takes **no**
context argument and calls the use case with the constant
`kConstellationContext = ''`. The `context` response field echoes that constant
so a later switch to per-capability contexts stays a server-side parameter
change. `ConstellationFieldCase.load` keeps its `context` parameter (the seam
D14 asks for); only the *wire* is pinned.

**[resolves 14.2/4] Filter field mappings.** Reliable sources only:

| Filter | Source | Unavailable ⇒ |
|---|---|---|
| Capability | `beacon.needs` + `primary_need_slug` | request joins the identified "Unspecified" group |
| Location | `address_label` present, `hasCoordinates` — **presence** of a location only. Missing values are *unspecified*, never "remote"; a remote-specific filter is deferred until an explicit reliable field exists (limitation recorded in U20) | "Unspecified" group |
| Timing | `start_at` / `end_at` (semantics per `beacon-schedule-semantics`) | "Unspecified" group |
| Effort | **no reliable field — filter omitted in v1**, limitation recorded in U20 | — |

**[resolves 14.2/4] Participation detail.** Constellation v1 exposes only its
specified viewer-scoped facts — the three booleans above — and `helpOfferCount`,
and intentionally omits third-party participation statements such as *"Ana is
helping"* from this payload and from the preview (§11.2). Existing endpoints
retain their existing authorization: Hasura help-offer rows use the involvement
wall (`can_read_involvement`, m0124), while `helpOffersWithCoordination`
(`coordination_case.dart:95-122`) uses **content** access with admission fields
redacted for third parties. This plan changes neither endpoint's gate, and
discovery does not grant `can_read_involvement` (D11 as narrowed). Do not
synthesize.

### 0.4 Client pure domain

```dart
// packages/client/lib/features/constellation/domain/constellation_path_resolution.dart (NEW)
typedef ConstellationEdgeRef = ({String src, String dst, int tier});

typedef ConstellationPathResolution = ({
  Map<String, int> depth,        // reached people, 1..maxHops
  Map<String, int> derived,      // reached people, count of tier-2 edges on the chosen path
  Map<String, String> parent,    // person -> parent (ego for depth 1)
  Map<String, int> parentTier,   // person -> tier of parent->person edge
  Set<String> attributed,        // reached HOLDERS only          (architecture §5 step 3)
  Set<String> keep,              // attributed ∪ their ancestors  (Steiner keep set, D9, step 4)
  Set<String> ring,              // holders not reached within the cap  (D3 residual)
});

ConstellationPathResolution resolveConstellationPaths({
  required String egoId,
  required Set<String> visiblePeerIds,
  required Set<String> holderIds,
  required Iterable<ConstellationEdgeRef> edges,
  int maxHops = 3,               // D2
});
```

**Algorithm — normative source: architecture §5 (O1 / O1a / O1b).** Do not
restate it here and do not re-derive it. §5 states the two stages, the
`d2[p][h]` layered table and its stage-2 constraint, the hops-first key with its
load-bearing finiteness restriction, the guarded `(tier asc, id asc)` parent
selection, the duplicate-pair discard, ego's exclusion, and the proof of the ring
invariant. Its clauses carry stable identifiers (`ALG-HOLDERS`, `ALG-DEDUP`,
`ALG-STAGE1`, `ALG-STAGE2`, `ALG-PARENT`, `ALG-EGO`, `ALG-PRUNE`); this table and
UNIT 08's test names cite them, so a clause removed from §5 leaves a dangling
reference here rather than a silent gap. This plan binds that algorithm to units
and to Dart names. **Where the two disagree, §5 wins and the disagreement is a
bug in this file.**

What the units owe it, and nothing more:

| Architecture clause (§5) | Bound by |
|---|---|
| `ALG-HOLDERS` — holders are the author IDs of returned eligible requests | UNIT 07 verifies request eligibility; UNIT 11 verifies construction of `holderIds` from the returned request set, including ego — *holder IDs follow returned requests* |
| `ALG-DEDUP` — a `(src, dst)` pair carrying both tiers keeps tier 1 only | UNIT 08 *duplicate pair, tier 1 wins* |
| `ALG-STAGE1` — two stages; a holder reachable by explicit trust is never explained by a derived edge (O1a) | UNIT 08 *tier 1 wins across stages* and *stage-1 nodes carry `derived == 0`* |
| `ALG-STAGE2` — hops-first key within a stage, finiteness-restricted (O1b) | UNIT 08 *hops first inside stage 2 / `derived` is per-layer* and *unreachable first layer, reachable second* — the `(1, ∞)` vs `(2, 1)` case the restriction exists to exclude |
| `ALG-STAGE2` — order-independence: each cell is a `min` over a fixed set, never a queue | UNIT 08 *no order dependence in the table* plus the shuffle test. A 0-1 BFS deque is **forbidden**: it front-loads tier-1 chains within one `derived` value, a DFS on hops, and settles `x` at 2 or 3 hops by edge order alone |
| `ALG-PARENT` — `(tier asc, id asc)` parent tie-break (D8) | UNIT 08 *tier beats id in the parent tie-break* and *min-id parent, not first discovery* — a tier-1 and a tier-2 predecessor can realize the same key; id alone would let the derived edge explain a person the explicit edge explains equally well |
| `ALG-PARENT` — the **parent-candidate guard** `q ∉ T OR depth1(q) = depth(p)-1` | UNIT 08 *illegal parent rejected* — §5's own counterexample, asserting `parent(p) == r`. This guard once existed only in a since-deleted duplicate of the algorithm; the identifier is what keeps it auditable |
| `depth(parent(p)) == depth(p) - 1`, proved in §5 from `ALG-PARENT` | UNIT 08 *parent is always exactly one ring in*; UNIT 10's sibling-sector model rests on it. Not re-proved here |
| `ALG-STAGE2` — the constraint costs reachability; such holders fall to `ring` | UNIT 08 *stage-2 constraint costs reachability*; UNIT 20 limitations list. Never "fix" it by letting a `T` node float between rings |
| `ALG-EGO` — ego is absent from every returned map and from `ring` | UNIT 08 *ego is excluded* and *ego-only field* |
| `ALG-PRUNE` — `attributed` = reached holders; `keep` = Steiner set (D9) | UNIT 08 *Steiner pruning*, asserted against `keep` |

Cost is bounded and small: `maxHops × |E|` relaxations, with `|E|` already capped
by the peer cap. This is deliberately **not** `computeRadialHopLayout`'s
first-discovery parent (R11), and the layout is fed the resulting parent edges
rather than re-deriving them.

`attributed := holderIds ∩ reached` — **reached holders only**, matching the
architecture's §5 step 3. `keep := attributed ∪ { every ancestor of an attributed
holder }` is the Steiner set (step 4), and it is `keep` — not `attributed` — that
the cap policy and rendering consume. The two names are **not** interchangeable:
an intermediary is in `keep` and not in `attributed`, and `FieldPersonNode`
carries `isKept`, never `isAttributed`.
`ring := holderIds \ reached` (excluding `egoId`).

```dart
// .../domain/constellation_cap_policy.dart                            (NEW)
typedef ConstellationResolvedField = ({
  ConstellationPathResolution paths,   // ALWAYS resolved on the full peer set
  Set<String> keptPeerIds,
  Set<String> droppedHolderIds,        // holders the cap could not fit at all
  bool capped,
});

/// The **only** entry point. Resolution and truncation are one call precisely so
/// no caller can invert their order (see the ordering rule below).
ConstellationResolvedField resolveAndCapConstellation({
  required String egoId,
  required Iterable<String> visiblePeerIds,
  required Set<String> holderIds,
  required Iterable<ConstellationEdgeRef> edges,
  required int cap,
  int maxHops = 3,
});
```

**[resolves 14.2/1] Truncation is path-preserving and score-independent.**
Internally, in this order:

1. Run `resolveConstellationPaths` on the **full** peer set. `paths` — including
   `ring` — is always the full-set resolution and is never recomputed on the
   truncated set.
2. Keep, **chain-atomically**, starting from an **empty** kept set: for each
   holder in `paths.attributed` ascending by id, compute its complete selected
   ancestor chain (its share of `paths.keep`), **excluding ego**. Charge the
   budget only for chain members not already kept. If every missing member fits,
   add them all; otherwise add **none** and record the holder in
   `droppedHolderIds` — never keep a partial chain.
3. Then ring holders ascending by id, each while budget remains. **Do not fill
   unused capacity with other peers.** Anything not selected by steps 2-3 is
   either a fragment of a dropped chain or a non-holder with no kept descendant,
   and re-admitting either violates D9 and the no-fragment test in UNIT 08 —
   with `ego→a→h`, holder `h`, budget 1, the chain cannot fit, and a "remaining
   peers" fill would keep `a` alone.

```text
capped := ((paths.attributed ∪ paths.ring) \ keptPeerIds).isNotEmpty
```

**Holder states are defined once — architecture §5.2's absence-semantics table
(N2).** This plan does not restate them. What it binds: `droppedHolderIds` is
**attributed-only**. A *ring* holder that step 3 cannot fit stays in `paths.ring`,
absent from `keptPeerIds`, and never enters `droppedHolderIds`; `capped` is what
reports the omission. Putting it in both sets, as an earlier revision did, made
two mutually exclusive claims true at once and left UNIT 17 unable to pick
truthful copy. UNIT 17 reads the same table, including its `peersCapped` override
of ring copy.

**Ordering is structural, not a convention.** Resolving after truncating
re-derives a dropped intermediary's holder into the ring with no signal —
a cap masquerading as "no permitted path exists" (architecture §5.2).
`selectCappedPeers` no longer exists as a separately callable function
*because* callers got this backwards; there is one function and it fixes the
order internally.

```dart
// .../domain/constellation_density.dart                               (NEW)
typedef ConstellationLabelBudget = ({int perPerson, int total});

ConstellationLabelBudget constellationLabelBudget({
  required Size viewport,
  required double textScaleFactor,
});   // ceilings, never targets: perPerson ≤ 3, total ≤ 150

Map<String, List<String>> allocateVisibleRequests({
  required Map<String, List<String>> requestIdsByAuthor,  // each list ascending id
  required ConstellationLabelBudget budget,
});   // round-robin over authors sorted by id — no author can eat the budget
```

```dart
// .../domain/constellation_layout.dart                                (NEW)
typedef ConstellationLayout = ({
  Map<String, Offset> positions,   // people, ring people, and requests
  Map<String, int> ring,           // person -> 0 ego, 1..maxHops tree, maxHops+1 residual
});

ConstellationLayout computeConstellationLayout({
  required String egoId,
  required ConstellationPathResolution paths,  // full-set resolution, unfiltered
  required Set<String> keptPeerIds,            // from resolveAndCapConstellation
  required Map<String, List<String>> visibleRequestsByAuthor,
  required Set<String> egoOwnRequestIds,       // D16
  required Size canvasSize,
  int maxHops = 3,                             // the same value paths were resolved with
  double ringGap = 170,
  double residualRingFactor = 1.6,             // × ringGap beyond maxHops
  double satelliteOffset = 56,
});
```

`paths` alone cannot tell a selected person from a cap-displaced one, so the
layout takes `keptPeerIds` explicitly: person-tree positions are computed for
`paths.keep ∩ keptPeerIds`, ring positions for `paths.ring ∩ keptPeerIds`, and
ego is always included. A cap-displaced holder and its excluded ancestors receive
**no** node and **no** position. Both sets remain the unfiltered snapshot sets
within a snapshot (filters never reach this function). `maxHops` is a parameter
because pass 2's geometry uses it; it must equal the value the paths were
resolved with.

Three passes (§5.1), never one call:

1. **Person tree.** Rings by `paths.depth`, over `paths.keep ∩ keptPeerIds`.
   Sibling sectors are split **equally** among children sorted by id — *not* by
   subtree size. This is the R9 fix: subtree-size weighting rotates a person when
   a satellite appears.
2. **Residual ring.** `paths.ring ∩ keptPeerIds` placed on radius
   `(maxHops + residualRingFactor) × ringGap`, sorted by id, evenly spaced. Not
   part of any BFS. Stubs are decoration drawn afterwards.
3. **Satellites.** Each request at `satelliteOffset` from its already-placed
   author, fanned outward along the author's radial direction (ego's own hang off
   the centre). Never a graph hop.

**[resolves 14.2/1] Determinism contract, exactly:**

- the result is a function of the arguments only, never of set iteration order,
  and never of the order in which the user expanded things — the layout is
  recomputed from the current resolved field every time, never patched forward
  from a previous layout;
- **filtering, grouping, or expanding** requests moves no person, ever. This one
  is unconditional because UNIT 17 keeps the layout input unfiltered: filters
  change which satellites are drawn, never `holderIds`;
- **adding or removing** a request moves no person **unless it changes its
  author's holder status**. It can: `holderIds` feeds
  `resolveAndCapConstellation`, so a person's first request can pull them (and
  their ancestor chain) into the kept set and change the sector split. When
  holder membership is unchanged, positions are bit-identical;
- adding a **person** may re-split its parent's sector among sorted siblings, but
  never moves anything outside that parent's sector, and never changes any
  ancestor's position. Note this is vacuous at depth 1, where the parent is ego
  and the sector is the whole circle;
- the **residual ring** is evenly spaced by id and is outside the sector
  guarantee: adding or removing a ring person re-spaces the other ring people,
  and moves nothing in the tree.

The binding positional-stability contract is architecture §5.1, **A3** — the
four clauses above restate it and add nothing. UNIT 20 records its holder-status,
sibling-sector, and residual-ring exceptions in the limitations list.

### 0.5 Client feature layout

```text
packages/client/lib/features/constellation/
  domain/constellation_path_resolution.dart
  domain/constellation_cap_policy.dart
  domain/constellation_density.dart
  domain/constellation_layout.dart
  domain/constellation_filters.dart
  domain/entity/constellation_field.dart          (freezed)
  domain/port/constellation_repository_port.dart
  domain/use_case/constellation_field_case.dart
  data/gql/constellation_field_fetch.graphql
  data/repository/constellation_repository.dart
  data/repository/constellation_repository_mock.dart
  ui/bloc/constellation_cubit.dart
  ui/bloc/constellation_state.dart                (freezed)
  ui/screen/constellation_screen.dart
  ui/widget/constellation_body.dart
  ui/widget/constellation_request_preview_sheet.dart
  ui/widget/constellation_filter_bar.dart
  ui/widget/constellation_text_view.dart
  ui/widget/constellation_snapshot_bar.dart
```

Render vocabulary is shared, per the architecture's reuse map:
`GraphMode.constellation` and `GraphLegendMode.constellation` are added to the
existing enums in `features/graph/domain/entity/graph_mode.dart` and
`features/graph/ui/widget/graph_legend_mode.dart`; node kinds
`FieldPersonNode` / `FieldRequestNode` are added to
`features/graph/domain/entity/node_details.dart`; the layout algorithm
`ConstellationLayoutAlgorithm` is added to
`features/graph/ui/utils/tentura_layout_algorithms.dart`.

**[resolves 14.2/8] The reused widgets need a provider-neutral seam first.**
The reuse below does **not** work as-is: `GraphNodeWidget`
(`graph_node_widget.dart:115`) contains an unconditional
`BlocSelector<GraphCubit, GraphState, int?>` for its hidden-neighbour badge, so
mounting it under `ConstellationCubit` with no `GraphCubit` ancestor throws at
build time. `GraphPersonContextCubit` and `graph_person_context_panel` (UNIT 15)
have the same coupling. UNIT 12 therefore **first** lifts that dependency —
`GraphNodeWidget` takes `hiddenNeighborCount` as a parameter and the existing
graph surfaces pass `context.select<GraphCubit, int?>(…)` at the call site — and
only then reuses the widget. This is a pure refactor of existing surfaces and
must leave `test/features/graph/` green unchanged.

**`GraphCubit` is not extended.** Constellation is driven by its own
`ConstellationCubit` and its own `ConstellationBody`, which reuses
`GraphNodeWidget`, `EdgeDetails`, and the layout-algorithm seam. Rationale:
`GraphCubit` is 1473 lines with three interacting modes, block listening, focus
expansion, and beacon fetch; a fourth data source there would couple the field
snapshot to focus-driven refetch, which D15 forbids. This is a structural call,
not a product one, and it keeps `GraphMode` single-sourced as the architecture
requires.

### 0.6 Copy and identifiers

l10n keys (both `app_en.arb` and `app_ru.arb`), user-facing wording per §9.3 —
epistemic, never transactive:

```text
constellationTitle                 "Constellation"
constellationRingHint              "Reachable through your wider network"
constellationConnectionLabel       "Visible through {name}"
constellationNotReferral           "This is a connection, not a referral"
constellationLoadedAt              "Loaded at {time}"
constellationFindWaysToHelp        "Find ways to help"
constellationEmptyFiltered         "No requests match these filters"
constellationClearFilters          "Clear filters"
constellationUnspecifiedGroup      "Unspecified"
constellationPathOmittedByCap      "Some connection paths are not shown"
constellationMoreRequests          "+{count} more"
constellationMapView / constellationTextView
requestDiscoverableLabel           "Discoverable"
requestDiscoverableHint            "Discoverable by people you and your network can both see"
```

Forbidden strings anywhere in Constellation copy: "from {name}", "via {name}",
"{name} shared", "{name} has not seen", "recommended", "top", "trending".

Test ids (`packages/client/lib/ui/test_ids.dart`):

```text
constellationMap            'constellation.map'
constellationNavItem        'constellation.nav_item'
constellationLoadedAt       'constellation.loaded_at'
constellationViewToggle     'constellation.view_toggle'
constellationFilterBar      'constellation.filter_bar'
constellationRequestPreview 'constellation.request_preview'
constellationPersonExpand   'constellation.person_expand'
constellationRingStub       'constellation.ring_stub'
myWorkFindWaysToHelp        'my_work.find_ways_to_help'
requestDiscoverableToggle   'request.discoverable_toggle'
```

---

## 1. Live baseline and stop conditions

At plan-writing time (2026-09-08):

```text
latest migration                     m0159
packages/client/pubspec.yaml         7.1.5
packages/client/web/index.html       flutter_bootstrap.js?v=7.1.5
packages/server/lib/env.dart         kDefaultMinClientVersion = '7.0.0'
beacon_can_read_content              m0136 (4 grant branches + block/status guards)
person_visibility_peers              m0151   |  person_is_mutually_visible  m0140
graph_edges_between                  m0136 (node_ids, positive_only, hasura_session)
Hasura beacon row filter             can_read_content _eq true
GraphMode / GraphLegendMode          trust | forwards | genealogy
Home destinations                    My Work, Inbox, Updates, Friends, Profile
architecture source                  constellation-edge-semantics.md, UX amendment 2026-09-08
```

Before UNIT 00, re-read those values. Stop with `BLOCKED` when:

- a migration above `m0159` already exists **and** this plan would add a
  colliding number — renumber into the free range and record it, do not skip;
- `beacon_can_read_content` has gained or lost a grant branch since m0136 — the
  m0162 body must be re-derived from the live definition, not from §0.1;
- `person_visibility_peers` has been redefined again (a version above m0151) —
  re-verify the symmetry argument in §1 of the architecture before UNIT 04;
- the Hasura `beacon` select permission no longer filters on `can_read_content`
  — the blast-radius analysis in UNIT 05 is then wrong;
- `Beacons` (Drift) already carries an `isDiscoverable` column;
- the Updates tab has already been folded or removed — UNIT 13 must then be
  re-scoped rather than executed;
- an owned file has unrelated local modifications a narrow edit cannot preserve.

A changed Git HEAD alone is not a blocker. Line-number drift is not a blocker.

Until implementation is authorized, this plan owns only:

```text
docs/plans/constellation-edge-semantics.md
docs/plans/constellation-implementation-plan.md
docs/plans/constellation-implementation-journal.md
docs/README.md
```

---

## 2. Executor contract

1. Units in manifest order. Complete one unit, run its Verify block, append the
   journal entry, make one focused local commit, then the next.
2. Preserve pre-existing modified/untracked files. Stage explicit paths only.
3. Create `docs/plans/constellation-implementation-journal.md` in UNIT 00.
4. If live code contradicts a frozen contract, stop that unit and record
   `BLOCKED` with the contradicting evidence.
5. **One hard gate remains: `GATE-14.1` (UNIT 02), blocking UNIT 05.** An executor
   *does* run UNIT 02 — it builds the fixture, takes the measurements, and writes
   them up. What an executor may not do is **choose the outcome**: the latency
   budget must be stated by a named owner *before* measuring, and the cache /
   no-cache decision and its `GATE-14.1: resolved (a|b)` line must carry that
   owner's name. Measurement is executable; the decision is not.
   `GATE-D1` (the path key ordering) is **resolved (A)** by an explicit
   architecture override — see §0.4 and §6.
6. **UNIT 02 and UNIT 01 are hard gates on UNIT 05.** Do not start UNIT 05 until
   both are `complete` and their decisions are written into this plan's §0 or the
   journal. UNIT 05 additionally requires an explicit human sign-off line in the
   journal (`SECURITY-REVIEW: <name/date>`), because it is an access-control
   change (D11, §8.3).
7. Do not "fix" a failing visibility assertion by editing the expectation. For
   each break, record in the journal whether it is (a) a genuine regression or
   (b) an assertion that encoded the old narrower rule, and why.
8. Run codegen after GraphQL/Freezed/Drift/AutoRoute/Injectable/`.arb` changes;
   never hand-edit generated output. A unit that changes routes, Freezed states,
   `.arb` copy or DI **must** run the matching generator in its own Verify block
   before its tests — a stale `*.gr.dart` / `*.freezed.dart` / `di.config.dart`
   fails in a way that looks like a test bug.
9. **Every line of a Verify block runs from the repository root, as its own
   command.** They are a checklist, not a shell script: consecutive
   `cd packages/server && …` lines only work from a fresh root each time
   (the second `cd packages/server` fails from inside `packages/server`, and
   `./scripts/check-custom-lints.sh` resolves from the root). If you paste a
   block into one shell, wrap each line in a subshell.

Journal entry template:

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
DECISIONS: <anything this unit resolved that §0 did not fix>
REMAINING: <specific work, or none>
```

---

## 3. Unit manifest

| Unit | Purpose | Arch ref | Depends on | Suggested commit |
|------|---------|----------|------------|------------------|
| 00 | Journal, baseline, docs index | — | — | `docs: start constellation implementation journal` |
| 01 | Visibility docs, evidence, **architecture amendments** | U0 / UX10 | 00 | `docs: reconcile beacon visibility current vs intended` |
| 02 | **Gate:** authorization cache + read-wall performance decision | §14.1 / §8.4 | 00 | `docs: decide constellation read-wall performance gate` |
| 03 | `beacon.is_discoverable` — m0160, Drift, mutations, Hasura | U1 | 01 | `feat(server): add per-request discoverability flag` |
| 04 | Symmetric `person_are_mutually_visible` — m0161 | U2 | 01 | `feat(server): make mutual visibility symmetric` |
| 04a | **Inserted by GATE-14.1 (b):** discoverability visibility cache | §14.1 (`constellation-read-wall-performance.md`) | 02, 04 | `feat(server): cache discoverability mutual-visibility checks` |
| 05 | Read-wall discoverability clause — m0162 | U3 | 01, 02, 03, 04, 04a | `feat(server): open active requests to the author's field` |
| 06 | `constellation_trust_edges` — m0163 | U4 | 04 | `feat(server): add two-tier constellation edge source` |
| 07 | `constellationField` V2 query | U5 | 03, 05, 06 | `feat(server): expose the constellation field query` |
| 08 | Client pure domain: paths, caps | U6 | 00 | `feat(client): resolve constellation paths` |
| 09 | Client pure domain: filters, density | U6 / UX4–5 | 08 | `feat(client): constellation filters and label budget` |
| 10 | Client pure domain: three-pass layout | U6 / §5.1 | 08 | `feat(client): three-pass constellation layout` |
| 11 | Client data: entities, gql, repository, use case | U7 | 07, 08 | `feat(client): fetch the constellation field` |
| 12 | Render: mode, nodes, edges, painters, legend | U8 | 09, 10, 11 | `feat(client): render the constellation map` |
| 13 | **Prerequisite project:** fold Updates into Inbox | U9a | 00 | `feat(client): fold updates into inbox` |
| 14 | Navigation slot, route, My Work entry | U9 / UX7 | 12, 13 | `feat(client): put constellation in the navigation` |
| 15 | Need labels, request preview, person panel | U10 / UX1–3 | 12 | `feat(client): actionable constellation previews` |
| 16 | Snapshot lifecycle + action-time validation, incl. server `expectedOfferKind` | U10a / UX8 | 15 | `feat: validate constellation actions at submit` |
| 17 | Filter bar, grouping, stable anchors | U10b / UX4–5 | 09, 15 | `feat(client): constellation filters and density` |
| 18 | Accessible Map/Text switch | U10c / UX6 | 17 | `feat(client): accessible constellation text view` |
| 19 | Author discoverability toggle + reach statement | U11 / §8.5 | 03 | `feat(client): author discoverability control` |
| 20 | Version bump, docs activation, UX acceptance | U12 / UX9–10 | all | `chore: release constellation client 7.2.0` |

Parallelizable: {08, 09, 10} after 08's contracts land; {13} alongside 03–07;
{19} after 03. Everything else is serial. UNIT 12 depends on 09 because
`ConstellationCubit` holds the filter state UNIT 09 defines.

---

## UNIT 00 — Journal, baseline, docs index

**Owns:** `docs/plans/constellation-implementation-journal.md` (new),
`docs/README.md`.

1. Record `git rev-parse HEAD`, branch, `git status --short`, migration tail
   (`ls packages/server/lib/data/database/migration/ | sort | tail -3`), client
   version, `web/index.html` `?v=`, `kDefaultMinClientVersion`, the live
   `beacon_can_read_content` migration number, and the live `GraphMode` values.
2. Copy the §3 manifest into the journal as unchecked items.
3. Record the architecture source and its UX-amendment date.
4. Add two rows to the `docs/README.md` plan index: the architecture doc and this
   plan.
5. Do not alter or stage any other pre-existing file.

**Acceptance:** journal exists; baseline either matches §1 or every difference is
recorded verbatim without guessing.

---

## UNIT 01 — Visibility documentation and evidence reconciliation

Implements **U0 / UX10**. Documentation and evidence only; changes no behaviour.
**Gate on UNIT 05.**

**Owns:** `CONTEXT.md`, `docs/Tentura_current_status_quo.md`,
`docs/plans/constellation-edge-semantics.md`, the journal.

1. Inspect the live functions and record, with migration numbers and file:line
   evidence, what is **implemented today**:
   - `beacon_can_read_content` grant branches (m0136);
   - `person_is_mutually_visible` (m0140), `person_visibility_peers` (m0151);
   - the Hasura `beacon` row filter and its exposed columns;
   - every server call site of `BeaconAccessGuard.canReadContent`
     (`grep -rn "canReadContent" packages/server/lib`) — the blast-radius list
     UNIT 05 will re-check.
2. In `CONTEXT.md` § *Beacon visibility & sharing*, split the paragraph into
   **Current contract** (what the code does now: author / forward edge / room
   participant / help offerer; MeritRank not a visibility gate) and **Target
   contract (not yet active)** stating D4/D11/D14 and naming the migration that
   activates it. Do not delete the current-contract text. Do not claim the new
   rule applies.
3. In `docs/Tentura_current_status_quo.md` §11, annotate the *"Discoverability is
   opt-out"* paragraph as **intended behaviour, not yet active**, with the same
   activation pointer.
4. In the architecture doc §10, replace the U0 instruction with a pointer to the
   journal's evidence record.
5. Confirm the four terms — direct trust, discoverability, forwarding, discussion
   admission — have one unambiguous meaning across all three documents. Record
   any collision found.
6. **Verify the architecture amendments are present** (they were applied on
   2026-09-08 and approved; see the header banner in
   `constellation-edge-semantics.md` and §6 of this plan). Confirm each is
   there and self-consistent, and record the confirmation in the journal. This is
   a **checklist, not an editing task**: if an item is present, tick it; if one is
   missing or was reverted, stop and record `BLOCKED` rather than re-authoring it,
   because a divergence means someone changed a normative document out of band and
   that needs a decision, not a patch. Confirm each of:
   - **O1** — §5 carries the layered DP, the hops-first key restricted to finite
     layers, the `depth(parent(p)) == depth(p) - 1` proof, and `(tier, id)` in D8;
     D1 and §12.1 state tier-1 preference as an **across-stages** rule (O1a: a
     holder explicable by explicit trust alone is never explained by a tier-2
     path, however much longer) — *not* the revision-6 "within-layer" wording,
     which O1a superseded;
   - **A2** — §12/U5 shows `constellationField` with no context argument;
   - **A3** — §5.1 carries the four narrowed stability clauses, not the absolute
     rule;
   - **N1** — §5's definition of **V** carries the symmetric single-source rule
     and the accepted enumeration gap;
   - **N2** — §5.2 distinguishes the transport guard rail from the client render
     budget and states the three disjoint holder-absence meanings;
   - **N3** — §12/U8 requires the provider-neutral seam before reuse;
   - **§14.2** contains items 6, 7 and 8;
   - **§8.3** — the wall clause shows all four conjuncts, `published_at IS NOT
     NULL` and `user_id IS NOT NULL` included;
   - **ALG identifiers (revision 11)** — §5's clauses carry `ALG-HOLDERS`,
     `ALG-DEDUP`, `ALG-STAGE1`, `ALG-STAGE2`, `ALG-PARENT`, `ALG-EGO`,
     `ALG-PRUNE`; `ALG-PARENT` carries the parent-candidate guard
     `q ∉ T OR depth1(q) = depth(p)-1` and the invariant proof cites it;
     `ALG-STAGE2` initialises `d2[ego][0] = 0` explicitly; **B** carries the
     publication conjunct; §5.2 holds the absence-semantics table; D11 is
     narrowed to content-wall parity.
   §14.2 items 6-8 now exist in the architecture, so the `[resolves 14.2/6-8]`
   markers in §0 are live references rather than proposals.

**Verify:** `bash scripts/check-user-facing-terminology.sh`

**Acceptance:** the three documents distinguish current from target; the
evidence record names migrations and call sites; nothing is described as shipped.

---

## UNIT 02 — Gate: authorization cache and read-wall performance

Implements **§14.1**, the one hard gate the architecture leaves open. This unit
produces a **decision plus measurements**, and may conclude "no cache". It does
not ship a cache by default.

**Owns:** `docs/plans/constellation-read-wall-performance.md` (new), the journal,
and a benchmark script under `scripts/`.

**This unit does not depend on UNITs 04/05, and must not.** It measures the
m0161/m0162 bodies by applying them **as ad-hoc SQL to its own disposable
fixture database** — copied verbatim from §0.1 — and never registers them in
`_migrations.dart`. m0162 references `beacon.is_discoverable`, and
`beacon_can_read_content` is `LANGUAGE sql` (`m0136.dart:7-43`) whose body is
validated at creation time, so the fixture must apply **m0160's DDL first** (also
ad hoc) or the `CREATE OR REPLACE` fails outright against the m0159 baseline.
Apply m0160 → m0161 → m0162 → m0163, in that order, to the fixture. That is what keeps the gate ahead of the change it gates
rather than circular with it. If the §0.1 bodies are later re-derived from live
code (per §1), re-run this unit's measurements before UNIT 05 proceeds.

1. Build a representative fixture database (disposable, `pg`-tagged harness) with
   at least: 5k users, a `vote_user` graph with mean out-degree ~4, a MeritRank
   publish covering it, 50k beacons, and one viewer whose `V` has ~200 members.
2. Measure **whole-query plans**, not the helper in isolation, for:
   - `SELECT … FROM beacon` under the Hasura row filter with the m0162 predicate,
     including **denied** rows (Hasura evaluates before dropping, so a render cap
     bounds nothing);
   - a My Work list, an Inbox list, a profile shared-request list, an
     `attention_intent` batch, and one image-metadata read;
   - the same set with MeritRank **unavailable** (stop the service) — record
     whether calls error, hang, or return empty, and what the wall then returns;
   - **the field's own SQL**, as §0.1 promises: `person_visible_peers_symmetric`
     alone for the ~200-member viewer; `constellation_trust_edges` (m0163) over
     `{ego} ∪` that peer set; and the **complete planned `constellationField`
     composition** — graph peers, edges, ego's requests, peers' discoverable
     requests with the UNIT 07 authorization predicates, profiles — run ad hoc in
     the order §0.2 fixes. These numbers are the baseline UNIT 07 records the real
     registered endpoint's timing against.
3. Record: p50/p95 latency and rows examined, before and after m0162, and the
   fraction of calls satisfied by the `person_reciprocal_explicit_trust`
   short-circuit. State explicitly that the short-circuit misses the multi-hop MR
   audience and therefore does not bound the worst case (R6).
4. **Decide, in writing, one of:**
   - **(a) No cache.** Permitted only if p95 on every measured query stays within
     the budget. **The budget is fixed: no measured query may add more than
     +150ms to its current p95.** It was set by the plan owner before any
     measurement was taken, which is the point — record the current p95 per query
     first, then the post-m0162 p95, and compare. Do not renegotiate the budget
     against the numbers you get.
   - **(b) Cache.** Then the document must specify, before UNIT 05 may start:
     freshness/expiry; **two** invalidators — the MeritRank publish epoch
     (`mr_bump_publish_epoch`, m0144) **and a direct-trust version counter**,
     because explicit-trust membership can change with no epoch bump and a cached
     positive would outlive its justification (R5); rebuild concurrency;
     behaviour when MeritRank is unavailable (fail **closed** for the
     discoverability branch — never fail open on an access-control predicate);
     and the fact that `block_hides` stays **outside** the cache.
5. If (b), add the cache as its own unit inserted between 04 and 05 and record it
   in the manifest. Do not fold it into UNIT 05.

**Acceptance:** the document states the budget, the measurements, the
MeritRank-unavailable behaviour, and one decision. The journal carries
`GATE-14.1: resolved (a|b)`. Without this line, UNIT 05 is `BLOCKED`.

---

## UNIT 03 — `beacon.is_discoverable`

Implements **U1 / D4 / D12**.

**Owns:**

```text
packages/server/lib/data/database/migration/m0160.dart                 new
packages/server/lib/data/database/migration/_migrations.dart           edit
packages/server/lib/data/database/table/beacons.dart                   edit
packages/server/lib/domain/use_case/beacon_case.dart                   edit
packages/server/lib/api/controllers/graphql/mutation/mutation_beacon.dart  edit
packages/server/lib/api/controllers/graphql/custom_types.dart          edit
packages/server/lib/domain/entity/beacon_entity.dart                   edit
packages/server/lib/domain/port/beacon_repository_port.dart            edit
packages/server/lib/data/repository/beacon_repository.dart             edit
packages/server/lib/data/repository/mock/beacon_repository_mock.dart   edit
hasura/metadata.json                                                   edit
packages/server/test/data/database/beacon_discoverability_pg_test.dart new
```

1. Write `m0160` exactly as §0.1. Register it in `_migrations.dart`.
2. Add to `Beacons`:
   ```dart
   /// Author opt-out for field discovery (D4). Backfilled true (D12).
   late final isDiscoverable = boolean().withDefault(const Constant(true))();
   ```
   Re-run server codegen.
3. Add an optional `isDiscoverable` argument to `beaconCreate`, `beaconUpdate`,
   and `beaconUpdateDraft`, following the existing `_draft` / `_primaryNeedSlug`
   pattern (nullable field, `containsKey` provided-flag where update semantics
   need "omitted ≠ false"). Thread it through `BeaconCase.create` / `.update` /
   `.updateDraft`. Omitted on create ⇒ `true`. Omitted on update ⇒ unchanged.
   The flag must survive the whole persistence path, so this step also carries
   `BeaconEntity`, `BeaconRepositoryPort`, `BeaconRepository` and
   `BeaconRepositoryMock` — a Drift column alone does not make the value
   readable or writable by the use case.
4. Add `isDiscoverable` to `gqlTypeBeacon` (non-nullable Boolean) — **camelCase**:
   the live type is camelCase throughout (`addressLabel`, `primaryNeedSlug`,
   `coverImageId`, `custom_types.dart:338-346`), and only the OAuth token type
   above it is snake_case. The Postgres column and the Hasura column stay
   `is_discoverable`; the V2 field name is the only camelCase one. Add
   `is_discoverable` to the Hasura `beacon` select-permission **columns** array in
   `hasura/metadata.json`.
   Do **not** add an update permission — the toggle goes through the V2 mutation,
   not through Hasura.
5. `beaconFork` copies the source row's `is_discoverable`. Child beacons created
   via `beacon_child_create_case` take the column default (`true`, D12) — verify
   and record which path applies.
6. Tests (`@Tags(['pg'])`): column exists, default true, backfill covered
   pre-existing rows including children, create/update round-trip both values,
   fork copies the flag.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/data/database/beacon_discoverability_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** the flag persists, defaults true, is backfilled true everywhere,
and is readable through Hasura. **No read behaviour changes yet** — nothing reads
the column until UNIT 05.

---

## UNIT 04 — Symmetric mutual visibility

Implements **U2 / D14 / R1**. Changes forward-candidate eligibility — review with
the forwarding owner and record their name in the journal.

**Owns:**

```text
packages/server/lib/data/database/migration/m0161.dart                 new
packages/server/lib/data/database/migration/_migrations.dart           edit
packages/server/lib/data/repository/forward_candidate_context_sql.dart edit
packages/server/lib/data/repository/forward_candidates_sql.dart        edit
packages/server/lib/data/repository/person_visibility_repository.dart  edit (send-time check)
packages/server/test/data/database/person_visibility_symmetry_pg_test.dart  new
packages/server/test/data/database/person_visibility_migration_pg_test.dart edit
packages/server/test/data/repository/person_visibility_repository_pg_test.dart new
```

1. Write `m0161` exactly as §0.1. Do **not** modify `person_is_mutually_visible`
   or `person_visibility_peers` — the wrapper is additive.
2. Tests (`@Tags(['pg'])`) over the asymmetric fixtures named in architecture §1:
   - explicit `V→A` plus MR `A→V` with no MR `V→A`:
     `person_is_mutually_visible(V,A) != person_is_mutually_visible(A,V)`
     (documents the old asymmetry) while
     `person_are_mutually_visible(V,A) == person_are_mutually_visible(A,V) == true`;
   - reciprocal explicit trust ⇒ true without any MR row present. Note this
     passes with or without the short-circuit branch — `person_visibility_peers`
     already returns `is_mutually_visible` for a reciprocal explicit pair
     (m0151), so branch 1 is a **performance** short-circuit, not a semantic one.
     To assert it is actually taken, compare plan/timing with MeritRank stopped,
     or record the hit rate from UNIT 02 (step 4) instead of claiming coverage;
   - `person_visible_peers_symmetric(v, '')` returns exactly
     `{ b : person_are_mutually_visible(v, b, '') }` restricted to v's candidate
     list, excludes self, and is empty for a blank/whitespace viewer;
   - one-directional explicit trust and no MR ⇒ false in both argument orders;
   - self ⇒ false; empty/whitespace/NULL id ⇒ false;
   - randomized property test: for 200 random ordered pairs drawn from the
     fixture, `f(a,b) == f(b,a)`.
3. **Switch the forward-candidate queries to the symmetric predicate, then
   re-baseline their suites.** This step is the widening the architecture promises
   (§8.3); without it nothing changes. `forward_candidate_context_sql.dart:20-29`
   currently calls `person_visibility_peers(viewer, ctx)` and filters on
   `peer.is_mutually_visible` — the **old ego-outbound projection** — so leaving
   it alone means eligibility is untouched and "re-baselining" would find nothing
   to re-baseline. Replace that `EXISTS` with
   `public.person_are_mutually_visible(p.viewer_id, p.candidate_id, p.normalized_context)`,
   keeping the existing self- and `block_hides` guards, and apply the same change
   to `forward_candidates_sql.dart`. Direct-send eligibility then widens by
   exactly the set symmetry repairs. For every changed expectation, record which
   repaired pair caused it.
   **Approved by the plan owner (2026-09-08):** the widening of direct-send
   eligibility is accepted as an intended consequence of D14, not a side effect to
   be minimised. What still belongs in the journal is *who verified the diff* —
   the SQL swap itself and the re-baselined expectations — not a re-litigation of
   whether to widen.
3a. **Move the send-time check too, or the widening is display-only.** The
   candidate lists are not the authorization path for the actual send:
   `ForwardCase` (`forward_case.dart:235`) authorizes recipients through
   `PersonVisibilityRepositoryPort.mutuallyVisiblePeerIds`, whose implementation
   (`person_visibility_repository.dart:33`) still filters the old projection's
   `is_mutually_visible`. Left alone, a symmetry-repaired pair displays as
   eligible in step 3 and then fails when sending. Replace that query with a
   bounded check over the supplied recipients:
   ```sql
   SELECT DISTINCT c.peer_id
   FROM unnest($3::text[]) AS c(peer_id)
   WHERE c.peer_id <> $1
     AND public.person_are_mutually_visible($1, c.peer_id, $2)
     AND NOT public.block_hides($1, c.peer_id)
   ```
   (`$1` viewer, `$2` context, `$3` candidates — the existing variable order.)
   Add `person_visibility_repository_pg_test.dart` (`@Tags(['pg'])`) using the
   **real** repository against the explicit `V→A` / reverse-only-MR fixture from
   step 2: `mutuallyVisiblePeerIds(V, [A])` returns `{A}`, a blocked pair returns
   nothing, and — exercised **through `ForwardCase`** with the real visibility
   port (other ports may be mocked) — a forward from `V` to `A` succeeds rather
   than throwing. Mocked candidate eligibility alone does not prove the send.
4. Record the short-circuit hit rate from UNIT 02's fixture in the journal.

**Verify:**

```bash
cd packages/server && dart test -t pg -j 1 test/data/database/ \
  test/data/repository/forward_candidate_context_repository_pg_test.dart \
  test/data/repository/person_visibility_repository_pg_test.dart
cd packages/server && dart test \
  test/domain/use_case/forward_case_auth_test.dart \
  test/data/repository/forward_candidate_context_sql_test.dart \
  test/data/repository/forward_candidates_sql_test.dart \
  test/api/controllers/graphql/query_forward_candidate_context_test.dart \
  test/api/controllers/graphql/query_forward_candidates_test.dart
```

The forward-candidate suites live under `test/data/repository/` and
`test/api/controllers/graphql/`, **not** `test/data/database/` — running only the
latter would re-baseline nothing (step 3 is the point of this unit).

**Acceptance:** symmetry holds on every fixture; no existing suite is silenced;
each widened forward-candidate expectation is explained in the journal; a
repaired pair that displays as eligible can actually be sent to.

---

## UNIT 04a — Discoverability visibility cache

**Inserted by `GATE-14.1: resolved (b)`** — see
[`constellation-read-wall-performance.md`](constellation-read-wall-performance.md)
for the measurements that forced this outcome (4 of 6 representative queries
exceeded the +150ms budget by more than 30×, one by an observed 16m42s before
the benchmark itself was bounded) and the full cache specification this unit
implements verbatim. Do not re-derive the spec here; that document is
normative for this unit the same way §0 is normative for the rest of the plan.
Gate on UNIT 05 exactly like UNIT 02 and UNIT 01 (plan §2 rule 6): UNIT 05 must
not start until this unit is `complete`.

**Owns:**

```text
packages/server/lib/data/database/migration/m0163a.dart                new
packages/server/lib/data/database/migration/_migrations.dart           edit
packages/server/test/data/database/discoverability_visibility_cache_pg_test.dart new
```

(Migration numbered `m0163a` — after m0163, the last migration §0.1 fixes — so
this insertion does not renumber anything else in §0.1. Re-read §1's stop
condition before picking the number: if a migration above m0159 already exists
by execution time, renumber into the free range instead of colliding, exactly
as §1 already instructs for the rest of this plan.)

1. **Cache table**, keyed on the normalized unordered pair (per the
   performance doc's "What is cached" section — sort the two ids before
   storing/looking up, so `(a,b)` and `(b,a)` share one row):
   ```sql
   CREATE TABLE IF NOT EXISTS public.person_mutual_visibility_cache (
     person_lo        text NOT NULL,
     person_hi        text NOT NULL,
     ctx              text NOT NULL,
     is_mutually_visible boolean NOT NULL,
     mr_epoch         bigint NOT NULL,
     trust_version    bigint NOT NULL,
     computed_at      timestamptz NOT NULL DEFAULT now(),
     PRIMARY KEY (person_lo, person_hi, ctx)
   );
   ```
2. **Direct-trust version counter** (the second invalidator the performance
   doc requires — `mr_bump_publish_epoch()` already exists as the first):
   a sequence plus a trigger function bumped on every `vote_user` write:
   ```sql
   CREATE SEQUENCE IF NOT EXISTS public.direct_trust_version_seq;
   CREATE OR REPLACE FUNCTION public.direct_trust_current_version()
     RETURNS bigint LANGUAGE sql STABLE AS $$
       SELECT last_value FROM public.direct_trust_version_seq;
   $$;
   CREATE OR REPLACE FUNCTION public.bump_direct_trust_version()
     RETURNS trigger LANGUAGE plpgsql AS $$
     BEGIN
       PERFORM nextval('public.direct_trust_version_seq');
       RETURN NULL;
     END;
   $$;
   CREATE TRIGGER vote_user_bump_direct_trust_version
     AFTER INSERT OR UPDATE OR DELETE ON public.vote_user
     FOR EACH STATEMENT EXECUTE FUNCTION public.bump_direct_trust_version();
   ```
   (Statement-level, not row-level — one bump per statement regardless of how
   many rows it touched is sufficient; this is a coarse invalidator, not a
   per-row diff.)
3. **Wrapping function**, replacing the direct call m0162 makes. `m0162`
   (already landed as of this unit, per the manifest order — UNIT 05 runs
   after this one) calls `person_are_mutually_visible` directly today; this
   unit does not touch m0162's SQL text (that would mean re-registering an
   already-shipped migration), it defines the cache-aware wrapper for UNIT 05
   to call instead when UNIT 05's branch is written:
   ```sql
   CREATE OR REPLACE FUNCTION public.person_are_mutually_visible_cached(
     a_id text, b_id text, ctx text
   ) RETURNS boolean LANGUAGE plpgsql AS $$
   DECLARE
     _lo text := LEAST(a_id, b_id);
     _hi text := GREATEST(a_id, b_id);
     _ctx text := coalesce(ctx, '');
     _cur_epoch bigint;
     _cur_trust bigint;
     _row public.person_mutual_visibility_cache;
     _result boolean;
   BEGIN
     _cur_epoch := public.mr_current_publish_epoch();   -- confirm exact accessor name against m0144 before implementing; re-derive if it differs
     _cur_trust := public.direct_trust_current_version();
     SELECT * INTO _row FROM public.person_mutual_visibility_cache
       WHERE person_lo = _lo AND person_hi = _hi AND ctx = _ctx
       AND mr_epoch = _cur_epoch AND trust_version = _cur_trust
       AND computed_at > now() - interval '60 seconds';
     IF FOUND THEN
       RETURN _row.is_mutually_visible;
     END IF;
     -- Miss: single-flight via row-level lock on a per-key advisory lock,
     -- so concurrent misses on the same pair rebuild once, not N times.
     PERFORM pg_advisory_xact_lock(hashtext(_lo || ':' || _hi || ':' || _ctx));
     -- Re-check after acquiring the lock: another backend may have just
     -- finished the rebuild we were about to duplicate.
     SELECT * INTO _row FROM public.person_mutual_visibility_cache
       WHERE person_lo = _lo AND person_hi = _hi AND ctx = _ctx
       AND mr_epoch = _cur_epoch AND trust_version = _cur_trust
       AND computed_at > now() - interval '60 seconds';
     IF FOUND THEN
       RETURN _row.is_mutually_visible;
     END IF;
     BEGIN
       _result := public.person_are_mutually_visible(a_id, b_id, _ctx);
     EXCEPTION WHEN OTHERS THEN
       -- Fail CLOSED, per the performance doc: never cache, never propagate,
       -- never serve a stale positive through an outage.
       RETURN false;
     END;
     INSERT INTO public.person_mutual_visibility_cache
       (person_lo, person_hi, ctx, is_mutually_visible, mr_epoch, trust_version, computed_at)
     VALUES (_lo, _hi, _ctx, _result, _cur_epoch, _cur_trust, now())
     ON CONFLICT (person_lo, person_hi, ctx) DO UPDATE SET
       is_mutually_visible = EXCLUDED.is_mutually_visible,
       mr_epoch = EXCLUDED.mr_epoch,
       trust_version = EXCLUDED.trust_version,
       computed_at = EXCLUDED.computed_at;
     RETURN _result;
   END;
   $$;
   ```
   **Verify the exact name of m0144's epoch-reading accessor** (this sketch
   guesses `mr_current_publish_epoch()`; if m0144 only exposes the bump
   function and stores the epoch in a plain table/sequence, read from that
   directly) — re-derive against the live m0144 body rather than trusting this
   guess, the same way every other unit re-derives against live code.
   `block_hides` is not referenced here at all — it stays outside the cache
   entirely, exactly as the performance doc requires, by never being part of
   what this function memoizes.
4. Tests (`@Tags(['pg'])`):
   - a cache miss computes and stores a row; a subsequent call with the same
     inputs and no intervening writes is a hit (assert via a spy/counter on
     calls to the uncached `person_are_mutually_visible`, or by timing);
   - bumping `mr_bump_publish_epoch()` invalidates every existing entry;
   - an insert/update/delete on `vote_user` invalidates every existing entry
     (the trigger is statement-level, so assert this holds for both a single
     row change and a batch);
   - a TTL-expired entry (mock `computed_at` into the past, or use a short TTL
     for the test) is treated as a miss even with both versions unchanged;
   - `(a,b)` and `(b,a)` share one cache row (normalized-pair key);
   - concurrent misses on the same key: two simultaneous callers rebuild once,
     not twice — assert via a call-counter on the underlying function under
     concurrent connections;
   - **MeritRank unavailable ⇒ fail closed:** with the `meritrank` container
     stopped (or the underlying call mocked to raise), a miss resolves to
     `false`, writes nothing to the cache table (or writes a
     non-authoritative miss marker your implementation prefers, but never a
     cached `true`), and does not raise past this function — assert no
     exception escapes and the boolean result is `false`;
   - `block_hides` is never referenced by this function or its cache table —
     grep the migration body in the test to assert the string never appears,
     so this invariant cannot silently regress later.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/data/database/discoverability_visibility_cache_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** every property in the performance doc's cache specification
holds under test — TTL, both invalidators, single-flight rebuild, fail-closed
on MeritRank failure, `block_hides` excluded — and UNIT 05 can call
`person_are_mutually_visible_cached` in place of the direct call without
changing anything else about its branch.

---

## UNIT 05 — Read-wall discoverability clause

Implements **U3 / D4 / D11 / §8.3**. **This is an access-control change.**
Requires `GATE-14.1: resolved` and a `SECURITY-REVIEW:` line in the journal.

**Owns:**

```text
packages/server/lib/data/database/migration/m0162.dart                 new
packages/server/lib/data/database/migration/_migrations.dart           edit
packages/server/lib/domain/beacon_visibility.dart                      edit
packages/server/test/domain/beacon_visibility_test.dart                edit (constructs facts)
packages/server/test/domain/beacon_hierarchy_policy_test.dart          edit (constructs facts)
packages/server/test/data/repository/beacon_access_sql_parity_test.dart      edit
packages/server/test/data/repository/inbox_beacon_visibility_hasura_test.dart edit
packages/server/test/data/repository/user_block_adversarial_pg_test.dart      edit
```

1. Re-read the **live** `beacon_can_read_content` body. Copy it into `m0162`
   verbatim and insert only the branch in §0.1. If the live body differs from
   m0136, stop and record `BLOCKED` per §1.
2. Mirror the clause in the Dart policy so the parity test can hold.
   **Know what you are editing:** `BeaconVisibility.canReadContent` is **not** on
   the runtime path. `BeaconAccessRepository.canReadContent`
   (`data/repository/beacon_access_repository.dart:14-18`) calls the SQL
   predicate directly via `_callPredicate`, and no production code constructs
   `BeaconContentVisibilityFacts` — the only non-test occurrence is the
   constructor itself. The Dart policy is a **specification mirror exercised
   solely by tests**, which is exactly why the parity suite is load-bearing: it
   is the only thing keeping the two definitions in sync. Add the field, update
   the fact constructions in the test files this unit owns, and do not go looking
   for a production assembly site — there isn't one.
   The SQL branch has **four** conjuncts plus the visibility call; the Dart
   expression must have all of them or parity is false by construction:
   - add `isDiscoverable`, `isPublished` and `isMutuallyVisibleWithAuthor` to
     `BeaconContentVisibilityFacts`. `isPublished` mirrors
     `published_at IS NOT NULL` and has **no** existing counterpart — the class
     (`beacon_visibility.dart:4-18`) carries only `status`, `isAuthor`,
     `hasActiveForwardEdgeAsRecipient`, `isRoomAdmittedOrSteward`,
     `isActiveHelpOfferer`;
   - in `BeaconVisibility.canReadContent`, add
     `|| (facts.isDiscoverable && facts.isPublished && facts.status.isOpenFamily && facts.isMutuallyVisibleWithAuthor)`
     — `BeaconStatus.openFamilyValues` is `{0, 7, 8}`
     (`lib/domain/entity/beacon_status.dart:16`, the **repo-root** shared
     package, not `packages/server/lib`), which matches D10 exactly; re-verify
     before reusing the getter and spell the set out if it has drifted;
   - the SQL's `b.user_id IS NOT NULL` guard (m0157 erasure tombstones) needs no
     Dart field: `isAuthor` and the caller's fact assembly already require a
     resolved author. Record that reasoning in the journal — if a tombstoned row
     can ever reach `canReadContent` with an author-less beacon, add the fact
     rather than assuming;
   - update the docstring: it currently asserts "MeritRank and vote-mutual
     friendship are not part of this predicate", which this unit makes false.
   - `canReadInvolvement` is **unchanged** — discovery must not widen the
     involvement wall. D11 as narrowed (architecture §2) grants discovery-only
     viewers the **content** wall and the operation-gated actions, not
     `can_read_involvement`: m0124 (`m0124.dart:45-76`) grants involvement to an
     active forward recipient, and that difference between a forwarded recipient
     and a discovery-only viewer is preserved, not parity.
3. **Fix the parity fixture before asserting anything.**
   `beacon_access_sql_parity_test.dart:105-112` inserts
   `(id, user_id, title, description, status, created_at, updated_at)` and
   **never sets `published_at`**, so every fixture beacon has
   `published_at IS NULL` — including the `BeaconStatus.open` rows at ~:166,
   :197, :263, :317, :375 and :424. The moment m0162 lands, those rows are
   SQL-deny / Dart-allow and the parity suite fails. Add `published_at` to
   `insertBeacon` (parameterised, defaulting to a fixed non-null timestamp) and
   add one explicit case for an open-but-unpublished row that **both** sides
   deny. This is a fixture that never modelled the column, not an expectation
   that encoded the old rule — record it in the journal under §2/7 with that
   distinction.
4. Extend the three named suites to assert the **new** wall:
   - discoverable + active + mutually visible ⇒ read allowed;
   - opt-out ⇒ denied; draft / review-open / closed / cancelled / deleted ⇒
     denied (exercise every status, D10);
   - block in **either** direction ⇒ denied, and denial survives the new branch
     (`block_hides` stays first);
   - a peer visible only through the repaired symmetry direction ⇒ allowed;
   - Hasura row-filter parity: the same beacon set appears through the Hasura
     `beacon` query as through the SQL predicate.
5. Walk the blast-radius list from UNIT 01 and record, per call site, the
   expected behaviour change: `beacon_display_case`, `forward_band_case`,
   `forward_case`, `help_offer_case`, `invitation_case`, `coordination_case`,
   `beacon_child_create_case`, `attention_intent_case`,
   `person_capability_event_repository`, `beacon_lineage_visibility`,
   `beacon_can_read_linked_detail` (m0155), and the Hasura row filter. **D11 is
   deliberate and was re-confirmed by the plan owner (2026-09-08):** discovery
   confers the same **content-wall** reads as a forwarded recipient and permits
   `offerHelp`, `forward`, invitation, and `fork` subject to their existing
   operation-specific checks — not `can_read_involvement`, not discussion
   admission. Do not add a new gate; do record each site you checked, and record
   for `coordination_case` that `helpOffersWithCoordination` already gates on
   content access with admission fields redacted (§0.3) and is unchanged.
   The `SECURITY-REVIEW:` line therefore covers **implementation correctness** —
   that the branch is placed where §0.1 says, that `block_hides` still precedes
   it, that no call site widens further than D11 intends — and **not** whether
   D11 was the right call. That question is closed; do not reopen it in review.
6. Note in the journal, as an accepted property rather than a defect (R7/R8):
   actions taken while discoverable outlive discoverability, and already-served
   image URLs are not revocable by tightening SQL.

**Verify:**

```bash
cd packages/server && dart test \
  test/domain/beacon_visibility_test.dart \
  test/domain/beacon_hierarchy_policy_test.dart
cd packages/server && dart test -t pg -j 1 \
  test/data/repository/beacon_access_sql_parity_test.dart \
  test/data/repository/inbox_beacon_visibility_hasura_test.dart \
  test/data/repository/user_block_adversarial_pg_test.dart
cd packages/server && dart test -t pg -j 1
./scripts/check-custom-lints.sh packages/server
```

The first line is not optional: `beacon_visibility_test.dart` and
`beacon_hierarchy_policy_test.dart` are **untagged**, so the `-t pg` commands
never run them and the Dart mirror's fact constructions would go unexercised.

**Acceptance:** SQL ↔ Dart parity holds with the new branch; every previously
passing case either still passes or has a recorded, justified change; the journal
carries `SECURITY-REVIEW:` and the per-call-site walk.

---

## UNIT 06 — `constellation_trust_edges`

Implements **U4 / D1 / D6 / §9.1**.

**Owns:**

```text
packages/server/lib/data/database/migration/m0163.dart                 new
packages/server/lib/data/database/migration/_migrations.dart           edit
packages/server/test/data/database/constellation_trust_edges_pg_test.dart new
```

1. Write `m0163` exactly as §0.1.
2. Tests (`@Tags(['pg'])`):
   - **containment:** an edge whose endpoint is outside `{ego} ∪ V` is never
     returned, even when both ids are passed in `node_ids`;
   - **tier preference:** a pair present in both `vote_user` and
     `user_trust_edge` is returned once, `tier = 1`;
   - **positive only:** `amount <= 0` and `prev_sent_weight <= 0` never appear;
   - **viewer blocks:** an edge touching a peer the *viewer* blocks, or who
     blocks the viewer, is absent — `block_hides` is symmetric in its arguments
     (m0135), so the one `allowed` call covers both directions of that pair;
   - **peer↔peer blocks (distinct case, do not merge with the above):** peers A
     and B are both visible to ego and neither is blocked by ego, but A blocks B.
     Neither the tier-1 nor the tier-2 A→B edge may be returned. Assert tier 1
     explicitly: m0137 zeroes `prev_sent_weight` on withdrawal, so a tier-2-only
     test passes for the wrong reason while `vote_user` still carries the pair;
   - **wire hygiene:** the returned column set is exactly `{src, dst, tier}`;
   - **empty viewer / empty array** ⇒ empty result, no error.

**Verify:** `cd packages/server && dart test -t pg -j 1 test/data/database/constellation_trust_edges_pg_test.dart`

**Acceptance:** no weight or score column exists on the function; endpoint
containment is enforced inside the function, not by its caller.

---

## UNIT 07 — `constellationField` V2 query

Implements **U5 / D13 / D15 / D16 / §9.1**.

**Owns:**

```text
packages/server/lib/consts/constellation_consts.dart                              new
packages/server/lib/domain/entity/constellation_field.dart                        new
packages/server/lib/domain/port/constellation_field_repository_port.dart          new
packages/server/lib/data/repository/constellation_field_repository.dart           new
packages/server/lib/domain/use_case/constellation_field_case.dart                 new
packages/server/lib/api/controllers/graphql/query/query_constellation_field.dart  new
packages/server/lib/api/controllers/graphql/query/_queries_all.dart               edit
packages/server/lib/api/controllers/graphql/custom_types.dart                     edit
packages/server/lib/api/controllers/graphql/mappers/constellation_gql_maps.dart   new
packages/server/test/domain/use_case/constellation_field_case_test.dart           new
packages/server/test/data/repository/constellation_field_repository_pg_test.dart  new
```

1. Entities and port per §0.2. Repository queries, in order:
   - **peers:** `person_visible_peers_symmetric(viewerId, ctx)` — the **same**
     symmetric predicate the read wall uses (D14). Do **not** use
     `person_visibility_peers`: it is ego-outbound and asymmetric (m0151), which
     would let a request pass the wall while its author is absent from the field.
     Minus `block_hides` in either direction, ascending id, limit
     `kConstellationPeerCap + 1`. **The peer cap is a guard rail, not a
     selection.** An id-ordered prefix cannot preserve paths — the server has not
     resolved any — so on overflow the architecture (§5.2, **N2**) accepts the
     truncation and degrades ring semantics to *path not shown* rather than
     pretending the prefix selected anything. Path-preserving truncation happens
     **only** client-side, inside `resolveAndCapConstellation`, which has the
     resolution to preserve paths with. So, exactly:

     | | under the cap | overflow (`cap + 1` rows came back) |
     |---|---|---|
     | graph peer set | the full symmetric peer set | the **first `kConstellationPeerCap` by id** — call it `P` |
     | `edges` | for the full peer set | **for `P` only** |
     | peer `requests` | from the full peer set | **from the full symmetric peer set, unchanged** |
     | `peers` | the full symmetric peer set | `P` ∪ **every author of a returned request** |
     | ego `requests` | present | present (D16 is unconditional) |
     | `peersCapped` | `false` | `true` |
     | `requestsCapped` | per the peer-request query | per the peer-request query |

     **The peer cap bounds the graph, not the content.** Edges are the quadratic
     term and the actual reason this cap exists; requests are linear and bounded
     separately by `kConstellationRequestCap`. So peer overflow truncates
     `edges` — and therefore which holders can be *explained* — while the request
     query runs over the whole symmetric peer set exactly as it always does.
     What peer overflow omits is the **path**, not the request, which is what
     lets UNIT 18's same-snapshot fallback recover the content.
     **Say "path", not "request", in the copy.** The frozen l10n string is
     `constellationPathOmittedByCap` — *"Some connection paths are not shown"*.
     A *"some requests are hidden"* notice would be false under this shape.
     **The request set is still not "complete" in the absolute sense:** its own
     cap applies independently, and when `requestsCapped` is true some requests
     genuinely were not returned and the fallback list cannot recover those. The
     two caps are independent and both may be set;
     `peers` must therefore include request authors outside `P` (bounded by
     `kConstellationPeerCap + kConstellationRequestCap`), or the list cannot
     render a name. Those authors have no edges, so path resolution places them
     in `ring` — correctly: their path is genuinely not available;
   - **ego's own requests, as their own query:** `user_id = viewerId AND
     status IN (0,7,8) AND published_at IS NOT NULL`, ascending id, **no
     `is_discoverable` filter and no share of the request cap**. D16 says ego's
     own are always shown, and a single `(user_id, id)`-ordered query with a
     global limit cannot honour that — ego's requests vanish whenever ego's
     `user_id` sorts late enough;
   - **peers' requests:** beacons authored by the peer set (**excluding ego**)
     with `is_discoverable AND status IN (0,7,8) AND published_at IS NOT NULL`
     **and, in the same `WHERE`, its own authorization predicate**:
     ```sql
     AND NOT public.block_hides(viewer_id, b.user_id)
     AND public.beacon_can_read_content(b.id, viewer_id)
     ```
     applied **before** the limit and before `requestsCapped` is set. This query
     is deliberately independent of the graph peer query, so the graph query's
     block filter cannot protect it — `person_visible_peers_symmetric` (§0.1)
     filters no blocks, and a blocked author outside the graph prefix would
     otherwise arrive through the request path alone. Ascending `(user_id, id)`,
     limit `kConstellationRequestCap + 1`. `requestsCapped` reflects this query
     only. Per-request viewer booleans come from the same rows the read wall
     already authorizes (`beacon_forward_edge`, `beacon_participant`,
     `beacon_help_offer`);
   - **edges:** `constellation_trust_edges(viewerId, ctx, {ego} ∪ graphPeerIds)`
     — **`graphPeerIds` only**, never the wider `peers` profile set. The full
     closure among those peers is returned (D13); pruning is the client's job.
     Note `peers` may exceed `kConstellationPeerCap` (it adds request authors, so
     it is bounded by `kConstellationPeerCap + kConstellationRequestCap`); nothing
     may assume `|peers| ≤ kConstellationPeerCap`. **The graph subset is
     server-only**: the wire (§0.3) carries the merged `peers` and `edges`, so the
     client passes **all returned peer-profile ids** as `visiblePeerIds` and must
     not infer graph membership from edge incidence. The server-side graph subset
     controls which edges are returned; an author outside it has no edges by
     construction and resolves into `ring`, and request authors without returned
     paths remain eligible ring holders with their copy governed by `peersCapped`
     (architecture §5.2 table);
   - **profiles:** reuse `UserProfileBatchLookup` for display name / handle /
     image, exactly as `ForwardCandidatesCase` does — but **do not** populate
     `scoresByPeerId`.
2. Use case: assemble the snapshot, stamp `loadedAt = DateTime.now().toUtc()`
   (D15 — the field is explicitly a snapshot), return empty for a blank viewer.
3. GraphQL types and resolver per §0.3, following
   `QueryForwardCandidateContext` for shape and `custom_types.dart` for field
   construction. Register in `_queries_all.dart`. The resolver takes **no**
   context argument and passes `kConstellationContext = ''` (§0.3); an
   unauthenticated viewer is rejected exactly as the neighbouring V2 queries
   reject one.
4. Tests:
   - unit: caps set the `*Capped` flags; ego's own non-discoverable active
     request is present; a peer's non-discoverable request is absent; a closed /
     draft / cancelled request is absent (all of D10); an **open-but-unpublished**
     request (`published_at IS NULL`) is absent — publication is a conjunct of
     **B** (architecture §5), not only of the wall;
   - **blocked author outside the graph prefix** (`pg`, both block directions):
     with `kConstellationPeerCap + 1` visible peers and an author `x` whose id
     sorts after the prefix, where `x` blocks the viewer in one case and the
     viewer blocks `x` in the other, neither `x`'s request nor an `x` profile
     introduced solely by that request is returned;
   - **wire hygiene:** serialize a fully populated snapshot to JSON and assert no
     key matches `/score|weight|_mr$|meritrank|rank/i`, recursively;
   - **containment:** no edge endpoint and no request author lies outside
     `{ego} ∪ V`;
   - **ego requests survive the cap:** with `kConstellationRequestCap` peer
     requests whose author ids all sort **before** ego's, ego's own requests are
     still present (this is the regression the split query exists to prevent);
   - **overflow shape, pinned exactly:** with `kConstellationPeerCap + 1`
     visible peers, assert `peersCapped == true`, **exactly
     `kConstellationPeerCap`** peers in the graph set, every `edges` endpoint
     inside that set, **requests still drawn from the whole peer set**, and every
     returned request's author present in `peers`. Asserting only the flag would
     let an empty-payload implementation pass;
   - **registration and auth:** `constellationField` is reachable through the
     registered V2 query set (`_queries_all.dart`), rejects a blank/absent
     viewer, and exposes no `context` argument in the built schema;
   - `pg`: repository ordering is stable under shuffled fixture insert order.
5. Record in the journal the registered endpoint's whole-call timing on UNIT 02's
   fixture, against the ad-hoc composition numbers UNIT 02 step 2 produced.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test test/domain/use_case/constellation_field_case_test.dart
cd packages/server && dart test -t pg -j 1 test/data/repository/constellation_field_repository_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** the query returns peers, both edge tiers tagged and weight-free,
and requests; the wire-hygiene test passes; caps are reported, not silently
applied.

---

## UNIT 08 — Client pure domain: paths and caps

Implements **U6 / D1 / D2 / D3 / D6 / D7 / D8 / D9 / R11 / §5.2**.

**Owns:**

```text
packages/client/lib/features/constellation/domain/constellation_path_resolution.dart  new
packages/client/lib/features/constellation/domain/constellation_cap_policy.dart       new
packages/client/lib/features/constellation/domain/constellation_consts.dart           new
packages/client/test/features/constellation/constellation_path_resolution_test.dart   new
packages/client/test/features/constellation/constellation_cap_policy_test.dart        new
```

1. `GATE-D1` is **resolved (A)** — the key is `(hops, derived)`, hops first
   (architecture §5 / O1b; §0.4 binds it). The tests below are written against
   that key.
   Implement the signatures in §0.4 exactly: `resolveConstellationPaths`
   **two-stage** (tier-1 BFS → constrained `d2[p][h]` table → keys → parents), and
   `resolveAndCapConstellation` as the single entry point that resolves on the
   full peer set before truncating. There is no standalone `selectCappedPeers`.
   Pure Dart: no Flutter import, no `dart:ui`, no entity dependency — records and
   collections only.
2. Tests, table-driven. Names are the ones §0.4's binding table cites, each
   tagged with the §5 clause it pins:
   - **tier 1 wins across stages, however much longer** `[ALG-STAGE1]` (O1a):
     `ego→a (t1), a→b (t1), b→h (t1)` plus `ego→h (t2)`. `h` is reached by stage
     1, so `depth(h) == 3`, `derived(h) == 0`, and the 1-hop tier-2 edge is
     **not** used. This is the test that pins the disclosure bound — if it passes
     with `depth(h) == 1` the stages have been collapsed;
   - **hops first inside stage 2 / `derived` is per-layer** `[ALG-STAGE2]`:
     tier-2 `ego→a`, `a→h`, `ego→b`; tier-1 `b→c`, `c→h`. Stage 1 reaches
     nothing (`T` is empty — ego's only tier-1 out-edges do not exist), so `h`
     is a stage-2 node with a 2-hop path of derived count 2 and a 3-hop path of
     derived count 1. Assert `depth(h) == 2` **and `derived(h) == 2`**: the
     shorter path with **more** derived edges wins, and the three-hop path's
     derived count of 1 must not be borrowed by the two-hop result. (An earlier
     revision's fixture put the person in `T` and demanded `(2, 1)`, contradicting
     O1a — a stage-1 node has `derived == 0` by construction.) Separately, among
     **equal-length** stage-2 paths the one with fewer tier-2 edges wins: tier-2
     `ego→a`, `ego→b`, `a→h`; tier-1 `b→h` — `derived(h) == 1`, `parent(h) == b`;
   - **unreachable first layer, reachable second** `[ALG-STAGE2]` — the
     finiteness regression: tier-2 `ego→a`, tier-1 `a→p`, no `ego→p` edge.
     `d2[p][1] = ∞`, `d2[p][2] = 1`; assert `depth(p) == 2`, `derived(p) == 1`.
     A lex-min over all layers would hand `p` depth 1 with an infinite count;
   - **stage-1 nodes carry `derived == 0`** `[ALG-STAGE1]`: every `p ∈ T` has
     `derived(p) == 0` by construction, whatever tier-2 edges also touch it;
   - **stage-2 constraint costs reachability, deliberately** `[ALG-STAGE2]`:
     build a holder whose only route needs a `T` node at a shorter ring than its
     `depth1`; assert the holder lands in `ring`, **not** that it is drawn through
     a two-ring parent edge;
   - **min-id parent, not first discovery** `[ALG-PARENT]` — use the
     architecture's own counterexample `ego→a,b; a→z; b→c; z→h; c→h`:
     parent(`h`) is `c`, not `z`;
   - **tier beats id in the parent tie-break** `[ALG-PARENT]`: `ego→q2 (t1)`,
     `ego→q1 (t2)`, `q1→p (t1)`, `q2→p (t2)` — `q2 = (1,0)`, `q1 = (1,1)`, and
     both predecessors realize `key(p) = (2,1)` (hops first).
     `parentTier(p)` must be **1** even when `q2`'s id sorts first. (Ordering by
     id alone picks the tier-2 edge; that is the bug this test pins.)
   - **illegal parent rejected** `[ALG-PARENT]` — §5's counterexample for the
     parent-candidate guard: tier-1 `ego→a, a→b, b→q, q→p, r→p`; tier-2
     `ego→q, ego→r`; ids `q < r`; all visible; `p` a holder. `depth1(q) == 3`,
     `p ∉ T`, `p` reached at `(2, 1)` through `r` only. Assert `parent(p) == r`,
     `parentTier(p) == 1`, and `depth(parent(p)) == depth(p) - 1`. Without the
     guard `d2[q][1] + 0 == derived(p)` admits `q`, and id order picks it — a
     depth-3 parent for a depth-2 child. **This guard was lost once** when a
     duplicate statement of the algorithm was deleted; this test is what makes
     that loss fail loudly;
   - **parent is always exactly one ring in** `[ALG-PARENT]`: assert
     `depth(parent(p)) == depth(p) - 1` for **every** reached `p`, over a
     randomized fixture mixing both tiers and both stages. UNIT 10's
     sibling-sector model depends on this invariant;
   - **duplicate pair, tier 1 wins** `[ALG-DEDUP]`: visible peers `{a, b}`,
     holder `b`, edges `ego→a (t1)`, `a→b (t1)`, and `a→b (t2)`. Across every
     input ordering, assert `depth(b) == 2`, `derived(b) == 0`,
     `parent(b) == a`, and `parentTier(b) == 1`;
   - **ego is excluded** `[ALG-EGO]`: with ego in `holderIds` and an edge
     `a→ego (t1)` present, ego appears in none of `depth`, `derived`, `parent`,
     `parentTier`, `attributed`, `keep`, or `ring`;
   - **ego-only field** `[ALG-EGO]`: `visiblePeerIds` empty, `holderIds == {ego}`,
     no edges — every returned set and map is empty and nothing throws; the
     field is ego and ego's own satellites;
   - **no order dependence in the table** `[ALG-STAGE2]`: tier-2 edges `ego→a`
     and `ego→c`; tier-1 edges `a→b`, `b→x`, and `c→x`; holder `x`; all
     endpoints authorized. Stage 1 reaches no peer, so the result comes from the
     stage-2 table. Across all 120 edge permutations, assert `depth(x) == 2`,
     `derived(x) == 1`, and `parent(x) == c` — the case a settle-once 0-1 BFS
     deque gets wrong;
   - **depth cap:** a holder at 4 hops falls into `ring`, not `attributed`;
   - **direction:** `a→ego` alone does not put `a` in the tree (D7);
   - **containment:** accept edges only when both endpoints belong to
     `{egoId} ∪ visiblePeerIds` (D6). With `visiblePeerIds == {a}`, holder `a`,
     and edge `ego→a (t1)`, assert `parent(a) == ego`, `depth(a) == 1` and
     `derived(a) == 0`. Edges touching any other ID are ignored, including when
     they would otherwise create a shorter path;
   - **Steiner pruning** `[ALG-PRUNE]`: a reached non-holder with no holder
     descendant is absent from `keep` (D9) — assert against `keep`, not
     `attributed`: a non-holder is never in `attributed` under the §0.4 naming,
     so asserting there would pass vacuously and test nothing;
   - **ring:** a holder reachable only through a non-visible person is in `ring`
     with no parent;
   - **determinism:** shuffle the edge iterable 50 times and the input sets'
     iteration order; assert identical output records every time;
   - **cap, path-preserving:** with `cap` below the holder-plus-ancestor count,
     no holder is demoted into `ring` by truncation, `capped == true`, and every
     kept holder still has its **whole** ancestor chain in `keptPeerIds` — assert
     no partial chain survives;
   - **cap, chains exceeding the budget:** with `cap` smaller than one holder's
     ancestor chain, that **attributed** holder appears in `droppedHolderIds`, is
     **absent** from both `keptPeerIds` and `ring`, and no fragment of its chain
     is kept;
   - **cap, two-node chain with budget 1:** `ego→a (t1), a→h (t1)`, holder `h`,
     `cap = 1`. Assert `keptPeerIds` is **empty**, `droppedHolderIds == {h}`,
     `capped == true` — a "fill remaining capacity with other peers" step would
     keep `a` alone, which is exactly the fragment §0.4 forbids;
   - **cap, no holders:** peers reachable but `holderIds` empty. Assert
     `keptPeerIds` is empty and `capped == false` — unused capacity is never
     filled with unrelated peers (D9);
   - **a ring holder displaced by the cap stays a ring holder:** with the budget
     exhausted before step 3, a ring holder is in `paths.ring`, absent from
     `keptPeerIds`, and **not** in `droppedHolderIds` — §0.4's three holder
     states stay disjoint, and `capped` is what reports the omission;
   - **cap never re-resolves:** `paths.ring` is identical with and without the
     cap — truncation must not turn a capped-away intermediary into "no permitted
     path exists";
   - **cap, score-independent:** selection depends only on ids and holder
     membership (there is no score input to depend on — assert the signature).

**Verify:**

```bash
cd packages/client && flutter test test/features/constellation/
```

**Acceptance:** all cases pass; neither file imports Flutter or `dart:ui`.

---

## UNIT 09 — Client pure domain: filters and density

Implements **U6 / UX4 / UX5 / §5.3**.

**Owns:**

```text
packages/client/lib/features/constellation/domain/constellation_filters.dart   new
packages/client/lib/features/constellation/domain/constellation_density.dart   new
packages/client/test/features/constellation/constellation_filters_test.dart    new
packages/client/test/features/constellation/constellation_density_test.dart    new
```

1. Filters operate **only** on the already-authorized field. Signature:
   ```dart
   typedef ConstellationRequestRef = ({
     String id,
     Set<String> needs,
     String? primaryNeedSlug,
     DateTime? startAt,
     DateTime? endAt,
     String? addressLabel,
     bool hasCoordinates,
   });
   typedef ConstellationFilters = ({
     Set<String> capabilitySlugs,   // empty = no capability constraint
     LocationFilter location,       // any | hasLocation | unspecified
     TimingFilter timing,           // any | withinDays(int) | undated
     bool includeUnspecified,       // default true
   });
   Set<String> filterRequestIds({
     required Iterable<ConstellationRequestRef> requests,
     required ConstellationFilters filters,
     required DateTime asOfUtc,     // the snapshot's loadedAt — never DateTime.now()
   });
   ```
   `ConstellationRequestRef` is owned by `constellation_filters.dart`. Capability
   values are the union of `needs` and a non-empty `primaryNeedSlug`; capability
   is unspecified only when that union is empty. Location is present when
   `addressLabel?.trim().isNotEmpty == true` or `hasCoordinates` is true. Date
   values are UTC. UNIT 11 maps each returned `ConstellationRequest` into this
   record without importing data-layer types into the filter module.
   Field mappings are frozen in §0.3. No effort filter in v1, and **no remote
   filter**: the location fields establish presence only, so `unspecified` means
   "no location given", never "remote" (limitation recorded in UNIT 20).
   Unspecified values stay visible by default in an identified group; excluding
   them requires `includeUnspecified: false`.
   **Timing is deterministic because the reference time is an input.**
   `withinDays(n)` selects against the closed interval
   `[asOfUtc, asOfUtc + n days]`, using the snapshot's `loadedAt` so the same
   snapshot filters identically however long it has been open. Per
   `beacon-schedule-semantics` (dates mean event vs deadline by nullability):
   a **deadline-only** request (`endAt` set, `startAt` null) matches when `endAt`
   lies in the interval; an **event** request (`startAt` set) matches when
   `[startAt, endAt ?? startAt]` overlaps the interval; an **undated** request
   (both null) is `unspecified` and follows `includeUnspecified`. `undated`
   selects exactly the unspecified group.
2. Filtering changes **which requests are shown**, never person order or
   geometry, and never membership. Assert by contract: `filterRequestIds`
   returns request ids only and takes no person input.
3. Density per §0.4: `constellationLabelBudget` derives from viewport and text
   scale, clamped to the ceilings; `allocateVisibleRequests` round-robins over
   authors sorted by id.
4. Tests:
   - a request with empty `needs` and no non-empty `primaryNeedSlug` follows
     `includeUnspecified` — retained with it, excluded without it, in the
     identified group either way. A request with a matching value in `needs`
     remains specified and matches even when `primaryNeedSlug` is absent;
   - one author with 40 requests cannot consume the whole budget — every author
     with at least one request gets at least one label while budget remains;
   - a smaller viewport or larger text scale lowers the budget monotonically and
     never exceeds `(3, 150)`;
   - allocation is deterministic under shuffled author-map iteration order;
   - clearing filters returns the original id set exactly;
   - **timing boundaries:** with `asOfUtc` fixed, a deadline exactly at
     `asOfUtc`, exactly at `asOfUtc + n days`, one second past it, and one second
     before `asOfUtc` produce inclusion, inclusion, exclusion, exclusion; an event
     that starts before the interval and ends inside it is included (overlap); an
     undated request is included only under `includeUnspecified`; the same inputs
     with a different `asOfUtc` change the result — proving the function never
     reads the wall clock;
   - `location: unspecified` selects exactly the requests with neither
     `addressLabel` nor coordinates, and no request is ever classified "remote".

**Verify:** `cd packages/client && flutter test test/features/constellation/`

**Acceptance:** pure; no ranking anywhere; ceilings are ceilings, not targets.

---

## UNIT 10 — Client pure domain: three-pass layout

Implements **U6 / §5.1 / R9 / R10**.

**Owns:**

```text
packages/client/lib/features/constellation/domain/constellation_layout.dart   new
packages/client/test/features/constellation/constellation_layout_test.dart    new
```

1. Implement `computeConstellationLayout` per §0.4 — three passes, never one
   call into `computeRadialHopLayout`. Reuse `clampLayoutPosition`,
   `amenityChordForRingGap`, and `preferredFanStep` from
   `features/graph/domain/layout/radial_hop_positions.dart`; do **not** call
   `computeRadialHopLayout` itself (its undirected BFS, first-discovery parents,
   and subtree-size sectors all contradict §0.4).
2. Tests:
   - **rings:** a depth-2 person sits at `2 × ringGap`; a ring person sits beyond
     `maxHops × ringGap`; a satellite sits within `satelliteOffset + ε` of its
     author (R10: none of these is achievable in a single radial call);
   - **satellite stability (R9):** add satellites to a person who **already
     holds** a request; assert **every** person position is bit-identical.
     (Holding fixed matters: a person's *first* request changes `holderIds`,
     which feeds `resolveAndCapConstellation` and may legitimately move people —
     §0.4. Add a second case asserting exactly that, so the boundary is pinned
     rather than accidentally relied on.)
   - **filter stability:** hiding a branch's requests moves no person;
   - **sector containment:** adding a depth-2 person changes only positions
     inside its parent's sector; ego, depth-1 people, and other branches are
     unchanged;
   - **ego satellites:** ego's own requests hang off the centre (D16);
   - **cap-displaced people get no position:** resolve `ego→a→h` (holder `h`)
     with `resolveAndCapConstellation(cap: 1)`, feed its `paths` and
     `keptPeerIds` in; assert neither `a` nor `h` (nor `h`'s requests) has an
     entry in `positions` or `ring`, while ego does. `paths` alone would place
     them — `keptPeerIds` is what the layout must honour;
   - **`maxHops` drives the residual radius:** the same field laid out with
     `maxHops: 2` and `maxHops: 3` places ring people at different radii, and
     the value must match the one paths were resolved with;
   - **determinism:** shuffled input iteration order ⇒ identical positions.

**Verify:** `cd packages/client && flutter test test/features/constellation/constellation_layout_test.dart`

**Acceptance:** the satellite-stability and sector-containment tests pass — they
are the reason this unit exists.

---

## UNIT 11 — Client data: entities, gql, repository, use case

Implements **U7**.

**Owns:**

```text
packages/client/lib/features/constellation/domain/entity/constellation_field.dart      new (freezed)
packages/client/lib/features/constellation/domain/port/constellation_repository_port.dart new
packages/client/lib/features/constellation/domain/use_case/constellation_field_case.dart  new
packages/client/lib/features/constellation/data/gql/constellation_field_fetch.graphql  new
packages/client/lib/features/constellation/data/repository/constellation_repository.dart new
packages/client/lib/features/constellation/data/repository/constellation_repository_mock.dart new
packages/client/lib/data/service/remote_api_client/build_client.dart                   edit
packages/client/lib/data/gql/schema.graphql                                            edit
packages/client/test/features/constellation/constellation_repository_test.dart         new
```

1. Freezed entities mirroring §0.3, with **no** score/weight field:
   `ConstellationField`, `ConstellationPerson`, `ConstellationTrustEdgeEntity`
   (`src`, `dst`, `tier`), `ConstellationRequest`, plus a
   `ConstellationHeldState` enum derived from the viewer booleans — `none`,
   `offered`, `participant`, `forwarded`, `mine`. **Never** a bare "already held"
   boolean (D16); actions derive from real state.
2. GraphQL document per §0.3, importing `image_model_v2.graphql`, following
   `forward_candidate_context_fetch.graphql`.
3. Repository per the `ForwardCandidateContextRepository` pattern
   (`RemoteApiService.request`, `dataSource == DataSource.Link`,
   `dataOrThrow(label: 'ConstellationFieldFetch')`), returning domain entities
   only. Register the port with `@LazySingleton(as: …, env: [dev, prod])` and a
   mock for tests.
4. **Register the operation for direct V2 routing.** Add
   `ConstellationFieldFetch` to `_V2RoutingLink._tenturaDirectOperationNames`
   (`build_client.dart:188`) and add the new types to `schema.graphql`. This is
   step 1 of the documented procedure at `build_client.dart:161-176`; without it
   the operation falls through to `hasuraLink`, and Hasura has no
   `constellationField`. UNIT 19 owes the same for the mutation arguments.
5. `ConstellationFieldCase` composes repository fetch → **`resolveAndCapConstellation`**
   (§0.4 — one call; resolution happens on the full peer set *inside* it),
   returning a `ConstellationFieldResolved` record (field + paths + keptPeerIds +
   droppedHolderIds + capped flags). `visiblePeerIds` is **every returned
   `peers` id** (UNIT 07 step 1: the graph subset is server-only and is not
   reconstructed from edge incidence); `holderIds` is the author set of the
   returned `requests`, ego included. Do **not** truncate before resolving, and do
   not call a separate cap function first — that ordering is the defect §0.4
   removes. The cubit injects this case, not two repositories.
6. Tests: mapping round-trip; `tier` outside `{1,2}` is rejected. Wire hygiene is
   asserted **against the operation document and the generated types**, not
   against a runtime payload — once Ferry has produced typed data an unexpected
   score-shaped key is already gone, so a runtime "rejected loudly" assertion is
   unobservable. Assert instead that `constellation_field_fetch.graphql` selects
   no field matching `/score|weight|_mr$|meritrank|rank/i` and that the generated
   entity classes expose no such member. **Holder IDs follow returned requests**
   `[ALG-HOLDERS]`: a field containing two requests by `a`, one by ego, and a
   profile-only peer `b` passes exactly `{a, ego}` as `holderIds`. Profile
   presence alone does not make `b` a holder.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d && flutter test test/features/constellation/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** domain entities cross the port; no Ferry type escapes the
repository; `domain/` imports neither `data/` nor `ui/`.

---

## UNIT 12 — Render: mode, nodes, edges, painters, legend

Implements **U8 / D1a / §4.2**.

**Owns:**

```text
packages/client/lib/features/graph/domain/entity/graph_mode.dart          edit (+constellation)
packages/client/lib/features/graph/ui/widget/graph_legend_mode.dart       edit (+constellation)
packages/client/lib/features/graph/domain/entity/node_details.dart        edit (+FieldPersonNode, FieldRequestNode)
packages/client/lib/features/graph/ui/utils/tentura_layout_algorithms.dart edit (+ConstellationLayoutAlgorithm)
packages/client/lib/features/graph/ui/widget/graph_legend_content.dart    edit
packages/client/lib/features/graph/ui/widget/graph_app_bar_actions.dart   edit (exhaustive switch at :159)
packages/client/lib/features/graph/ui/widget/graph_node_widget.dart       edit (provider seam, step 0)
packages/client/lib/features/graph/ui/widget/graph_body.dart              edit (pass the count in)
packages/client/lib/features/graph/ui/bloc/graph_person_context_cubit.dart  edit (provider seam, step 0)
packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart edit (provider seam, step 0)
packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart  new
packages/client/lib/features/constellation/ui/bloc/constellation_state.dart  new (freezed)
packages/client/lib/features/constellation/ui/widget/constellation_body.dart new
packages/client/lib/features/constellation/ui/screen/constellation_screen.dart new
packages/client/test/features/constellation/constellation_body_test.dart     new
```

0. **Provider seam first — the reuse does not compile without it.**
   `graph_node_widget.dart:115` holds an unconditional
   `BlocSelector<GraphCubit, GraphState, int?>` for the hidden-neighbour badge,
   so `GraphNodeWidget` throws when mounted under `ConstellationCubit`. Replace
   it with a `final int? hiddenNeighborCount` parameter and move the
   `context.select<GraphCubit, int?>(…)` to the existing graph call sites.
   Constellation passes `null`. This is a pure refactor: run
   `flutter test test/features/graph/` **before** touching anything else in this
   unit and require it green and unchanged.
   `GraphPersonContextCubit` **does** have the same coupling, and it is wider
   than one callback. Enumerate and lift every touchpoint — the live ones are:
   - `GraphPersonContextCubit` takes `required GraphCubit graphCubit` in its
     constructor (`graph_person_context_cubit.dart:14-21`);
   - it reads the **viewer id** as `_graphCubit.state.me.id` (`:25-29`) →
     replace with an injected `viewerId` (or a `ProfileViewCase` lookup);
   - it calls `_graphCubit.patchLoadedProfile(authoritative)` (`:89-94`) →
     replace with an optional `onProfilePatched` callback that the graph
     surfaces wire to `patchLoadedProfile` and Constellation leaves null;
   - `GraphPersonContextPanel` takes `required GraphState graphState`
     (`graph_person_context_panel.dart:20-30`) and uses
     `graphState.hiddenNeighborCounts`, `graphState.isLoading` and
     `context.read<GraphCubit>().canPageMore(...)` (`:34-51`) → replace the whole
     group with plain parameters (`hiddenNeighborCount`, `isLoading`,
     `canPageMore`) plus the `onExpand` callback for `:239-249`.

   Constellation passes `null`/`false`/`0` for the graph-only ones. UNIT 15 then
   only *uses* the seam. This is not conditional — do not defer it, and do not
   stop at `onExpand`: the panel does not compile without `GraphState` until the
   whole group is lifted.
1. Extend the two enums with `constellation`. Every existing `switch` over them
   becomes non-exhaustive — fix each explicitly; do not add a `default`.
2. `FieldPersonNode` carries `person`, `ring` (int), `isKept` (membership of
   `paths.keep` — the Steiner set, **not** the holders-only `attributed` set);
   `FieldRequestNode` carries the `ConstellationRequest` entity. Follow the
   existing `==`/`hashCode` discipline in that file.
3. Edge rendering, all through design-system tokens (§4.2):
   - **tier 1** — one quiet stroke, uniform width, no arrowhead;
   - **tier 2** — same geometry, visibly lighter or dashed, **unlabelled** (D1a);
   - **attachment** (person → request) — a visually distinct *kind* of line:
     shorter, different weight and colour role. It must not be confusable with a
     path stroke;
   - **ring stub** (ego → ring person) — dashed, low emphasis, no intermediary
     claim.
   Never weight-derived width, never a colour ramp, never a negative edge.
   Reciprocity, if shown at all, is decoration (hairline or dot), never geometry.
4. `ConstellationLayoutAlgorithm` wraps `computeConstellationLayout`, passing the
   resolved field's `paths`, `keptPeerIds`, and the `maxHops` the paths were
   resolved with (§0.4) — never `paths` alone. `relayout`
   **recomputes from the current resolved field** — positions are a pure function
   of that input and never of expansion history. Do not cache and re-emit prior
   positions to "keep things still": that makes the final layout depend on the
   order the user expanded things, which §0.4's first determinism clause forbids.
   Stability comes from the layout being deterministic, not from memoisation.
5. `ConstellationCubit` holds: `status`, `loadedAt`, resolved field, filters,
   `expandedPersonIds`, `selectedRequestId`, `viewMode`. Loads **on open only**
   (D15) — no subscription, no realtime, no polling.
6. Legend: explains tier-1 vs tier-2 strokes, attachment, and the ring, **without
   naming the evidence** behind tier 2 (D1a) and without any weight vocabulary.
7. Widget tests: golden-free structural assertions — a ring person renders with a
   stub and no parent edge; a tier-2 path renders with the distinct stroke and
   **no** label; an attachment edge never uses the path stroke style.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/features/constellation/ test/features/graph/
./scripts/check-custom-lints.sh packages/client
```

`build_runner` is required: this unit adds a Freezed `ConstellationState`.

**Acceptance:** the map renders three ring kinds and four edge kinds; no raw
colour/size constants in feature UI; tier-2 edges carry no label.

---

## UNIT 13 — Prerequisite project: fold Updates into Inbox

Implements **U9a / D17**. **Its own product review** — Constellation must not be
the vehicle that quietly redesigns Inbox. Independent of units 03–12; run it in
parallel but merge it before UNIT 14.

**Owns:** `packages/client/lib/features/inbox/**`,
`packages/client/lib/features/updates/**`,
`packages/client/lib/app/router/root_router.dart`,
`packages/client/lib/app/router/home_tab_branches.dart`,
`packages/client/lib/features/home/ui/screen/home_screen.dart`,
`packages/client/lib/features/home/ui/bloc/home_tab_reselect_cubit.dart`,
`packages/client/lib/features/notification*/**` (badge/read-state only), l10n.

1. The fold shape is **decided: receipts become a third tab inside Inbox**,
   alongside *Needs me* and *Watching*. Chosen for read-state safety — receipts
   keep a distinct home, so the Updates badge and read-state store move across
   essentially unchanged and an already-read receipt cannot resurface as unread,
   which the interleaved option put at risk. Record in the journal, before
   editing, the remaining details this leaves open:
   - the Updates badge and its read-state store **move to the receipts tab**
     (§9.2) — confirm the store's keying survives the move unchanged;
   - where the Updates archive lands within that tab;
   - what `kPathUpdates` and the `RedirectRoute(kPathNotifications → kPathUpdates)`
     become. Keep a redirect so existing deep links and notifications resolve.
2. Implement the fold. Preserve read-state continuity — an already-read receipt
   must not resurface as unread.
3. Free the navigation slot: remove `UpdatesNavbarItem` from both the
   `NavigationRail` destinations (~`home_screen.dart:222`) and the
   `HomeBottomNavigationBar` destinations (~`:284`), and remove the
   `HomeTabSpec(tab: HomeTab.updates, index: 2, …)` entry in
   `home_tab_branches.dart:54-60`. Updates occupies **index 2**, not a trailing
   slot — that index is what UNIT 14 reuses, and `home_tab_reselect_cubit`
   tracks it.
   This unit's own commit therefore has **four** destinations; that is expected
   and is not a release. UNIT 14 restores the fifth. The constraint is that
   **no build is released** between 13 and 14 — merge them together (§3: "run it
   in parallel but merge it before UNIT 14"). Renumbering the later tabs is
   part of this unit; keep `HomeTab` indices contiguous and update every test
   that asserts a tab index.
4. Tests: receipts reachable from Inbox; badge count equals the pre-fold Updates
   count; deep link to `kPathUpdates` resolves; tab-index sync survives.

**Verify:**

```bash
cd packages/client && flutter gen-l10n && dart run build_runner build -d
cd packages/client && flutter test test/features/inbox/ test/features/updates/ test/features/home/ test/app/
bash scripts/check-user-facing-terminology.sh
```

Both generators are required — this unit changes AutoRoute branches **and**
`.arb` copy — and `test/app/` carries the router contract tests that tab-index
changes break.

**Acceptance:** Updates is reachable inside Inbox with its badge and read-state
intact; the product-review decision is recorded in the journal with a reviewer
name.

---

## UNIT 14 — Navigation slot, route, My Work entry

Implements **U9 / UX7 / §9.2 / §11.4**.

**Owns:** `packages/client/lib/features/home/ui/screen/home_screen.dart`,
`packages/client/lib/app/router/root_router.dart`,
`packages/client/lib/consts.dart` (`kPathConstellation`),
`packages/client/lib/features/home/ui/widget/constellation_navbar_item.dart` (new),
`packages/client/lib/app/router/home_tab_branches.dart`,
`packages/client/lib/features/home/ui/bloc/home_tab_reselect_cubit.dart`,
`packages/client/lib/features/my_work/ui/screen/my_work_screen.dart`,
`packages/client/lib/features/my_work/ui/widget/my_work_empty_body.dart`, l10n,
`packages/client/test/features/home/constellation_nav_test.dart` (new).

1. Add `kPathConstellation` and a `HomeTabSpec` at **index 2** in
   `home_tab_branches.dart`, mirroring the Updates branch UNIT 13 removed, and
   restore the contiguous tab indices. Both the rail and the bottom bar get the
   destination, and `home_tab_reselect_cubit` learns the new tab.
2. `ConstellationNavbarItem` — **no badge, no dot, no count, ever** (§9.2). It is
   deliberately not built on whatever badge widget `UpdatesNavbarItem` used;
   copying that widget is the failure mode this rule exists to prevent.
3. **My Work stays the default landing destination.** Add a visible
   `Find ways to help` route to Constellation from My Work, prominent in its
   empty state, carrying no opportunity count and no badge.
4. Tests:
   - **anti-feed:** widget test asserting the Constellation navigation item
     renders no badge, dot, or count in either the rail or the bar, under a state
     where every other item does show one;
   - the bar has exactly five destinations in both chromes;
   - My Work is still the initial tab;
   - the My Work empty state exposes `TestIds.myWorkFindWaysToHelp` and it routes
     to `kPathConstellation`.

**Verify:**

```bash
cd packages/client && flutter gen-l10n && dart run build_runner build -d
cd packages/client && flutter test test/features/home/ test/features/my_work/ test/app/
```

**Acceptance:** five destinations, Constellation in the freed slot, no badge, My
Work default and linking in.

---

## UNIT 15 — Need labels, request preview, person panel

Implements **U10 / UX1 / UX2 / UX3 / D16 / §9.3 / §11.1–11.2**.

**Owns:** `packages/client/lib/features/constellation/ui/widget/constellation_request_preview_sheet.dart`,
`.../ui/widget/constellation_request_label.dart` (new),
`packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart` (edit),
l10n, `packages/client/test/features/constellation/constellation_preview_test.dart` (new).

1. **First glance (UX1):** the satellite label carries short need text plus
   existing timing/coverage information — e.g. *"Borrow a drill · Saturday"*,
   *"Enough help · backups welcome"*. Timing follows
   `beacon-schedule-semantics` (dates mean event vs deadline by nullability).
   Unknown values are **omitted or shown as unspecified, never guessed**.
   Quantities like *"One more driver needed"* require author-supplied facts —
   do not derive them from offer counts.
2. **Preview (UX2)** answers, in order: what contribution is needed; when /
   where-or-remote / effort **if specified**; whether more help is needed; how
   the author connects to the viewer; what the viewer can do. `Open` stays
   available. The primary action follows real state from
   `ConstellationHeldState` — `Offer help`, `Offer as backup` (status 8), or the
   existing held-request action. `Forward` is a permitted secondary action.
   Opening the preview never submits anything.
3. **Three meanings stay separate (UX3):**
   - *Connection* — the selected path, phrased *"Visible through {name}"*, with
     *"This is a connection, not a referral"* available. Tier-2 strokes stay
     distinct and unlabelled; the legend explains the distinction without
     disclosing evidence.
   - *Referral* — shown only through the existing authorized Inbox/forward
     context. Never inferred from a trust path. Never a claim that an
     intermediary *has not* seen or shared it (R14 — we cannot know that).
   - *Participation* — omitted in v1 per §0.3. Do not widen involvement reads.
   Never place a path intermediary's avatar on the request card.
4. **D16:** requests already held are shown and annotated, not hidden; ego's own
   hang off the centre with author actions.
5. Person panel: reuse `GraphPersonContextCubit` / `graph_person_context_panel`
   (issue #100) and add the person's active discoverable request list with the
   explicit expansion control.
6. Tests: state-derived action matrix (open / needsMoreHelp / enoughHelp ×
   none / offered / participant / mine); the forbidden-copy list of §0.6 appears
   in no rendered string; a held request renders annotated, not hidden.

**Verify:**

```bash
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/constellation/
bash scripts/check-user-facing-terminology.sh
```

**Acceptance:** a user can identify a concrete contribution without opening a
person; no string implies referral, endorsement, or causation.

---

## UNIT 16 — Snapshot lifecycle and action-time validation

Implements **U10a / D15 / UX8 / §11.5**. **This unit changes a live mutation.**
"Never silently convert an offer into a backup" cannot be kept by client code:
`beaconOfferHelp` (`mutation_help_offer.dart:20-34`) accepts no expected kind, and
`HelpOfferCase.offerHelp` (`help_offer_case.dart:111`) derives `offerKind` from
the status it reads at submission — so a coverage change between the client's
preflight and the mutation turns an ordinary offer into a backup with no further
user choice. The server half is the gate; the client half is the courtesy.

**Owns:**

```text
packages/server/lib/api/controllers/graphql/mutation/mutation_help_offer.dart  edit (+expectedOfferKind)
packages/server/lib/domain/use_case/help_offer_case.dart                       edit (both branches inside the locked transaction, kind check)
packages/server/lib/domain/exception_codes.dart                                edit (+offerKindChanged)
packages/server/test/domain/use_case/help_offer_case_test.dart                 edit
packages/server/test/data/repository/help_offer_expected_kind_pg_test.dart     new
packages/client/lib/features/forward/data/gql/beacon_offer_help.graphql        edit (+expectedOfferKind)
packages/client/lib/features/forward/data/repository/forward_repository.dart   edit (optional argument)
packages/client/lib/data/gql/schema.graphql                                    edit
packages/client/lib/features/constellation/ui/widget/constellation_snapshot_bar.dart  new
packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart    edit
packages/client/test/features/constellation/constellation_freshness_test.dart new
```

1. Show a plain `Loaded at …` timestamp for the displayed snapshot. Reopening
   the surface reloads (D15). Switching Map/Text does **not** imply a refresh and
   must not change the timestamp. No realtime subscription is added for
   discovery-only viewers.
2. **Server: validate every offer write inside one transaction.** Add the
   nullable `expectedOfferKind: Int` argument frozen in §0.3 (`0` normal, `1`
   backup) and thread it into `HelpOfferCase.offerHelp`. Enclose **both** the
   active-offer update branch and the new-offer branch in `_attention.runAction`
   — today the active-offer branch (`help_offer_case.dart:73-103`) updates and
   returns before `_attention.runAction` at line 113, so a check placed only in
   that scope would leave it able to write against a mismatched kind. Inside that
   scope, call
   `BeaconRepositoryPort.runInBeaconStateTransaction(beaconId: beaconId, userId: userId, fn: ...)`
   (`beacon_repository_port.dart:105`; its implementation locks the row with
   `SELECT … FOR UPDATE` at `beacon_repository.dart:425`) and perform
   authorization, lifecycle validation, active-offer lookup, kind validation and
   all writes inside its locked callback. Use the supplied locked `BeaconEntity`;
   do not derive the kind from a pre-transaction read. No direct database
   dependency in the use case is necessary.

   For a **new** offer, the permissible kind is `1` when the locked status is
   `enoughHelp`, otherwise `0`. For an **existing active** offer, the permissible
   kind is its stored `offerKind`, preserving the current update semantics. If a
   supplied `expectedOfferKind` differs from that permissible kind, throw
   `HelpOfferCoordinationException(coordinationCode: HelpOfferCoordinationExceptionCode.offerKindChanged)`
   before any write. Omission preserves those existing creation/update semantics,
   so existing clients are unaffected and `kDefaultMinClientVersion` does not
   move. Preserve the existing lifecycle/author restrictions (`authorCannotCommit`
   / `beaconNotOpen` stay ahead of the kind check) and the rule that an
   active-offer update creates no new offered commitment or submission receipt.
   **No branch may write or return successfully before this validation.**

   **Schema compatibility.** Preserve `InputFieldId.field` and the existing
   `$beaconId: String!` variable. The only schema change is the nullable
   `expectedOfferKind` argument (§0.3 — `id` stays `String!`, never `ID!`).
   Validate the pre-change `BeaconOfferHelp` operation against the updated
   registered schema and execute it successfully without the new argument.
3. **Client:** before entering an offer/forward flow, re-fetch current request
   state and action eligibility through the **existing authorized request path**
   (the same one the request detail screen uses). Constellation always submits
   the kind the user explicitly chose as `expectedOfferKind`; the repository
   argument is optional so other callers are unchanged.
4. Outcomes:
   - help now covered ⇒ present the **backup** action for a new, explicit choice.
     Never silently convert an offer into a backup — and if the server answers
     `offerKindChanged`, preserve the note and request a new choice; do not
     resubmit with the other kind on the user's behalf;
   - **current authorization denied** (closed, deleted, blocked, or the read
     wall no longer passes for this viewer) ⇒ explain that state, do not submit
     the stale action. This is *authorization*, not opt-out: an author's or an
     existing participant's independent access is untouched by discoverability,
     so "opted out" alone is never a reason to refuse — the server's answer is;
   - validation failure ⇒ offer retry without recording an offer; preserve any
     draft note.
5. Refreshing one selected request must not claim the whole field refreshed —
   the `Loaded at` value stays the snapshot's, not the re-fetch's.
6. Tests:
   - **server regression — coverage changes after preflight, before
     submission:** read the beacon as `open`, flip its status to `enoughHelp`,
     then call `offerHelp(expectedOfferKind: 0)`; assert `offerKindChanged` and
     **no writes** — no `beacon_help_offer` row, no commitment, no receipt,
     no attention action. The mirror case (`expectedOfferKind: 1` on a beacon
     re-opened to `open`) also rejects. Omitted kind keeps today's behaviour;
   - **server — active-offer update branch:** an existing active backup offer
     submitted with `expectedOfferKind: 0` rejects without changing its message,
     help types or kind. A matching update preserves its kind and creates no new
     commitment or submission receipt. An omitted kind preserves both current
     creation and current update behaviour;
   - **server — real transaction (`help_offer_expected_kind_pg_test.dart`, `-t pg`):**
     using real repositories and the real transaction runner, hold the beacon
     row in a competing transaction, change coverage, start the offer call, then
     commit the coverage change. Verify that the offer checks the newly committed
     locked state and rejects a mismatch without offer, commitment or attention
     writes. The unit harness cannot prove this:
     `test_attention_harness.dart:43` implements its unit of work as plain
     `action()`;
   - **server — schema compatibility:** the pre-change `BeaconOfferHelp`
     operation (`$beaconId: String!`, no `expectedOfferKind`) validates against
     the updated registered schema and executes;
   - client: each of the four outcomes, including `offerKindChanged` preserving
     the draft note and re-presenting the choice; the timestamp is unchanged by a
     Map/Text switch and by a selected-request refresh; a request that vanished
     between snapshot and flow entry produces an explanation, not a crash or a
     silent substitution; an opted-out request the viewer still has independent
     access to is **not** refused client-side.

**Verify:**

```bash
cd packages/server && dart test test/domain/use_case/help_offer_case_test.dart
cd packages/server && dart test -t pg -j 1 test/data/repository/help_offer_expected_kind_pg_test.dart
./scripts/check-custom-lints.sh packages/server
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/features/constellation/constellation_freshness_test.dart test/features/forward/
./scripts/check-custom-lints.sh packages/client
```

`build_runner` is required on the client: the `.graphql` document changed.

**Acceptance:** no stale action can be submitted silently — proved by the
no-writes regression, not by the client courtesy; the snapshot claim stays
truthful.

---

## UNIT 17 — Filter bar, grouping, stable anchors

Implements **U10b / UX4 / UX5 / §5.3**.

**Owns:** `packages/client/lib/features/constellation/ui/widget/constellation_filter_bar.dart`,
`.../ui/widget/constellation_overflow_group.dart` (new),
`.../ui/bloc/constellation_cubit.dart` (edit), l10n,
`packages/client/test/features/constellation/constellation_density_widget_test.dart` (new).

1. Wire the UNIT 09 filters: capability, location, timing, passing the
   snapshot's `loadedAt` as `asOfUtc`. **No effort filter and no remote filter**
   — record both omissions in the UI limitations rather than inventing a match.
   Unspecified values stay in a visible, identified group by default.
2. Overflow: group a person's extra satellites under a **labelled expansion
   control** — not a discoverable second-tap gesture. A second tap may remain a
   shortcut (per `cross-platform-gesture-affordances`: touch **and** desktop —
   secondary tap and hover affordance, never long-press alone).
3. **Anchors are unfiltered.** Layout input is always the unfiltered person set;
   filtering dims or hides satellites and branches but never re-runs the layout.
   Clearing filters restores identical positions. A filter must never make a
   connected person appear unattributed.
4a. **Three field-level states, each named and each tested.**
   - `peersCapped` — the graph was truncated. Render a persistent, non-dismissible
     *"Some connection paths are not shown"* (`constellationPathOmittedByCap`)
     notice that does not read as an error and links to the **fallback plain
     list** (UNIT 18). Do **not** say "requests are hidden": under UNIT 07's shape
     the request query is unaffected by peer overflow.
   - `requestsCapped` — the **request** query hit its own independent cap. Some
     requests genuinely were not returned, and the fallback list cannot recover
     those. Distinct copy, and it may be set at the same time as `peersCapped`.
   - client **render budget** `capped` (from `resolveAndCapConstellation`) — the
     local budget dropped kept people. Architecture §5.2 requires this signal;
     it is not `peersCapped` and must not be folded into it.
4b. **`peersCapped` poisons ring semantics — degrade the copy, do not assert.**
   This is the "While `peersCapped` is set" column of architecture §5.2's
   absence-semantics table: an author outside the graph set has no edges and is
   mechanically in `paths.ring`, but a permitted path may well exist and simply
   not have been fetched. So while `peersCapped` is set, **no ring node anywhere
   in the field may carry "no permitted path exists" copy**; the whole ring
   degrades to *"path not shown"*. Test this explicitly: with `peersCapped` set,
   no rendered string claims a path does not exist.
4. Distinguish filter hiding, space collapse, and holder states using
   architecture §5.2's absence table — this unit adds no definition of its own:
   hidden by a **filter**; collapsed for **space**; a holder in `paths.ring`
   (**ring**); and a holder in `droppedHolderIds` (**cap-displaced**). For
   `droppedHolderIds`, explain that a known connection and its holder were
   omitted from the map by the client render budget; the fetched path data
   remains available (truncation never touches `paths`). For ring holders, use
   *"Connection not explained within this map's path rules"*; when `peersCapped`
   is true, use *"Path not shown"* (4b's override). **Never claim that no
   connection exists** — a ring holder may have a four-hop path or one the
   stage-1 pinning constraint declined. A ring holder outside `keptPeerIds`
   remains a ring holder and receives a separate indication that the map's
   render budget omitted it; it never receives the attributed cap-displaced
   classification.
5. An empty filtered result offers **Clear filters** and must not imply that
   nobody in the network needs help.
6. Tests: compact and expanded window classes × text scale 1.0/1.3/2.0 — labels
   stay readable, hit areas stay ≥44dp and non-overlapping; changing a filter
   moves no person anchor; clearing restores the exact prior positions; the
   **four** absence states of step 4 render distinctly; and the **three**
   field-level states of step 4a, each asserted **independently and in
   combination**: `peersCapped` alone ⇒ `constellationPathOmittedByCap` ("Some
   connection paths are not shown" — never "field too large" or "requests
   hidden"), the fallback-list link present, ego's own requests still shown, and
   every ring node in *path not shown* copy; `requestsCapped` alone ⇒ its
   distinct copy and no path notice; client `capped` alone ⇒ the render-budget
   notice without the server graph-cap notice — test both an attributed holder in
   `droppedHolderIds` and a ring-only omission with `droppedHolderIds` empty
   (`capped` holds with two ring holders and a one-person budget); their holder
   classifications remain distinct; all three set ⇒ all
   three signals present and distinguishable. 150 requests is never required to
   be simultaneously legible.

**Verify:**

```bash
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/constellation/
```

**Acceptance:** filters change what is shown, never order or geometry; no
ranking anywhere.

---

## UNIT 18 — Accessible Map/Text switch

Implements **U10c / UX6 / §11.3**.

**Owns:** `packages/client/lib/features/constellation/ui/widget/constellation_text_view.dart`,
`.../ui/screen/constellation_screen.dart` (edit), l10n,
`packages/client/test/features/constellation/constellation_text_view_test.dart` (new).

1. A labelled Map/Text switch over the **same** authorized snapshot, filters, and
   request ids — **not** a second query, not a ranked list, not infinite scroll.
1a. **Fallback plain list mode.** The Text view doubles as the recovery surface
   for `peersCapped` (UNIT 17 step 4a): the same authorized requests listed
   **without** connection explanations, since paths are exactly what the cap made
   unreliable. Entering from the overflow notice opens this mode. It is the same
   query and the same authorization — only the path column is suppressed — so it
   must never show a request the map would not have been allowed to show. Never
   present it as "more results"; it is the same field, listed plainly.
2. Text view groups requests by person in deterministic, score-independent order
   (ascending id, matching the map's allocation), with the same per-person
   expansion and the same bounded limits.
3. Connection explanations, previews, and actions are keyboard- and
   screen-reader-accessible. Meaning must never depend on edge colour, hover,
   drag, or long press.
4. Preserve selection, filters, and map viewport across the switch. On a fresh
   snapshot reconcile by stable ids; if the selection is gone, **explain that
   state** — never silently select another request.
5. Announce expansion, empty, and error states; do not move focus unexpectedly.
6. Tests: **parity** — for each filter state, both views expose the identical
   eligible request id set; selection and filters survive a round trip; every
   action reachable by keyboard; semantics labels present on nodes, edges'
   explanations, and expansion controls.

**Verify:**

```bash
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/constellation/constellation_text_view_test.dart
```

**Acceptance:** the text view is an equivalent surface, not a degraded one.

---

## UNIT 19 — Author discoverability toggle and reach statement

Implements **U11 / §8.5**.

**Owns:** `packages/client/lib/features/beacon_create/ui/widget/info_tab.dart` (or the
optional-summary row — pick the one that holds comparable per-request settings and
record which), `packages/client/lib/features/beacon/**` (detail settings surface),
`packages/client/lib/domain/entity/beacon.dart`,
`packages/client/lib/data/gql/beacon_model.graphql`,
`packages/client/lib/data/model/beacon_model.dart`,
`packages/client/lib/data/gql/schema.graphql`,
`packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart`,
`packages/client/lib/features/beacon_create/ui/bloc/beacon_create_state.dart`,
the beacon create/update
mutation documents, l10n, `packages/client/lib/ui/test_ids.dart`,
`packages/client/test/features/beacon_create/discoverability_toggle_test.dart` (new).

1. Add `@Default(true) bool isDiscoverable` to the `Beacon` entity and
   `is_discoverable` to `BeaconModel` (`data/model/beacon_model.dart` as well as
   the `.graphql` document); thread it through the create/update mutation
   documents, `schema.graphql`, the repository mappers, and
   `BeaconCreateState`/`BeaconCreateCubit` — without the cubit and state the
   toggle has nowhere to live between load and save. Server field name is
   `isDiscoverable` (UNIT 03/4).
2. Author-facing control on the request surface: the toggle beside a plain
   statement of current reach — *"Discoverable by people you and your network can
   both see"*. A precise live count is optional and **must not** become a vanity
   metric; v1 ships no count.
3. Non-authors never see the toggle. Changing it is an ordinary update: it does
   not revoke content already disclosed, and the UI must not imply that it does.
4. Tests: default on for a new request; toggling round-trips through
   `beaconUpdate`; the reach statement is present whenever the toggle is; the
   control is absent for non-authors.

**Verify:**

```bash
cd packages/client && flutter gen-l10n && dart run build_runner build -d
cd packages/client && flutter test test/features/beacon_create/
bash scripts/check-user-facing-terminology.sh
```

**Acceptance:** authors can see and change what they are opting out of.

---

## UNIT 20 — Version, docs activation, UX acceptance

Implements **U12 / UX9 / UX10 / §10**.

**Owns:** `packages/client/pubspec.yaml`, `packages/client/web/index.html`,
`docs/Tentura_current_status_quo.md`, `CONTEXT.md`,
`docs/features/constellation.md` (new), `docs/README.md`, the journal.

1. Bump the client to **7.2.0**. Run the app once (`flutter run` or
   `flutter build web`) so `hook/build.dart` rewrites the
   `flutter_bootstrap.js?v=` cache-buster, then confirm the `web/index.html` diff
   is present and staged. Do **not** raise `kDefaultMinClientVersion`.
2. Status-quo doc, **required when Constellation ships**:
   - §5 surface table gains a **Constellation** row and **loses the Updates row**
     (D17); re-check the "no ranked feed" sentence against both changes;
   - §7 gains the D16 rule that field membership and held-request state are
     independent;
   - §3 "feedless, inbox-driven" becomes "feedless, inbox- and field-driven";
   - §14 drops "exploration without feed logic" and points at the architecture
     doc;
   - §11 discoverability paragraph is promoted from *intended* to **active**,
     citing m0160–m0163 as the activating migrations.
3. `CONTEXT.md`: merge UNIT 01's split back into one active contract now that the
   target is live.
4. `docs/features/constellation.md`: the shipped feature doc — surfaces, edge
   vocabulary, ring semantics, filters, freshness, and the **limitations list**:
   no effort filter; no third-party participation statements; actions outlive
   discoverability (R7); already-served media is not revocable (R8); the four
   narrowings of the architecture's positional-stability rule (§0.4 — sector
   containment, vacuous at depth 1, the residual ring outside it, and requests
   that change holder status); the symmetric-visibility residual gap (§0.1 —
   field membership is a subset of wall-readable, never a superset); **the
   stage-2 reachability cost** (architecture §5, `ALG-STAGE2`): a holder whose
   only route needs a `T` node at a ring other than its explicit-trust `depth1`
   falls to the residual ring although a path exists, because one person is never
   drawn at two rings; and **no remote filter** — the location fields establish
   presence only, and a request without them is *unspecified*, never "remote".
5. **UX acceptance (UX9).** Fixtures must include: explicit and inferred
   connections, a genuine referral, pending and acknowledged helpers, unknown
   effort/timing, an `enoughHelp` request, a dense field, compact and large
   layouts, and the text view. Task: *"Find something you could help with,
   explain your connection to its author, and describe what happens if you
   offer."* Plus a stale-request recovery task and keyboard/screen-reader
   operation.
   Record: time to first suitable opportunity, taps before understanding the
   need, completion, mistaken endorsement/referral assumptions, and understanding
   of offer versus discussion admission. Use the measured times to **set** a
   benchmark — do not invent a speed target. Clicks, browsing duration, and graph
   exploration are **not** success measures. Fix observed failures before
   declaring acceptance.
6. Update the `docs/README.md` rows; move nothing to `archive/` until the journal
   records acceptance.

**Verify:**

```bash
cd packages/client && flutter test
cd packages/server && dart test && dart test -t pg -j 1
./scripts/check-custom-lints.sh packages/client && ./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh
git status --short packages/client/web/index.html
```

**Acceptance:** full suites green; docs describe shipped behaviour with evidence;
limitations recorded; cache-buster matches 7.2.0.

---

## 4. Spec coverage (self-check)

| Arch item | Unit(s) |
|---|---|
| D1 tier-1 preferred, tier-2 fallback | 06, 08 |
| D1a tier-2 distinct, unlabelled | 12 |
| D2 3-hop cap · D7 direction · D8 one parent · D9 Steiner | 08 |
| §5 `ALG-HOLDERS` / `ALG-DEDUP` / `ALG-STAGE1` / `ALG-STAGE2` / `ALG-PARENT` / `ALG-EGO` / `ALG-PRUNE` | 08 (named tests per §0.4); `ALG-HOLDERS` by 07 (eligibility) and 11 (`holderIds` construction) |
| §5.2 absence-semantics table (N2) | 08, 17, 18 |
| D3 residual ring, tappable, carries satellites | 08, 12, 15 |
| D4 opt-out discoverability · D12 backfill true | 03, 05 |
| D5 no forward edges drawn | 12, 15 (copy) |
| D6 permitted intermediaries only | 06, 08 |
| D10 active = {0,7,8}, enoughHelp de-emphasised | 05, 07, 15 |
| D11 content-wall parity (not involvement), deliberate widening | 05 |
| D13 closure over the wire, tree on screen | 07, 08 |
| D14 symmetric mutual visibility | 04 |
| D15 refresh on open only | 12, 16 |
| D16 held requests annotated, ego's own shown | 07, 11, 15 |
| D17 Constellation takes the Updates slot | 13, 14 |
| UX1 readable needs · UX2 actionable preview · UX3 distinct meanings | 15 |
| UX4 filters · UX5 density | 09, 17 |
| UX6 text view | 18 |
| UX7 My Work entry | 14 |
| UX8 freshness and action checks, incl. server `expectedOfferKind` | 16 |
| UX9 task-based acceptance · UX10 doc reconciliation | 01, 20 |
| R1, R9–R11, R13, R14, R16 (fixed in arch) | 04, 08, 10, 12, 15 |
| R2, R3, R4, R7, R8, R12, R15 (decided) | 05, 07, 08, 15 |
| R5, R6 + §14.1 hard gate | 02 |
| §5.2 deterministic, path-preserving caps (14.2/1) | 08 |
| §11 Updates fold scope (14.2/2) | 13 |
| §4.2 tier-2 token treatment (14.2/3) | 12 |
| §5.3/§11.2 field mappings and density (14.2/4) | 07, 09, 17 |
| §10 current vs intended docs (14.2/5) | 01, 20 |
| symmetric peer set is the single source (14.2/6) | 04, 06, 07 |
| `ctx` pinned server-side, off the wire (14.2/7) | 07 |
| provider-neutral render seam (14.2/8) | 12 |

Test obligations from architecture §12.1 map to: determinism 08/10; pruning 08;
containment 06/07/08; wire hygiene 07/11; tier preference 08; symmetry 04;
authorization 05; anti-feed 14; first glance and density 17; filter/layout parity
17/18; social meaning 15; stale actions 16; navigation/accessibility 14/18.

---

## 5. Out of scope (executor must not do)

- Any use of `mr_graph` as a path source (§7.2). It is a ranked focus
  neighbourhood in a fixed 100-row window with known incomplete structural
  coverage, not a path API. Taking that exit requires a new path contract and an
  explicit privacy decision.
- Undirected "you both trust Carol" bridge paths (§14.3/1).
- Per-capability contexts. `ctx` is fixed at `''` (D14, §14.3/2).
- Any badge, dot, or count on the **Constellation navigation item** (§9.2).
  Request overflow counts (`constellationMoreRequests`, "+{count} more") remain
  permitted — they are expansion controls, not notification hooks. Ranking,
  "top requests", recommendation, and score-derived ordering of people by
  anything but geometry remain forbidden.
- Any score, weight, `prev_sent_weight`, `dst_score`/`src_score`, or ordering
  derived from one — rendered **or** transmitted (§9.1).
- Negative or neutral trust edges; Constellation is hard-coded `positive_only`.
- Widening `can_read_involvement`, admitting anyone to a discussion, or adding a
  "watching" action to populate a preview.
- Changing My Work's default-destination status, or adding personalized
  recommendations to it (§11.4).
- Editing a failing visibility expectation without recording why the old rule no
  longer holds (§2/7).
- Shipping UNIT 05 without `GATE-14.1: resolved` and a security review.
- Re-litigating the D1 key ordering. It was decided by explicit architecture
  override (§6); an executor must not restore derived-first.

---

## 6. Architecture overrides

Decisions taken here that diverge from the architecture as originally written.
**All are approved and have been written into `constellation-edge-semantics.md`**
(amendment banner dated 2026-09-08); UNIT 01 step 6 verifies rather than authors
them. The two documents now agree.

| Ref | Kind | Architecture location |
|---|---|---|
| **O1** | override — hops-first path key | §5, D1, D8 |
| **A2** | correction — no `ctx` on the wire | §12/U5, §14.2/7 |
| **A3** | correction — narrowed positional stability | §5.1 |
| **N1** | new — symmetric peer set + residual gap | §5, §14.2/6 |
| **N2** | new — peer cap guard rail, three holder-absence meanings | §5.2 |
| **N3** | new — provider-neutral render seam | §12/U8, §14.2/8 |

### O1 — two-stage search, hops-first within each stage (`GATE-D1: resolved (A)`)

`GATE-D1` is **resolved (A)**. The override is now the architecture's own text:
O1a (two stages, so D1's disclosure bound survives) and O1b (hops-first within a
stage, which is what makes `depth` well-defined) are stated and proved in
`constellation-edge-semantics.md` §5, together with the accepted cost of the
stage-2 constraint. Nothing about the algorithm is decided here.

What this plan owes the override: §0.4's binding table, the UNIT 08 tests
identified in that table (each named for the `ALG-…` clause it pins), and UNIT
10 — whose sibling-sector model now rests on §5's proved invariant rather than
on an assumption.

---

## 7. Revision history

This plan is at **revision 11**. It states only what is currently true; it does
not carry its own change log.

Every revision entry — what each adversarial-review round found, what was
changed, and what was deliberately left alone — is in
[`constellation-review-cursor-gpt.md`](constellation-review-cursor-gpt.md),
Part C. The review findings that drove them are Parts A and B of the same file.

Executors: read the plan, not the history. The history exists to answer *why is
this clause here*, and nothing in it overrides a clause above.
