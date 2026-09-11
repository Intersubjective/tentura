# Constellation pinning — implementation plan

Status: implementation-ready plan; no implementation or acceptance implied.
Decisions in this document are not shipped product behavior until implemented.

Updated: 2026-09-11. Live-code baseline: migrations through `m0166`.

Implementation starts at [Execution rules](#execution-rules), followed by [frozen contracts](#frozen-implementation-contracts) and [P01–P12](#ordered-implementation-packets).

User-facing **Request** remains internal **Beacon**. This feature introduces a
personal spatial preference over existing people and beacons; it does not create
a parallel Request domain entity.

## Goal

Let a viewer arrange and pin people and Requests in Constellation so the map
develops a stable, personal shape around ego. Pinned people form a persistent
personal skeleton; current opportunities continue to occupy the dynamic layer.

## Accepted product decisions

### D1 — A pinned person does not require an active Request

A pinned person remains present in the viewer's Constellation even when that
person has no active accessible Requests. Pinning is viewer-owned presentation
state, not a consequence of current field membership.

Pinning never grants visibility or overrides a block or other access loss.

### D2 — The viewer chooses and owns the exact placement

The viewer can drag a person to a chosen point and pin them there. A pinned
person does not automatically move when their path or ring classification
changes. Changed topology is communicated by current edge wiring; the viewer
may reposition the person manually.

### D3 — The arrangement follows the account

Anchors are persisted server-side and follow the viewer across sessions and
devices. Screen pixels are not a portable persistence format; the technical
representation must use coordinates in Constellation graph space relative to
ego.

### D4 — Person and Request anchors are independent

Pinning or moving a person does not pin or move their Requests. A pinned Request
has its own position relative to ego. Moving either endpoint only changes the
rendered author-to-Request edge. Unpinned Requests remain satellites of their
authors.

### D5 — Closed Requests are hidden by default, not forgotten

When a pinned Request closes, its node disappears from the default Constellation
view while its anchor remains dormant. If the Request becomes eligible for the
current view again, it returns at the same anchor.

The filter surface gains two opt-in filters, both disabled by default:

- **Show closed** expands the field to readable closed Requests.
- **Only Requests I participated in** restricts the field by the viewer's own
  participation. The exact participation predicate is frozen in C2 below.

An unreadable or deleted Request is never rendered, even when an anchor or
filter preference exists. Pinning is not an authorization mechanism.

### D6 — Forwarding alone is not participation

A viewer who only forwarded a Request does not match **Only Requests I
participated in**. Forwarding is relay activity, not participation in execution
or coordination.

A separate **Show Requests I forwarded** filter is a possible future extension.
It is not part of the participation predicate or the initial scope of this
feature.

### D7 — A pending help offer counts as participation

A Request matches **Only Requests I participated in** as soon as the viewer
submits a help offer; acknowledgement by the author is not required. This keeps
the filter aligned with the existing My Work boundary and prevents an offered-on
Request from disappearing while it awaits the author's response.

### D8 — A declined offer is not completed participation

If the author declines a help offer before any acknowledgement or discussion
admission, the Request stops matching **Only Requests I participated in**. The
declined offer may remain visible on responsibility/history surfaces such as My
Work, but it does not mean that participation actually began.

### D9 — Completed participation remains participation

After an acknowledged participant later withdraws or is released from the
current commitment, the Request continues to match **Only Requests I
participated in**. The predicate preserves historically established
participation instead of reducing it to current stake.

### D10 — Request state is visible on the graph and explained in the legend

Request nodes must communicate their current state directly on the map. The
encoding may use a semantic border tone as reinforcement, but must also include
a non-color cue such as an icon, corner marker, or shape treatment. The graph
legend explains every state encoding that can appear.

The same state meaning must be available to assistive technology and Text view.
The state dimension and visual mapping are fixed by D36 and C2 below. Today the
Constellation label exposes coverage and viewer-held annotations in text, while
the underlying `BeaconIdentityTile` has no dedicated lifecycle marker.

### D11 — Request-node signals have separate responsibilities

The Request node's primary border and status marker encode lifecycle/coverage.
A separate minimal pin icon communicates spatial anchoring. Viewer-relative
states such as mine, pending offer, or participant remain in the label, preview,
and participation filter instead of adding a third decorative layer to the node.

The legend explains the lifecycle/coverage encoding and the pin marker without
conflating either with viewer participation.

### D12 — Show closed does not mean show cancelled

**Show closed** includes successfully closed Requests and their wrapping-up or
review phase. It does not include cancelled Requests: cancellation is a distinct
outcome in Tentura, not a form of successful closure.

A separate **Show cancelled** filter may be considered later, disabled by
default; it is outside the initial scope.

### D13 — Request filters temporarily hide pinned Requests

Request filters apply strictly to pinned and unpinned Requests alike. A pinned
Request that does not match is hidden while its anchor remains unchanged; it
returns to the same position when the filter no longer excludes it.

The filter surface reports how many pinned Requests are currently hidden and
offers a clear-filter action. Request filters do not hide pinned people, because
people form the persistent personal skeleton rather than the filtered Request
layer.

### D14 — Favorites and Constellation anchors are independent

Saving a Request in Favorites and spatially pinning it in Constellation are
separate viewer actions and separate persisted states. Neither action implies,
creates, or removes the other.

The new persistence/API vocabulary uses `constellation_anchor`; it must not
reuse the existing `beacon_pinned` storage contract, whose meaning is a saved
Request rather than graph placement.

### D15 — Moving a pinned object commits on drop

An already pinned person or Request can be dragged directly without first
unpinning it. Dragging changes local presentation only; dropping performs one
optimistic server upsert for the final coordinate. Intermediate pointer movement
is not persisted.

The pin remains active throughout. If persistence fails, the object returns to
its last server-confirmed position and the viewer receives concise failure
feedback. No separate Save or second Pin action is required.

### D16 — Placement does not globally disable the camera

Pan and zoom remain available while the viewer is arranging an object, so a
mobile viewer can navigate and rescale the graph before continuing placement.
Camera gesture handling is suspended only after a specific node drag has been
captured and only until that drag ends; it resumes immediately on drop or
cancel.

Rejected: disabling camera pan/zoom for the entire placement mode. That makes
placement across a large mobile canvas impractical.

### D17 — First placement requires explicit confirmation

Dropping an unpinned person or Request creates a provisional local position,
not a persisted anchor. Camera controls resume immediately, and the viewer can
either choose **Pin here** or cancel. **Pin here** creates the server anchor;
cancel or leaving placement restores the computed layout position.

This deliberate first-pin confirmation protects against an accidental node drag.
Subsequent movement of an already pinned object follows D15 and commits on drop.

### D18 — A captured node drag owns the touch sequence

Touch gesture ownership is deterministic for the duration of one pointer
sequence:

- If multi-touch camera scaling is recognized before a node drag is captured,
  the camera wins and the node does not move.
- Once a node drag is captured, later pointers cannot switch the gesture to
  camera pan or zoom.
- Camera gestures are re-armed after the node drag ends and all participating
  pointers have lifted or cancelled.

This prevents the screen-to-graph coordinate transform from changing midway
through a node drag and avoids a camera jump from a pointer left on screen.

### D19 — Anchor coordinates use a versioned ego-relative space

Persisted anchor positions are Cartesian coordinates relative to ego, expressed
in normalized ring units rather than screen pixels, Flutter `Offset`, canvas
coordinates, or camera zoom. A domain value object carries `xUnits`, `yUnits`,
and `coordinateSpaceVersion`.

The client maps those values into current render coordinates. A future change to
the geometric meaning of the coordinate space requires an explicit version and
migration instead of silently moving existing anchors.

### D20 — Viewer-chosen anchors may overlap

Pinned people and Requests may occupy overlapping positions. A drop is not
rejected, snapped away, or rolled back merely because another anchor occupies
the same area. The viewer's chosen coordinate is authoritative, especially on
mobile where corrective movement makes placement frustrating.

Automatic layout still treats pinned nodes as obstacles when placing unpinned
nodes. It must not resolve overlap between pinned anchors by moving either one.

Rejected: snapping the dragged node to the nearest collision-free position or
returning it to its prior/provisional position after an overlapping drop.

### D21 — Overlap uses ordinary topmost interaction

Overlapping anchors do not create a cluster, chooser, fan-out, or special
selection mode. Ordinary hit testing selects the topmost node. The viewer can
drag that object away and then interact with the next object underneath,
repeating as needed.

Rejected: an adaptive selection sheet listing every node under the pointer. Its
extra interaction cost is not justified for a layout the viewer created and can
manually separate.

### D22 — Last placed or moved is topmost

Among overlapping anchors, the node whose anchor was most recently created or
moved is rendered and hit-tested on top. The order follows server-authored
placement time, not local device time or preview activity. Opening or selecting
a node does not change its layer.

Equal placement times use a stable target-kind and target-ID tie-break so the
same stack order is reconstructed after refresh and on every device. Dragging a
node updates its placement time and therefore brings it to the top.

### D23 — Pinned and automatic layers have independent budgets

Pinned anchors have no product or render budget. Every currently authorized and
filter-eligible pinned target is shown with priority, regardless of how many
anchors the viewer created. Anchors do not consume or reduce the separate budget
for automatically selected, unpinned nodes.

The resulting total graph is therefore `all eligible pinned nodes + the full
automatic-node budget`. If excessive pinning creates visual clutter once
automatic nodes are added, that clutter is an accepted consequence of the
viewer's own arrangement rather than something the layout corrects.

Rejected: an account anchor limit, silently pruning pinned targets, evicting old
anchors, or shrinking the normal automatic-node budget as the pinned count
grows.

### D24 — Explanation closure for pinned targets is outside the automatic budget

A visible pinned target brings the minimum currently authorized graph closure
needed to explain how it relates to ego, even when those support elements would
not have been selected by the ordinary automatic-node budget. For a pinned
Request this closure includes its author, any required visible path
intermediates, and the required connecting edges. Shared support nodes and
edges are deduplicated across pinned targets.

Support nodes introduced only for this closure are not themselves pinned: they
have no anchor, do not gain persistent visibility independently of the target,
and remain layout-managed. They do not consume or reduce the separate
automatic-node budget. If no authorized explanatory path exists within the
Constellation hop cap, the pinned target remains a residual node rather than
expanding the graph beyond that cap or fabricating a relationship.

### D25 — Text view exposes pin state without inventing spatial ordering

Text view exposes pin and unpin for people and Requests and clearly marks which
items have Constellation anchors. Pinning from Text view stores the target's
current computed Map position as its anchor; it does not derive a coordinate
from list order. Text ordering continues to communicate its own documented
non-spatial grouping and must not imply relative two-dimensional placement.

Repositioning an anchor remains a Map action in the initial scope. An
accessible keyboard or directional movement path may be designed separately;
Text view does not add misleading ordering controls as a substitute for moving
an object in two dimensions.

### D26 — Concurrent anchor mutations use server-ordered last-write-wins

Each anchor is one server-authoritative mutation stream per viewer and target.
The last mutation accepted by the server wins, including unpin; ordering uses a
server-assigned monotonic revision rather than client wall-clock time. A later
move after an unpin recreates the anchor and is treated as an explicit repin.

While a local node drag owns the gesture, an incoming update for the same anchor
must not move the object under the viewer's pointer. The client defers that
update until the gesture ends, submits the drop against current server state,
then reconciles to the newest server revision. A successful mutation adopts
the returned authoritative anchor. A failed mutation restores the newest
server-confirmed position available, not necessarily the position captured at
drag start. Ordinary updates for anchors not being dragged apply immediately.

### D27 — One anchor table retains target-specific foreign keys

Persistence uses one account-owned `constellation_anchor` table for both target
kinds. Each row contains `viewer_id`, normalized coordinates,
`coordinate_space_version`, server revision, and server placement time, plus
mutually exclusive nullable `person_id` and `beacon_id` columns. A database
check requires exactly one target column to be present.

Partial unique indexes on `(viewer_id, person_id)` and
`(viewer_id, beacon_id)` establish one anchor per viewer and target. Both target
columns keep ordinary foreign keys to their respective tables; the design does
not use an unchecked polymorphic `target_kind + target_id` reference. Domain
and API types may still expose a target-kind sum type rather than leaking the
nullable-column representation.

### D28 — Unauthorized anchors stay dormant and undisclosed

Temporary loss of target visibility, including blocking or content-access
loss, does not delete the stored anchor. The server omits both target and
anchor from the client projection and from filter-hidden counts. If access
returns, the target returns at its prior coordinate. Physical deletion of a
person or Beacon deletes corresponding anchors through foreign-key cascade.

Pinning overrides automatic discovery selection, not authorization. A pinned
Request which is no longer automatically discoverable but remains readable is
still eligible for the pinned layer. Lifecycle and viewer-selected filters are
applied only after authorization.

### D29 — Field snapshot composes anchors and server-owned membership filters

The V2 `constellationField` response is the single read boundary for the field,
authorized anchors, pinned-only targets, and their explanation closure. The
`showClosed` and `participatedOnly` flags are server-side query inputs because
they change database membership; toggling either loads a new timestamped field
snapshot. Existing capability, location, and timing filters remain client-side
presentation over that snapshot.

The response reports the number of authorized pinned Requests excluded by the
server-side Request filters. The client combines that with pinned Requests
hidden by its local filters for the D13 filter-surface message. Map and Text
views continue to consume the same returned snapshot.

### D30 — Anchor writes use target-typed authenticated V2 mutations

V2 exposes one anchor upsert and one anchor delete mutation. Both identify the
target with a closed `PERSON | BEACON` kind and `targetId`; upsert additionally
accepts normalized coordinates and `coordinateSpaceVersion`. The server derives
`viewerId` exclusively from JWT credentials, validates target existence and
current visibility for creation or movement, then returns the complete
authoritative anchor including server `revision` and `placedAt`.

Unpin deletes only an anchor owned by the authenticated viewer. Wire inputs and
nullable database target columns are mapped at the API/repository boundary and
do not escape as primitive pairs into domain layout code.

### D31 — Cross-device live sync invalidates anchors only

While Constellation is open, the client subscribes to a private account-scoped
anchor-change signal. The signal carries invalidation/revision identity rather
than becoming a second authoritative anchor payload; the client rereads the
server-owned anchor projection and reconciles it under D26. This subscription
does not make discovery content or Request lifecycle realtime.

This is a deliberate narrow exception to the related Constellation plan's
refresh-on-open rule: field content remains a timestamped snapshot, while the
viewer's own spatial preferences synchronize live. A target being actively
dragged retains gesture ownership and defers reconciliation until drag end.

### D32 — Coordinate-space v1 is finite and enforced before drop

Version 1 accepts finite anchor-centre coordinates in the inclusive square
`[-10, +10]` ring units on each axis. The placement UI constrains movement at
that navigable boundary before drop, so normal interaction cannot produce a
post-drop snap or collision-style rollback. The server rejects non-finite,
out-of-range, or unknown-version values.

Changing the envelope or its geometric interpretation requires a new
`coordinateSpaceVersion` and explicit migration policy. Responsive clients map
the same normalized coordinate into their render space and retain enough
camera extent and node padding to reach boundary anchors.

### D33 — Automatic positions have deterministic baseline and session-local inertia

On a fresh load, unpinned positions are a deterministic function of the
authorized snapshot, topology, stable IDs, viewport class, and anchors. During
one client session, prior positions of unchanged unpinned nodes are explicit
soft layout hints when their semantic parent/ring is unchanged and they do not
conflict with a hard anchor. This reduces avoidable movement without promising
cross-device equality for automatic nodes.

Only anchors persist. Session-local automatic positions are never uploaded, and
the pure layout contract remains deterministic for a given complete input,
including any explicit prior-layout hints.

### D34 — Dragging never continuously reflows the field

During a node drag, only the dragged node and its incident edge geometry update;
other nodes do not chase the pointer. Dropping an already pinned node applies
its new anchor optimistically and triggers one automatic-layer reconciliation.
For first placement, the provisional drop does not reflow other nodes; the one
reconciliation happens only after **Pin here** is invoked optimistically.

If persistence fails, restoring the latest server-confirmed anchor under D15
and D26 triggers one corresponding reconciliation. There is no continuous
force simulation or per-pointer-move global layout.

### D35 — Layout priority is fixed and crowding degrades to deterministic overlap

The placement order is ego, pinned people and pinned Requests, explanation
support nodes, ordinary automatically selected people, then unpinned Request
satellites. Pinned coordinates are hard constraints. Support nodes outrank the
ordinary automatic layer because they are required to explain pinned targets,
but remain unanchored and layout-managed under D24.

For each automatic node, layout searches a bounded deterministic sequence of
candidate positions around its semantic ideal and accounts for rendered node
bounds plus design-system spacing. It never moves a pinned anchor. If excessive
pinning exhausts collision-free candidates, it chooses the deterministic
least-conflicting candidate and permits overlap rather than dropping nodes,
reducing budgets, or expanding the canvas without bound.

### D36 — Request status has a redundant five-state graph vocabulary

The initial graph and legend map the renderable Request states as follows:

| Request state | Semantic tone | Non-color cue |
|---|---|---|
| Open | neutral | open-circle marker |
| Needs more help | warning | add-help marker |
| Enough help | positive | check marker |
| Wrapping up / review | informational | time marker |
| Closed | muted completion | completed marker |

Concrete colors, icon assets, stroke widths, spacing, and typography come from
the existing Tentura Material 3 design system and must pass contrast and
semantics checks. Each node and Text-view row exposes the state as text to
assistive technology; the legend names every visible cue. The spatial pin icon
is separate and invariant across lifecycle states. Draft, Cancelled, and
Deleted Requests are outside the initial renderable set.

### D37 — Initial rollout deliberately forces the new client

There are no real users requiring mixed-version compatibility for this rollout.
The release raises `packages/client` semver, synchronizes the tracked web
cache-buster, and raises server `kDefaultMinClientVersion` to that client
version. Older clients are intentionally rejected rather than supported against
the new anchor contract.

No anchor backfill is required. Migration, API, and client may be treated as one
coordinated activation, and acceptance does not include an old-client/new-server
compatibility matrix. Database rollback and forward migration safety still
remain required engineering properties.

## Execution rules

D1–D37 remain binding. C1–C8 below resolve implementation details; execute P01–P12 in order. Each step requires its checks to pass before the next. This is documentation, not permission to activate an incomplete release.

- Preserve unrelated worktree changes. Change only files needed by the current step; do not commit generated files.
- New names below are prescribed, not claims that files already exist. `S` means `packages/server/lib`; `C` means `packages/client/lib`; `F` means `C/features/constellation`; `G` means `packages/force_directed_graphview/lib/src`.
- Use existing Beacon entities. New anchor/coordinate/projection entities are feature values, not a parallel Request model.
- Domain ports return typed domain values. SQL, Ferry, Flutter gestures and graph-controller mutations stay in adapters. A Cubit injects use cases, not another persistence repository.
- Add `docs/plans/constellation-pinning-implementation-journal.md` in P01. For each step record owned files, commands, results and unresolved failures. No speculative PASS entries.

## Frozen implementation contracts

### C1 — Targets, coordinates and ordering

- `ConstellationAnchorTarget` is a sealed `person(id)` / `beacon(id)` value. Its wire kind is `PERSON` / `BEACON`. IDs are existing opaque text IDs, not assumed UUIDs. Never key client maps by a naked target ID: use the typed target; graph keys are `person:<id>` / `beacon:<id>`. Update `FieldPersonNode`/`FieldRequestNode` in `C/features/graph/domain/entity/node_details.dart` and Constellation node/edge lookups together; unwrap IDs before profile/Beacon navigation or API calls. Other graph node types retain their IDs.
- Ego is fixed and cannot be pinned. Reject `PERSON` targeting the authenticated viewer with `INVALID_TARGET`. A viewer's own published Beacon can be pinned.
- `ConstellationAnchorPosition(xUnits, yUnits, coordinateSpaceVersion)` uses finite doubles, inclusive `[-10,10]`, version `1`. Reject unknown versions; never silently clamp server inputs.
- V1 conversion is `renderCentre + (xUnits, yUnits) * 170`; inverse subtracts ego centre and divides by `170`. Positive x is right, positive y is down. Keep a `4096 × 4096` canvas and centre `(2048,2048)` on every viewport. Camera zoom is independent. Named geometry constants belong in `constellation_consts.dart`; these are coordinate units, not UI styling tokens.
- Nodes remain reachable at all four envelope edges, with rendered bounds and a design-system spacing margin inside camera extent. Clamp the *dragged centre* during pointer movement, before displaying it; never snap on drop. Maintain pointer-to-centre grab offset.
- Server revision is an account-wide monotonically increasing PostgreSQL `bigint`, encoded as a decimal **String** on GraphQL and parsed as `BigInt` on clients (no GraphQL Int or JS-safe-number assumption). It orders updates and deletions; revision `0` means no mutations yet.
- Stable ascending paint order: unanchored nodes, then confirmed anchors sorted by `(placedAt, targetKind, targetId)`; later entries paint/hit-test on top. Kind tie-break is lexical (`BEACON`, then `PERSON`), ID is lexical. Active drag/provisional/pending placement paints above confirmed anchors. Selection never reorders. Ego has no drag/pin action.

### C2 — Authorization, filters and participation

Apply authorization **before** classification, counting or returning IDs. Never return an unauthorized anchor as a tombstone, hidden-count contribution, title or reason.

| Target/path | Required predicate |
|---|---|
| Pinned person, including one without Requests | Existing symmetric person visibility in the requested context, with `block_hides` checked in both directions; reject ego |
| Pinned Beacon / Beacon upsert | Exists, published, `beacon_can_read_content(id, viewerId)`, no block in either direction with author; upsert additionally permits only statuses `0,7,8,5,4,6` |
| Unpinned automatic peer Beacon | Existing discovery predicate and person visibility; keep `is_discoverable`, content read wall and both block checks |
| Unpin | Delete only viewer-owned target key; idempotent even if target is now missing/unreadable; return the same success shape whether it existed or not |
| Explanation support | Current authorized person identities and trust edges only. A readable Beacon can supply its already-authorized author identity, but does not make that author independently pinnable |

Request filters are an AND. `showClosed=false` permits statuses `{0,7,8}`; `true` permits `{0,7,8,5,4,6}`. Status `4` is legacy closed. Draft `3`, cancelled `1`, deleted `2`, unpublished and unknown statuses never render. Anchors for readable but permanently excluded states remain dormant; these are not reported as *filter-hidden*.

`participatedOnly` uses a single SQL predicate shared by automatic and pinned projections:

```text
is author
OR exists beacon_commitment_event(kind = 1, beacon_id = target, user_id = viewer)
OR exists beacon_help_offer_admission_event(action IN (0,1), beacon_id = target, offer_user_id = viewer)
OR current beacon_participant(role = 1 OR room_access = 3) for viewer and target
OR (active beacon_help_offer(status = 0)
    AND latest admission action by seq is neither decline(2) nor remove(3)
    AND current coordination response_type is not not_suitable(4))
```

Missing admission/coordination rows pass the final branch. Forward edges, Favorites, messages, views and anchor existence do not establish participation. An active normal or backup offer qualifies. Withdrawn unacknowledged offers do not. Resubmission follows the existing offer/admission workflow; a stale decline continues to exclude until that workflow supersedes it. Use `EXISTS`/indexed batch SQL, never per-Beacon repository calls.

D9 deliberately uses historical acknowledgement existence, including acknowledgement followed by immediate withdrawal. Do **not** reuse `everAcknowledged()` from `domain/commitment/commitment_state.dart`: that helper ignores grace-period withdrawals for a different purpose. Do not change its semantics. Existing append-only commitment/admission logs provide historical evidence; no participation table or fabricated history backfill.

Status presenter mapping is exact: `0 → Open / open-circle`, `7 → Needs more help / add-help`, `8 → Enough help / check`, `5 → Wrapping up / review / time`, `4,6 → Closed / completed`. Concrete Material icons: `circle_outlined`, `person_add_alt_1_outlined`, `check`, `schedule`, `task_alt`, respectively; pin uses `push_pin`. Semantic tones, in the same order: `tt.border`, `tt.warn`, `tt.good`, `tt.info`, `tt.textMuted`. Use localized state text and a separate pin glyph. Viewer involvement remains label/preview content.

### C3 — Storage and mutation transaction

Add two private, V2-only tables; do not expose them through Hasura CRUD or reuse `beacon_pinned`.

| Table | Columns / constraints |
|---|---|
| `constellation_anchor` | `id text PRIMARY KEY` (server `generateId('CA')`, preserved on moves); `viewer_id text NOT NULL REFERENCES "user"(id) ON DELETE CASCADE`; nullable `person_id text REFERENCES "user"(id) ON DELETE CASCADE`, `beacon_id text REFERENCES beacon(id) ON DELETE CASCADE`; `CHECK (num_nonnulls(person_id,beacon_id)=1)`; `x_units,y_units double precision NOT NULL`; `coordinate_space_version integer NOT NULL`; `revision bigint NOT NULL`; `placed_at timestamptz NOT NULL` |
| `constellation_anchor_cursor` | `viewer_id text PRIMARY KEY REFERENCES "user"(id) ON DELETE CASCADE`; `revision bigint NOT NULL DEFAULT 0`; nullable `last_placed_at timestamptz` |

Partial unique indexes: `(viewer_id,person_id) WHERE person_id IS NOT NULL` and `(viewer_id,beacon_id) WHERE beacon_id IS NOT NULL`. Add target-side indexes for FK cascades. Coordinate CHECK enforces version 1, both bounds and rejection of NaN/infinities; test PostgreSQL NaN behavior explicitly. The verified SQL account table is `public."user"` (Drift `Users`); use its existing text ID type, not a new Person table.

Use the next migration after the current baseline (`m0167.dart` if still free), register in `_migrations.dart`, add Drift table sources and register them in `tentura_db.dart`. Never renumber an existing migration.

Every accepted mutation runs inside one `TenturaDb.withMutatingUser` transaction:

1. Ensure the viewer cursor exists; lock it `FOR UPDATE` **before** finding/writing the anchor. This serializes different targets too, giving account-wide read watermarks. Validate upsert authorization inside this transaction, after obtaining the lock.
2. Use UPDATE-if-present / INSERT-if-absent under that lock, not an unchecked read followed by `ON CONFLICT` revision allocation. Database row triggers allocate revision by incrementing the locked cursor for INSERT/UPDATE/DELETE. For INSERT/UPDATE set `NEW.revision` and `NEW.placed_at = greatest(clock_timestamp(), last_placed_at + 1 microsecond)`; update `last_placed_at`. Clients cannot write either field.
3. Deleting an absent row still increments the cursor once and emits invalidation. This is an accepted unpin ordered after all preceding moves. For existing rows the DELETE trigger does this; do not increment twice in the repository.
4. Row triggers publish a transactional private invalidation for `[viewer_id]`. FK target deletion uses the same DELETE trigger, so other sessions learn removal. Viewer-account cascade needs no event if its cursor/account is already absent; never recreate a deleted account's cursor. Rollback rolls back cursor, row and notification together.
5. Return the anchor plus watermark for upsert, or typed target plus watermark for delete. No expected-revision conflict rejection: last server-accepted write wins. A later upsert after deletion is an explicit repin.

No persistent delete tombstones are needed: retain the viewer cursor after unpin, and return a complete authorized anchor projection with its watermark. Handle DB deadlock/serialization errors through the existing transaction-error boundary; test concurrent cascades and mutations. Never automatically replay a client write after an ambiguous network timeout.

### C4 — One field API, two read projections

Extend `constellationField(context, showClosed: Boolean = false, participatedOnly: Boolean = false, projection: FULL | ANCHORS = FULL)`. Add `constellationAnchorUpsert(targetKind, targetId, xUnits, yUnits, coordinateSpaceVersion)` and `constellationAnchorDelete(targetKind, targetId)`. JWT supplies viewer ID; no viewer input. Mutations use the default Constellation context for person authorization (the current UI exposes no context selector).

Keep current FULL fields (`loadedAt`, `context`, `peers`, `edges`, `requests`, cap flags) as the **automatic** snapshot and add:

```text
projection: FULL | ANCHORS
anchorProjection: {
  revision: String,
  anchors: [authorised stored anchor],
  pinnedPeers: [person], pinnedRequests: [ConstellationRequest],
  supportPeers: [person], supportEdges: [trust edge],
  serverFilteredBeaconIds: [ID], serverFilteredBeaconCount: Int
}
anchor = { targetKind, targetId, xUnits, yUnits,
           coordinateSpaceVersion, revision: String, placedAt: UTC timestamp }
```

`anchors` includes readable dormant anchors. `pinnedRequests` contains only server-filter-eligible requests. `serverFilteredBeaconIds` contains unique authorized, otherwise renderable pinned Beacons excluded by `showClosed` or `participatedOnly`; it returns no Request payload for those exclusions. Support is computed for eligible pinned targets. `serverFilteredBeaconCount` equals the unique ID list length. All lists have stable ordering; deduplicate entities by typed key and edges by `(src,dst,tier)`.

FULL reads automatic selection, authorized anchors, pinned targets, support and cursor in **one read-only REPEATABLE READ transaction** via `ConstellationFieldRepositoryPort.readSnapshot(viewerId, context, filters, projection)`, returning `ConstellationFieldSnapshot`. Keep constituent query helpers private in the adapter. Do not issue independent transactions through the current `_profiles` repository and call the result atomic; bind its profile lookup to the same database transaction. No external network reads inside this transaction. If no cursor exists, read watermark `0` without creating a row in this read-only transaction.

ANCHORS uses that same projection builder but skips automatic discovery queries. Return empty automatic arrays/false cap flags; client must replace **only** `anchorProjection`, retaining its automatic snapshot, `loadedAt`, filters and selection. Anchor-added targets/support may bring current authorized content into that layer; existing automatic content remains a timestamped snapshot. A FULL refresh replaces both layers. This avoids turning anchor notifications into discovery/lifecycle realtime. Switching either server filter or pressing Refresh requests FULL; local filters request no network read.

Hidden count is `size(serverFilteredBeaconIds UNION locallyFilteredEligiblePinnedBeaconIds)`, counted once per Beacon, never people, authorization omissions, density overflow or cancelled/draft/deleted records. “Clear filters” resets both server filters to false and all existing local filters to their current defaults; it does not enable Show closed. A default-hidden closed anchor may therefore remain hidden after clearing; keep Show closed available next to the count. Disable Clear filters if no filter differs from default.

GraphQL failures use stable extensions codes: `INVALID_TARGET`, `INVALID_COORDINATES`, `UNSUPPORTED_COORDINATE_SPACE`, `TARGET_UNAVAILABLE`. Nonexistent and unauthorized upsert targets share `TARGET_UNAVAILABLE`. Use existing authentication and client-version errors. Upsert response contains authoritative anchor and `revision`; delete contains target and `revision`.

### C5 — Membership, support and budgets

- Server budgets remain the existing automatic peer/request caps; client automatic peer budget remains `120`, satellite label budget remains the current viewport-dependent policy (base `3` per author, `150` total). Own-Request exemptions remain as shipped.
- Compute the authorized pinned layer and its minimal explanation closure **before** automatic budget allocation. Exclude already supplied pinned/support objects from charged automatic slots and continue selection to fill the normal budget if candidates exist. Deduplicate the union; do not merely union pins after an unchanged LIMIT that charged them already.
- Pinned Beacon closure includes author and the selected authorized path to ego, within `3` hops. Pinned person closure includes its selected path. Use existing two-tier path semantics and stable tie-breaks in `constellation_path_resolution.dart`; do not choose an arbitrary SQL shortest path. Add a server pure resolver with parity fixtures against the client resolver. Candidate lookup must range beyond the ordinary peer cap, but stay within the authorized three-hop graph.
- No path: retain target/author as residual, with the existing residual stub semantics, never a fabricated trust edge. Support-only nodes/edges disappear when their last visible dependent pin is hidden or unpinned; locally filtered pins also release their support. Shared support remains while another visible pin needs it. Do not prune an object also supplied by the automatic layer.
- Pinned Requests bypass per-author overflow, total label budget and client cap pruning; pinned people/support bypass the peer cap. Dense graphs may overlap; no anchor count limit, eviction, hidden pagination or auto-fit that silently omits pins. Viewport culling is allowed and must not remove targets from the logical graph/Text view.
- Map and Text derive from one composed presentation result. Text keeps its current non-spatial grouping; eligible pinned items are included even when normal satellite budgets are exhausted.

### C6 — Pure layout and graph adapter

Pass typed anchors, support IDs, node bounds, spacing and explicit prior-layout hints into layout. Store normalized coordinates in pure Dart values; convert to `Offset` only in the graph adapter. Extract the current `dart:ui` layout input/output into pure point/size/bounds values rather than adding Flutter objects to persisted/domain anchor types.

Resolve topology before placement; anchors never change parent/tier/ring metadata. Compute semantic ideals using the existing sector/residual/fan algorithms. Priority is ego → all pinned people/Beacons → support people → ordinary people → unpinned Beacons. Stable typed-key order breaks ties within automatic priority classes. Person and Beacon anchors are independent hard positions, including overlaps.

For each automatic node: try a prior hint only if parent, ring and viewport class are unchanged and it is collision-free; then its semantic ideal; then 64 candidates: radii `step * [1,2,3,4]`, 16 angles starting at the ideal radial angle, clockwise. `step = max(nodeWidth,nodeHeight) + spacing`. Discard candidates outside the C1 centre envelope or whose rendered bounds exceed the canvas. Apply the same envelope to semantic ideals and accepted hints, so Text-first pin can always persist its computed position without clamping. Collision uses rendered axis-aligned bounds including label/status/pin extents, inflated by half spacing on each object. If all valid candidates collide, choose the candidate with minimum total intersection area; tie by candidate index. Never move a pin, drop a node or enlarge the canvas. Pure inputs, sorted traversal and candidates must reproduce identical output.

`ConstellationLayoutAlgorithm.relayout` currently ignores `existingLayout` and graph `pinned`; amend it to supply explicit hints and anchors. Include these inputs in equality/hash invalidation. Do not treat `NodeBase.pinned` as persistence.

In the local graph package add optional, default-off node-drag callbacks, camera-interaction gating, scene-coordinate conversion and `GraphController.setNodePresentationPosition` (single-node layout override, not `mutate`/relayout). Use it for drag frames and attached edges only. Feed one shared node order to painting, labels and hit testing. Existing trust/forward/genealogy callers retain current behavior when hooks are absent.

### C7 — Interaction and reconciliation state machine

Feature state stores `confirmedProjection`, `projectionRevision`, typed pending command, account/load generations, and placement state `idle | draggingExisting | draggingNew | provisionalNew`. One local placement/write is active at a time; disable other pin/move/unpin actions while its request is pending, but leave camera and navigation usable. No per-frame HTTP calls.

| Event | Required transition |
|---|---|
| Touch long-press or mouse primary drag on non-ego node | Capture node after platform gesture slop/long-press rules; freeze current scene transform, preserve grab offset; `draggingExisting` if anchored, otherwise `draggingNew` |
| Two-pointer scale wins before capture | Camera owns sequence; no node movement or provisional state |
| Extra pointer after node capture | Node retains ownership; ignore extra pointers for movement; keep camera gated until every pointer in that sequence lifts/cancels |
| Existing-node drop | Upsert final position once, optimistic anchor/top order, one automatic reconciliation; restore camera when sequence is fully released |
| New-node drop | Enter `provisionalNew`, display Pin here/Cancel, zero writes and zero global reconciliation; camera resumes after sequence release |
| Pin here | Upsert once, optimistic anchor and one reconciliation |
| Cancel / Escape / route leave / switch to Text / filter or FULL refresh during placement | Cancel unsent placement, restore newest confirmed/computed position, no write; suppress late gesture-end callback |
| Pointer cancel / viewport geometry change during drag | Cancel drag safely and wait for pointer release before rearming camera; no write |
| Unpin | Optimistic remove + one reconciliation, submit one delete; never touch Favorites |
| Text Pin | Compute target's Map position with the same layout engine and current viewport inputs even if Map was never mounted; submit one upsert (button is explicit confirmation) |
| Incoming anchor refresh during drag/provisional/pending write | Update confirmed cache/watermark, defer presentation for that target only; apply confirmed positions for other targets immediately, without automatic-layer reflow until placement ends |
| Successful command | Adopt returned authoritative value only if not older than newest confirmed revision; fetch ANCHORS to settle concurrent deletion or remote movement |
| Failed command | Fetch ANCHORS once, restore newest confirmed state, one rollback reconciliation, one localized failure message; if offline, restore last known confirmation and mark sync pending until reconnect |

No blind mutation retry on transport failure: the server may already have committed. Preserve command reconciliation across route disposal in the owning use case; no emits to closed Cubits. On account change dispose subscriptions, cancel unsent placement and discard prior-account results. A remotely deleted target may be repinned by a later successful local drop (D26).

Use a load-generation token for every filter/context/account change; stale responses cannot overwrite newer state. Ignore older projection revisions. Equal revisions may still refresh authorization/membership (permissions can change without anchor writes); only the latest matching request generation may apply them. Subscribe before initial FULL load; coalesce hints to one in-flight ANCHORS read plus one queued rerun. Reconnect requests ANCHORS once. Remote echoes do not show snackbars. Reconciliation never changes the field timestamp unless a matching FULL result is accepted.

### C8 — Private invalidation and rollout

Add realtime kind `constellation_anchor`, aggregate ID = viewer account ID, payload event `insert|update|delete`; no target, position, title or revision payload is necessary. Recipient list is exactly `[viewer_id]` and is stripped before client delivery. Use existing bounded `entity_changes` publisher/fan-out, not Hasura subscriptions or polling. Actor echo must be enabled so both sessions of the same account converge.

Register the kind in `docs/contracts/realtime-entity-contract.json`, client `RealtimeEntityKind`, impact mapping and contract tests; only Constellation anchor projection is affected. Route subscription ownership through the Constellation use case and `RealtimeSyncPort`, with screen open/close lifecycle. Generic beacon/profile/relationship events must not silently turn this feature into a live discovery feed.

Release once all gates pass: choose the next unused **minor** client version from the then-current `pubspec.yaml`, set `kDefaultMinClientVersion` to that exact version, synchronize `web/index.html` bootstrap query and the `.env.example` comment. Check deployment overrides cannot lower the intended gate. Build/version/preload verification uses one `WEB_BUILD_ID`. No mixed-version support or anchor backfill.

## Ordered implementation packets

### P01 — Contract fixtures and domain types

**Files:** new `F/domain/entity/constellation_anchor.dart`, `F/domain/entity/constellation_anchor_projection.dart`, corresponding `S/domain/entity/` files; existing field entities and both Constellation repository ports; new journal. Read architecture/codegen rules before Dart edits.

Implement typed targets, validated coordinates, revisions, projection mode and server-filter values. Add serializable fixture data covering every C1/C2 outcome. Keep wire mapping in data/API. Update mock/fake constructors as contracts change; no behavior activation yet.

**Check:** pure coordinate/target/revision tests, including NaN, infinity, boundaries, unknown version and values above `2^53`; no domain import of Flutter, Ferry, SQL or UI introduced.

### P02 — Migration and storage adapter

**Files:** new migration and `S/data/database/table/constellation_anchors.dart`, `constellation_anchor_cursors.dart`; `_migrations.dart`, `tentura_db.dart`; new `S/domain/port/constellation_anchor_repository_port.dart`, `S/data/repository/constellation_anchor_repository.dart`.

Implement C3, cursor/row triggers, cascade handling, SQL indexes and typed repository results. Add a domain-owned transaction/snapshot operation instead of leaking `TenturaDb` into use cases. Reuse the existing notification-envelope publisher. Regenerate Drift/DI.

**Check:** disposable PostgreSQL tests for all CHECK/FK/unique constraints, owner isolation, same-target upsert race, different-target ordering, delete-vs-move, absent delete, monotonic placement time, rollback with no notification, both target cascades and viewer deletion. Run fresh migration and upgrade from pre-feature schema. Migrant is forward-only here: document coordinated application rollback retaining additive tables; do not invent/destructively run a down migration.

### P03 — Server membership and complete snapshot

**Files:** `S/domain/use_case/constellation_field_case.dart`, `S/domain/port/constellation_field_repository_port.dart`, `S/data/repository/constellation_field_repository.dart`; new `S/domain/constellation/constellation_path_resolution.dart`; field/anchor entities.

Implement C2/C4/C5, including batched participation, authorized dormant anchors, pinned-only authors, bounded-hop closure outside automatic caps, FULL/ANCHORS and consistent transaction watermark. Share the canonical selection/projection builder between reads and mutation validation; do not bypass `beacon_can_read_content`.

**Check:** extend `test/domain/use_case/constellation_field_case_test.dart` and `test/data/repository/constellation_field_repository_pg_test.dart`; new participation/path parity tests. Fixtures: cap+1 automatic candidates plus pins/support; no active Request for pinned person; readable non-discoverable pinned Beacon; blocked/unblocked target retains coordinates; author outside normal graph; shared support; no three-hop path; every C2 status/participation branch. Assert excluded IDs/counts do not leak and ANCHORS does not query automatic discovery.

### P04 — Authenticated V2 API

**Files:** new `S/domain/use_case/constellation_anchor_case.dart`, GraphQL `mutation/mutation_constellation_anchor.dart`; `query/query_constellation_field.dart`, `mappers/constellation_gql_maps.dart`, `custom_types.dart`, `query/_queries_all.dart`, `mutation/_mutations_all.dart`; DI sources.

Expose exact C4 signatures, non-null lists, enum validation, stable error codes and decimal revision strings. Use the actual GraphQL registry pattern; do not add another HTTP route. Authenticate before resolving any field/mutation.

**Check:** new `test/api/controllers/graphql/constellation_anchor_test.dart`: missing/forged viewer input, invalid kinds/coordinates/version, missing vs forbidden indistinguishable error, own-delete semantics, authoritative mutation results and projection mode defaults. Run API tests against the emitted schema, not mapper mocks alone.

### P05 — Client wire adapters and realtime contract

**Files:** `F/data/gql/constellation_field_fetch.graphql`; new `constellation_anchors_fetch.graphql`, `constellation_anchor_upsert.graphql`, `constellation_anchor_delete.graphql`; `F/data/repository/constellation_repository.dart`, `_mock.dart`; new `F/domain/port/constellation_anchor_repository_port.dart` and `F/data/repository/constellation_anchor_repository.dart`; `C/data/gql/schema.graphql`, `C/data/service/remote_api_client/build_client.dart`; `C/domain/entity/realtime/realtime_entity_change.dart`, `C/domain/port/realtime_sync_port.dart`, `packages/client/test/architecture/realtime_entity_contract_impacts_test.dart`, and the C8 manifest/contract tests.

Use operation names `ConstellationFieldFetch`, `ConstellationAnchorsFetch`, `ConstellationAnchorUpsert`, `ConstellationAnchorDelete`; register all in `_tenturaDirectOperationNames`. With the updated server running, apply/reload Hasura metadata (`./scripts/hasura_apply_metadata.sh`) and run `docker compose run --rm schema_fetcher` from the repository root. Validate `test/data/gql/direct_v2_schema_overlay_test.dart`; GraphQL documents use stitched `v2_*` input/enum names. Schema/Ferry output is never hand-edited. The anchors query calls the same field with `projection: ANCHORS`. Parse every boundary into domain values; fail malformed anchors rather than silently moving them. Supply accurate mock behavior, not an always-empty anchor stub.

**Check:** extend `constellation_repository_test.dart`; validate routing, enums, precision and mapping. Run server/client realtime contract tests, owner-only WS fan-out and actor echo, catch-up/coalescing tests. No unrelated surface gains anchor-triggered reloads.

### P06 — Pure composition, budgets and layout

**Files:** `F/domain/constellation_cap_policy.dart`, `constellation_density.dart`, `constellation_layout.dart`, `constellation_consts.dart`, `constellation_filters.dart`, `domain/use_case/constellation_field_case.dart`; new `F/domain/constellation_anchor_composition.dart`; `C/features/graph/ui/utils/tentura_layout_algorithms.dart`, `C/features/graph/domain/entity/node_details.dart`.

Implement C5/C6 and a typed presentation result reused by both views. Store full automatic snapshot separately from anchor/support overlay. Layout input contains prior hints explicitly; never upload them. Density reserves nothing for pins; automatic selection continues to its own full budget. Hidden support is recomputed without pruning automatic copies.

**Check:** existing Constellation cap/density/filter/path/layout tests plus new anchor composition/layout tests: person/Beacon independence, all pins survive budgets, topology changes preserve anchors, repeatability, collisions, exact overlapping anchors, exhausted candidates, hint eligibility, all four envelope corners and compact/expanded coordinate round-trip. Confirm Map/Text eligible-ID parity.

### P07 — Graph gesture adapter

**Files:** `G/graph_view.dart`, `configuration.dart`, `controller.dart`, `widget/nodes_view.dart`, `widget/labels_view.dart`; new `G/widget/node_drag_gesture.dart`; graph package public exports if required.

Implement optional C6 hooks, deterministic paint/hit order and the C7 pointer ownership rules. Gesture arena must arbitrate camera and node capture; merely toggling `panEnabled` inside a child listener is insufficient. Stop an in-progress position animation when capturing a node; drag uses displayed position and freezes other nodes. Release all pointer bookkeeping on cancel/dispose.

**Check:** new graph-package widget tests: pan/zoom without capture; scale-before-capture; additional finger after capture; remaining finger after primary lift; cancel; topmost overlap; only one node/incident edges change during movement; zero global layout calls per move. Run existing graph package tests to protect non-Constellation callers.

### P08 — Placement orchestration and live reconciliation

**Files:** new `F/domain/use_case/constellation_anchor_case.dart`; `F/domain/use_case/constellation_field_case.dart`, `F/ui/bloc/constellation_state.dart`, `constellation_cubit.dart`.

Implement the complete C7 state machine through use cases. Maintain one confirmed cache, optimistic overlay, generation guards and deferred target update. Replace `_rebuildGraph` clear/re-add behavior during drag with the presentation-position hook; full rebuild occurs only at defined reconciliation points. Preserve selected node if still visible; clear selection when its target leaves the composed result.

**Check:** new `test/features/constellation/constellation_anchor_case_test.dart` and `constellation_anchor_cubit_test.dart`, using completers to invert response order. Cover remote move during drag, remote delete then drop, echo-before-response, stale FULL after ANCHORS, equal-revision permission refresh, failed/ambiguous write, offline recovery, provisional cancellation, double confirmation, account change and route disposal. Count writes and layout reconciliations exactly.

### P09 — Map/Text controls, filters and status accessibility

**Files:** `F/ui/widget/constellation_body.dart`, `constellation_text_view.dart`, `constellation_filter_bar.dart`, `constellation_request_label.dart`, `constellation_request_preview_sheet.dart`; new `constellation_anchor_controls.dart`, `constellation_request_status_marker.dart`; graph `graph_legend_content.dart`; `C/ui/test_ids.dart`; both `packages/client/l10n/app_{en,ru}.arb`.

Read `material-3-flutter`, design-system rules/docs before widget edits. Use existing identity tile inside a Constellation-specific status/pin decorator; do not change Favorites or global Beacon tile semantics. Expose Pin/Unpin in person panel, Request preview and Text rows; Map-only placement confirmation is Pin here/Cancel. Existing anchors drag directly. Add Show closed, Only Requests I participated in, hidden-pin plural message and Clear filters with C4 behavior. Filter preferences are screen-session state, default off on reopen; only anchors persist across devices.

Map status/pin legend and Text semantics share one status presenter. Use `context.tt` semantic tones, sizing/spacing and `TenturaText`; add named design-system tokens only if no existing token fits. Labels/actions localized in both languages. Add stable IDs for target pin/unpin, Pin here, Cancel, filters, hidden count, state marker and pin marker; do not locate by translated text in browser tests.

**Check:** body/filter/text/preview widget tests and new `constellation_anchor_interaction_test.dart`: first pin confirmation, no unintentional save, keyboard cancellation, Text-first pin, dormant count, clear defaults, five distinct status cues plus independent pin marker, semantics at text scale 1 and 2, compact 390×844 and expanded 1440×900. Verify chosen foreground/background contrast ≥4.5:1 for text and ≥3:1 for meaningful graphical markers. No accessibility claim for two-dimensional keyboard repositioning (D25).

### P10 — End-to-end and failure acceptance

**Files:** new `packages/client/integration_test/constellation_pinning_test.dart`, `constellation_pinning_multiclient_test.dart`; reusable helpers/TestIds only as needed; journal.

Use real UI for drag/drop/pin, camera and filters. QA APIs may prepare users/topology/Requests and read server truth; they cannot substitute for the tested interaction. Use two sessions of the same account and a third unauthorized account. Assert persisted normalized coordinates, not screenshot pixel equality.

Required journeys: person without Requests; independent person/Beacon move; overlapping pins survive reload with correct topmost hit; unpin leaves Favorites; close→hide→Show closed→same anchor; cancelled always absent; each participation transition; authorization loss/restore and physical deletion; cap overflow with every eligible pin retained; stale cross-device move/delete; one failed mutation with rollback; reconnect; first-load Text pin. Run touch arbitration in widget tests with multiple pointers and a real mobile/touch browser where available; record unavailable hardware/browser coverage as blocked, not passed.

**Check:** focused browser scripts with target-by-target PASS/FAIL/BLOCKED and screenshot/checkpoint evidence. No skipped journey, API-only gesture substitute, blanket timeout increase or stale web bundle as acceptance.

### P11 — Full verification and release preparation

Run from the repository root unless a command specifies `cd`:

```bash
(cd packages/server && dart run build_runner build -d)
(cd packages/client && flutter gen-l10n && dart run build_runner build -d)
(cd packages/server && dart test test/domain/use_case/constellation_field_case_test.dart test/api/controllers/graphql/constellation_anchor_test.dart)
(cd packages/server && dart test --exclude-tags pg)
(cd packages/client && flutter test test/features/constellation test/data/gql/direct_v2_schema_overlay_test.dart)
(cd packages/force_directed_graphview && flutter test)
(cd packages/tentura_lints && dart test)
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
bash scripts/check-user-facing-terminology.sh
(cd packages/client && flutter test)
./scripts/run_client_integration_web_local.sh integration_test/constellation_pinning_test.dart integration_test/constellation_pinning_multiclient_test.dart
```

For PostgreSQL acceptance: create a uniquely named disposable database, configure `POSTGRES_DBNAME` for that database without printing credentials, apply all migrations with `packages/server/tool/run_migrations_once.dart`, prove `SELECT current_database()` matches, then run `(cd packages/server && dart test -t pg -j 1)`. Run new focused PG tests during P02/P03; this is the final serial suite. An empty/shared database is not acceptance. Run all realtime test files listed by the manifest for the changed kind, including WS protocol/fan-out and client impact tests.

Before browser execution check whether port 8888 is already bound and use the documented local integration runner; do not start a duplicate Flutter server. Follow `docs/local-integration-tests.md` for the stack. Record separately tests passed, infrastructure failures and unrun gates.

Apply C8 version edits only after source/testing is coherent. Follow the current `.github/workflows/pipeline.yml` web-build command and its defines, then, in `packages/client`, run `dart run tool/trim_web_deploy_artifact.dart`, `dart run tool/apply_versioned_web_assets.dart`, `dart run tool/generate_wasm_preload_artifacts.dart` and `dart run tool/verify_web_version_consistency.dart` in that order under the same `WEB_BUILD_ID`. Verify tracked `web/index.html` matches the source version, not just build output. Test below-minimum client rejection and current-client acceptance.

**Exit:** all required automated checks and browser journeys passed, or release explicitly remains blocked with exact evidence. Do not call generated code or a browser build alone acceptance.

### P12 — Product docs and coordinated activation

**Files:** `docs/features/constellation.md`, `docs/plans/constellation-edge-semantics.md`, `docs/README.md`, realtime contract/operations docs if changed, this plan and journal; version files from P11.

Update shipped behavior only when implemented and verified. Explain account-owned placement, dormant anchors, participation filter, state/pin legend, independent Favorites, and the narrow anchor-only realtime exception. Mark conflicting old cap/snapshot/layout claims superseded by this plan; preserve historical decisions as history.

Activation order: apply additive migration → deploy server with required version gate and actor echo → publish matching client/web assets → smoke-test current client and two-device anchor sync. If activation fails, roll back coordinated server/client artifacts and version gate together; retain anchor tables/data. Before restoring an older client that lacks pinning, state that anchors are retained but temporarily unavailable. Destructive schema removal is not a routine rollback.

**Done:** journal links every P01–P12 gate to evidence; no unresolved contract placeholders; all authorized pins survive filters/budgets/restarts according to D1–D37; no claim that pinning widens access or replaces Favorites.

## Related documents

- [`../features/constellation.md`](../features/constellation.md)
- [`constellation-edge-semantics.md`](constellation-edge-semantics.md)
- [`constellation-implementation-plan.md`](constellation-implementation-plan.md)
