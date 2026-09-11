# Constellation pinning — product and technical plan

Status: architecture decisions resolved; implementation decomposition pending.
Decisions in this document are not shipped product behavior until implemented.

Date: 2026-09-10.

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
  participation. The exact participation predicate remains to be decided.

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
The exact state dimension and visual mapping remain to be decided. Today the
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

## Existing-system constraints

- `ConstellationField` currently projects peers, trust edges, and active
  discoverable beacons; it has no viewer layout preferences.
- `computeConstellationLayout` currently performs a deterministic three-pass
  layout: path tree, residual ring, then Request satellites.
- `ConstellationLayoutAlgorithm.relayout` recomputes all positions and ignores
  both `existingLayout` and `NodeBase.pinned`. Toggling the graph library's
  `pinned` flag alone cannot implement this feature.
- The graph canvas is currently a fixed `4096 × 4096`, with ego at its centre.
- The existing `beacon_pinned` / Favorites feature means “saved Request”; it is
  not spatial layout state. The two meanings must not be coupled accidentally.
- The live Constellation read path is already a Tentura V2 boundary: the server
  `ConstellationFieldCase` composes authorization-aware repository reads, while
  the client consumes a `ConstellationRepositoryPort` returning domain
  entities. Anchor wire and persistence types therefore need not leak into the
  layout function or UI state.
- Both current person and Beacon identifiers are stored as `text`, but the
  referenced rows live in different tables. A single polymorphic `target_id`
  column would therefore lose ordinary PostgreSQL foreign-key enforcement.
- Anchors cannot widen person visibility, beacon content authorization, or
  discoverability.

## Emerging layout model

The layout becomes constraint-based rather than a full deterministic rewrite:

1. Place ego at the canonical centre.
2. Materialize authorized pinned targets and reserve their viewer-chosen
   positions as immovable obstacles.
3. Resolve the current path tree and edge wiring independently of those
   positions.
4. Place unpinned people around the fixed obstacles while preserving current
   graph semantics where possible.
5. Place pinned Requests at their own anchors.
6. Place unpinned Requests as author satellites, avoiding pinned nodes and other
   occupied bounds.

Pinned coordinates are hard constraints. Pinned-to-pinned overlap remains
viewer-authored under D20–D21; automatic-node crowding follows D35.

## Accepted architecture boundary

- Domain entities describe anchor targets and ego-relative graph coordinates.
- A domain-owned repository port loads and writes the viewer's anchors.
- The data layer implements the port using server APIs and maps wire data to
  domain values.
- A Constellation use case composes the field projection and anchor projection,
  applies authorization-safe absence semantics, and supplies pure layout input.
- The Cubit handles interaction state and optimistic presentation but does not
  own persistence or geometry rules.
- The pure layout function accepts anchors explicitly; UI code does not mutate
  positions behind the domain layout contract.

## Resolved batch topics

All owner decisions listed below were resolved by D28–D37. The next planning
step is mechanical decomposition into exact files, migrations, tests, and
activation gates rather than further product questioning.

The resolved owner-decision batch was:

1. Dormant-anchor retention and authorization-safe omission.
2. Field snapshot shape and server-side lifecycle/participation filtering.
3. Typed anchor mutation surface and validation responsibility.
4. Cross-device invalidation while Constellation is open.
5. Versioned coordinate envelope and camera bounds.
6. Stability policy for unpinned nodes between in-session reconciliations.
7. Reflow timing during provisional and persisted node drags.
8. Placement priority and deterministic crowding fallback.
9. Exact Request lifecycle/coverage marker matrix and legend semantics.
10. Coordinated rollout and deliberate mandatory-client-version policy.

Implementation slicing and verification detail follow from these decisions and
do not require a separate product choice unless the resulting evidence gates
expose a new trade-off.

## Verification outline

- Pure layout tests: fixed-anchor invariance, topology changes without anchor
  movement, independent person/Request anchors, collision avoidance for dynamic
  nodes, deterministic output.
- Use-case tests: composition of field and anchors, dormant or unauthorized
  targets, caps, and concurrent update results.
- Repository/API tests: viewer ownership, target validation, normalization,
  deletion, and authorization loss.
- Widget tests: drag → pin, move pinned target, unpin, refresh persistence, and
  Map/Text parity.
- Cross-viewport tests: the same account-level graph position on compact and
  expanded surfaces.

## Related documents

- [`../features/constellation.md`](../features/constellation.md)
- [`constellation-edge-semantics.md`](constellation-edge-semantics.md)
- [`constellation-implementation-plan.md`](constellation-implementation-plan.md)
