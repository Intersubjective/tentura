# Constellation: always-interactive architecture (issue #235 and beyond)

Status: **proposal, rev 2** (2026-10-06). Rev 2 records the owner's decisions (§6) and revises the freeze model (§3.3) and the layout acceleration and time-slicing approach (§3.4). Related: #231, #232, #233, #234, #235.

## 1. Problem

After a node is dropped on the Constellation field, the next drag of that node or any other node pans the camera instead. The drag starts working again only when "the other nodes move by themselves". Issue #235 explains the immediate cause: the drag permission is tied to the anchor write plus a full projection re-read.

That gate is a symptom. Underneath it, the pipeline breaks one principle at three layers:

> **The user's hand must never wait for the network, the layout, or a rebuild.**

| Layer | How it breaks the principle today |
|---|---|
| Interaction | The drag permission (`canDragNode` → `placementActionsEnabled` → `AnchorCase.hasPendingWrite`) depends on server I/O. A blocked node turns into empty canvas, so the camera pans. |
| State | Writes are single-flight (`_pendingWrite`), and a concurrent write is *discarded*. The drop handler awaits the network. The optimistic state is visual only; the domain sees it after the recovery read. `load()` and recomposes land mid-drag with no deferral. |
| Layout | Every reconcile is a full, synchronous O(66·N²) greedy placement on the UI thread. It runs even for a selection tap. Every accepted layout tweens all nodes for 350 ms. Previous positions are only soft hints, so nodes nobody touched move. |
| Render | Every controller notify (each pointer move, tween tick or camera tick) rebuilds every node widget, re-runs O(L²) label placement and repaints all edges. |
| Server | A mutation returns `{anchor, revision}` only, which forces a separate ANCHORS read. That read pays the full visibility cost (MR RPC, all trust edges, double `beacon_can_read_content`, 4-query profiles). The writer's own write echoes back with no revision, so a second ANCHORS read races the recovery read. Reads have no versioning or not-modified path. |

"Solve for good" means changing the **contracts** between these layers. Patching the gate alone isn't enough.

## 2. Target invariants (the definition of done)

These are testable, and every phase below is measured against them.

- **I1. Input is never gated on I/O.** A pointer down on a draggable node always starts a node drag, whatever is in flight. Draggability depends only on what the node is (kind, ownership), never on network state.
- **I2. While the hand is on the graph, the graph holds still.** During a drag, no data refresh, recompose or layout changes *any* node, whether dragged or not. Incoming data is buffered and applied after release as one smooth transition. A resize never aborts the drag.
- **I3. Positional stability.** A node the user placed never moves unless the user moves it. A server failure doesn't move it either: it stays put and is marked "not saved" (§3.1). A free node moves only when its inputs change (new or removed neighbour, collision with a newly placed node). It moves by the minimum needed, and only that node animates.
- **I4. Frame budget.** With N = 300 nodes on a mid-range laptop running the web build:
  - drag frame under 8 ms of UI-thread work;
  - pan/zoom frame under 8 ms;
  - no single task over 50 ms (no long task) after drop, refresh or selection.
- **I5. Drop to next drag possible: 0 frames.** Drop to persisted: roughly one mutation round trip, with no follow-up read on the happy path.
- **I6. One network effect per user intent.** A drop is one mutation request, including a cluster drop. Your own echo is never refetched. Repeated reads of unchanged data cost a "not modified".

## 3. Target architecture

The model is the one used by collaborative canvases (Figma, Linear, Excalidraw, Replicache-style clients):

```
            ┌──────────────── UI thread, every frame ────────────────┐
 pointer ──►│ InteractionController (state machine; owns the hand)    │
            │   └─ writes drag positions straight into the scene      │
            └───────────────┬────────────────────────────────────────┘
                            │ intents (drop = PlaceIntent)
                            ▼
 ┌────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────┐
 │ FieldStore         │   │ PlacementOutbox          │   │ LayoutService         │
 │ server snapshot,   │   │ pending ops, LWW/target, │   │ incremental, stable,  │
 │ versioned, single- │   │ serial flush, rebase on  │   │ time-sliced, spatial  │
 │ flight refresh     │   │ confirmed revision       │   │ index                 │
 └─────────┬──────────┘   └────────────┬─────────────┘   └──────────┬───────────┘
           │ confirmed                 │ pending overlay            │ positions
           └────────────► desired = confirmed ⊕ pending ◄───────────┘
                                   │ (pure, memoised compose)
                                   ▼
                          Scene (layered render)
```

### 3.1 PlacementOutbox: optimistic writes with a local intent log

This replaces `_pendingWrite` single-flight and the `placementActionsEnabled` gate.

- Every drop, pin or unpin becomes an **op** `{clientOpId, target, kind: upsert|delete, position, baseRevision}`. It is appended to an in-memory outbox keyed by target, and **the last write wins per target**. A second drag of the same node before the first write lands replaces the queued op. If that op is already in flight, the new op is queued behind it.
- **Desired state = confirmed projection ⊕ pending ops.** The composer and layout always consume desired state, so the UI never waits. This one rule removes the drag gate, the "hold drop presentation" hand-off dance, and the snap-back race.
- **Flush:** one in-flight request at a time per viewer. Writes stay serial on the server, which keeps the per-viewer revision counter simple. Each request carries the *batch* of queued ops (§3.6), so a cluster drop is one request.
- **Ack:** the server returns the new revision plus the authoritative rows for the touched targets. The outbox drops the acked ops and *rebases*: confirmed ← server rows, and pending ops still queued stay on top.
- **Failure UX (decided):** the node **stays where the user put it** and gets a **"not saved"** marker. The copy frames it as a server-side problem, not the user's mistake. This applies both to a transport failure (retried automatically with backoff) and to a server reject. Other ops are unaffected. The marker offers "retry" and "discard my move"; discard reverts that target to confirmed. A quiet "saving…" cue shows only if an op is in flight for more than about 1 s. `syncPending` becomes "outbox has unsaved or failed ops". A desired position that is unsaved is still desired state, so layout treats it as anchored (I3).
- **Echo suppression:** a realtime `constellation_anchor` hint whose revision is at or below the confirmed revision is ignored (needs §3.6, revision in the payload). The recovery read disappears from the happy path. It remains only as a resync after transport failure or a revision gap.
- **In-memory only (decided).** The outbox isn't persisted across reloads; an unsent or failed move is lost on a hard reload.

Domain placement: `features/constellation/domain/` holds the port plus a pure outbox model that can be unit tested without Flutter. The data side implements the batch mutation.

### 3.2 FieldStore: one owner of server state and refresh

- It owns the FULL snapshot plus its **version stamp** (§3.6). There is one single-flight refresh loop for everything: realtime hints, catch-up, tab resume, filters and preflight. Requests are coalesced, cancelled when superseded, and paused while the tab is hidden. ANCHORS reads go through the same visibility gate (#234 left gaps here).
- `preflightRequestAction` stops doing a FULL fetch. It asks for the single request it needs, or trusts the current snapshot plus a server-side check at action time.
- It publishes **diffs**, not whole snapshots (added, removed or changed ids per entity type). That is what lets the layout be incremental (§3.4) and the scene update only what changed (§3.5).

### 3.3 InteractionController: a gesture state machine that owns the hand

States: `idle → pressing(node|canvas) → dragging(cluster) → settling → idle`, plus `panning` and `composing`.

- **Arbitration is decided once, at pointer down, from geometry and node kind only.** A hit on a draggable node claims the pointer *synchronously*: camera pan and scale are disabled in the same event, not one post-frame later (`graph_view.dart:299-322` today). A miss goes to the camera. "Node exists but is busy" doesn't exist any more (I1).
- **Whole-graph freeze (decided).** While `dragging`, the *entire* graph is frozen, not just the dragged cluster. This is less confusing for the user and simpler than per-target filtering. Every scene-changing input is put into one **buffer gate** in front of the composer: FieldStore diffs, outbox acks and rebases, label-budget recompose, composer candidate polls, and the layout results that would follow from them. Diffs are coalesced in the buffer (latest snapshot or version wins; diffs merge by id). Today's partial mechanisms (`deferredRefreshTargets`, `deferAutomaticReflow`, `_placementBusy`) are replaced by this one gate.
- **On release** the gate opens once. The drop's `PlaceIntent` and all buffered data are composed together into **one** desired state and **one** incremental layout. The scene then **animates smoothly** from the current on-screen positions to the new ones (§3.4 "Animation"). That is the only moment nodes the user didn't touch may move, and it is visibly caused by the user's own release, not by a background event.
- Things that are not data still apply during a drag: camera auto-scroll at edges, the hover or drop-target highlight, and the dragged nodes' own positions.
- Viewport or constraint changes (notices appearing above the canvas) re-project the camera. They **do not abort the drag** (`controller.dart:915-922` today).
- On release it emits a `PlaceIntent` to the outbox and goes straight to `idle`. `settling` is only a visual state (a short snap animation), not a lock.
- Fix the dead tap resolver while here: `identical(frame.snapshot, controller.renderSnapshot)` is always false, because `renderSnapshot` allocates a new snapshot per call (`constellation_body.dart:779-783`). Compare a monotonically increasing scene revision instead.

### 3.4 LayoutService: stable, incremental, never a long task

- **Stability contract (I3):** the layout input is `previousPositions + diff`, not "everything, with soft hints". Placed (anchored) nodes are fixed obstacles. Free nodes that already have a position are **kept as hard constraints** unless (a) their inputs changed (ring, author, support path) or (b) a newly placed or anchored node now overlaps them. Then only they are re-placed, with a minimum-displacement search starting from the old spot. New nodes are placed into free space. A full layout runs only on the first load, on a filter change, or on an explicit "tidy up".
- **Complexity: decided by measurement, not up front.** The hot loop is "score K candidate rects against all placed obstacles", currently O(K·N²) per full run. Whether an acceleration structure pays off at a few hundred nodes, once build and invalidation costs are counted, is an empirical question. Step P5a is a micro-benchmark with N = 100/300/600/1000 realistic node footprints and K ≈ 66, measuring full layout, incremental (diff of 1–10 nodes) and build-plus-invalidate cost. Candidates:
  - brute force (baseline, plus cheap wins: AABB early-out, precomputed rects, no allocation in the loop);
  - **sweep-and-prune**: obstacles kept sorted by x, binary search for the candidate's x-interval. Trivial to maintain incrementally;
  - **uniform grid / spatial hash**: cell ≈ median node size, O(1) insert and remove. Suits near-uniform node sizes;
  - **dynamic AABB tree (BVH)** with incremental insert and refit. Wins on very non-uniform sizes or large N, but is costlier to maintain;
  - **R-tree / quadtree**: included only if the above leave a gap.
  Pick the simplest structure that keeps an incremental layout under about 1 ms and a full layout's total under about 30 ms of work at N = 300. If brute force already meets that, keep brute force. Fixing the O(N²) id lookups in `_replaceNodeAndEdgeSets` and `_profileFromPeer` with id maps is unconditional, because it is pure overhead.
- **Threading reality:** the client is web-first, and on web `compute()` and isolates run on the **same thread** (dart2js and current wasm builds). Moving work "to an isolate" doesn't help there. The method is *incremental plus time-sliced*:
  - an incremental layout touches only the few nodes in the diff, typically under 1 ms;
  - a full layout runs as a cooperative job driven by an **adaptive slice controller** with a **4 ms setpoint** per frame. It doesn't use fixed chunks:
    - each slice measures elapsed time with a `Stopwatch` and keeps an EWMA of per-item cost;
    - the next batch size comes from congestion-control-style **AIMD**: additive increase while slices finish under the setpoint, multiplicative decrease (×0.5) on overshoot. A per-item-cost estimate seeds the first batch (setpoint ÷ EWMA cost), so the controller converges in a few frames;
    - a hard cap (e.g. 8 ms) bounds a single slice, so a mis-estimate can't make a long task;
    - slices are scheduled through `SchedulerBinding.scheduleTask` at idle priority, so they never compete with an input frame;
    - an incoming pointer down pauses the job (the graph freezes anyway, §3.3), and a newer layout request cancels it;
    - the controller is a small generic utility, reused for label placement and other O(N) recomputes;
  - native builds can still use a real isolate behind the same `LayoutService` port.
- **Animation:** tween only the nodes whose target moved more than a few px, from their *current on-screen* positions, so an interrupted transition doesn't jump. Never tween a node the user just placed. Remove the global 350 ms all-node tween. The post-release transition (§3.3) is the main use: buffered data plus the drop become one smooth reflow.
- **"Tidy up" action (decided).** Because the field no longer re-optimises itself, a "Re-arrange" action runs a full stable-seeded layout of free nodes. Anchored and user-placed nodes stay fixed. The action **appears only after the user has moved something** in this field (outbox has had at least one op this session, or any user anchor exists), and the transition animates like any other.
- **Triggers:** a selection tap, label-budget change or highlight never triggers layout. Those are paint-only concerns. Today `_rebuildGraph` always schedules a layout, including in `selectRequest`/`selectPerson`. `graphSceneLayoutAlgorithm` must be a stable instance, so `GraphView.didUpdateWidget` stops tearing down the ticker and re-requesting a layout with no hand-off tokens.

### 3.5 Scene rendering: layers split by how often they change

| Layer | Changes when | Technique |
|---|---|---|
| Edges (static) | Topology or layout changes | One painter with real `shouldRepaint` (revision compare). Cache to a `Picture`, and draw camera scale through the canvas transform, not by repainting on every `cameraRevision`. Reuse `Paint` objects. |
| Nodes | Per node: data or position change | One widget per node, driven by a **per-node `ValueListenable<Offset>`** inside a `RepaintBoundary`. A drag move updates one listenable, so one node moves and nothing else rebuilds. No whole-tree `AnimatedBuilder` on the controller. |
| Dragged cluster edges | Every drag frame | A small "live edges" painter for edges incident to the frozen set. Static edges stay cached. |
| Labels and overlay | Topology, layout, or zoom *bucket* change | Label placement is computed per (layout revision, zoom bucket) and cached. Pan is a pure translate of the overlay layer. Grid index for `occupied` makes it O(L) instead of O(L²). |
| Selection or highlight | Selection | Paint-only. Never a recompose or layout. |

The body's `BlocBuilder` must stop listening to `graphRevision`. The scene subscribes to the store or controller directly. Cubit emits are for chrome (app bar, sheets, notices), not for the canvas.

### 3.6 Server protocol

Per the no-legacy-client rule, this ships in one release together with `kDefaultMinClientVersion`.

1. **`constellationAnchorsApply(ops: [{clientOpId, kind, targetKind, targetId, position}])`**
   - One transaction, one cursor lock, one authorization pass, one MR call for person targets.
   - Returns `{revision, results: [{clientOpId, status: ok|rejected, reason?, anchor?}], delta}`. `delta` holds the pinned records, support peers and edges for the touched targets, computed inside the same transaction from the visibility already needed for authorization.
   - This removes the recovery read (I5) and the N serial cluster mutations (I6). It also trims the existing write path's extra round trips (discarded watermark read, direct `person_visible_peers_symmetric` instead of the memo).
2. **Revision in the anchor notification payload, emitted once per statement, not per row** (`m0193.dart:2794` trigger). This enables echo suppression in §3.1.
3. **Versioned reads:** each snapshot returns `version = (anchor revision, mr_publish_epoch, direct_trust_current_version(), beacon change seq)`. `constellationField(ifVersion:)` returns `notModified` without rebuilding. Next step: a short-TTL per-viewer cache of the visible set and discoverable list keyed by the same stamp. That attacks #233's ~200 ms discoverable cost on repeat reads.
4. **Delta reads (later):** `constellationFieldDelta(sinceVersion)`, driven by the aggregate ids that realtime hints already carry. FieldStore (§3.2) is designed so it can consume this when it exists.
5. **Lean profile lookup** for constellation (name, handle, image in one query) instead of the 4-query public-record batch.
6. **Visibility-change hints:** trust, block and MR epoch changes currently send no constellation hint, so the field goes stale. With versioned reads a cheap "maybe changed" hint is safe, because an unchanged read costs a `notModified`.

Authorization stays where it is. Read-side filtering is not loosened. Caches only reuse what is already computed, keyed by an epoch or version that fails closed. Leak and oracle hardening remains deferred per the project policy; this plan neither fixes nor regresses it.

### 3.7 Decomposing the god-cubit

`constellation_cubit.dart` (about 3,100 lines) currently owns fetching, write orchestration, composition, graph building, layout hand-off, the composer overlay, preflight and filters. Target:

- `FieldStore` (domain use case plus data repo): server state, refresh, versioning.
- `PlacementOutbox` (domain): §3.1.
- `ConstellationComposer` (pure domain function, memoised on input identities): desired state to presentation.
- `LayoutService` (UI utils behind a port): §3.4.
- `InteractionController` (UI): §3.3.
- `ConstellationCubit`: thin. It holds chrome state (filters, view mode, selection, sheets, notices) and wires the parts together.

The composer loop also needs fixing. The screen's composer `BlocListener` has no `listenWhen` and calls `enterComposing`, which means a full recompose and relayout on **every pointer move**, plus a 4 s `fetchForwardCandidates` poll. Composer positions belong in the InteractionController's per-node listenables, not in a recompose.

## 4. Phased delivery

Each phase ships on its own, keeps tests green, and is measured against §2.

| Phase | Scope | Fixes | Size |
|---|---|---|---|
| **P0. Instrument** | Timeline marks: `drop→draggable`, `drop→acked`, layout ms, scene build ms, long tasks over 50 ms. A dev-only perf HUD. A benchmark fixture with N = 100/300/600 synthetic nodes (widget test plus web profile run). | Baseline numbers for I4 and I5 | S |
| **P1. Unblock the hand** | `PlacementOutbox` (in-memory, LWW, serial, still on the existing single-op mutation, one request per op, cluster = sequential ops). Draggability no longer depends on I/O. "Not saved" marker with retry/discard. Recovery read moves to background resync (only on failure or revision gap). Synchronous camera claim on pointer down. Tap resolver fix. | #235 for good, the "pans instead of drags" class, snap-back races | M |
| **P2. Freeze and smooth reflow** | Whole-graph buffer gate during drag (replaces `deferredRefreshTargets` etc.). One coalesced compose, layout and animated transition on release. Resize doesn't abort. Layout stability contract (hard-keep free nodes). Per-node tween from on-screen positions, no global tween. No layout on selection. Stable layout-algorithm instance. "Re-arrange" action after the first user move. | "Nodes move by themselves", drag aborts on notices, mid-drag yanks | M |
| **P3. Server protocol** | `constellationAnchorsApply` batch plus delta. Revision in the notify payload, one per statement. Echo suppression. Lean profiles. Then versioned reads with `notModified`. | I5, I6, half of the #233/#234 load | M–L |
| **P4. Render layering** | Per-node listenables. Cached edge picture plus live-edge painter. Overlay cache per zoom bucket, grid-indexed label placement. Canvas off the cubit's `graphRevision`. | I4 at N = 300 | M |
| **P5. Incremental, time-sliced layout** | **P5a:** benchmark brute force vs sweep-and-prune vs grid vs BVH (§3.4) and pick by numbers. **P5b:** diff-driven incremental layout, id maps in `reconcileTopology`. **P5c:** adaptive AIMD slice controller (4 ms setpoint) for full layout and label placement. | Long tasks after refresh, scaling past N = 300 | M |
| **P6. Decompose** | Split the cubit along §3.7. Fix the composer recompose loop and poll. Done incrementally inside P1–P5 where a piece is touched (the outbox lands as its own class in P1, the store in P3). | Maintainability; stops regressions of I1/I2 | ongoing |

P1 alone removes the user-visible bug. P2 removes the "moves by itself" impression. P3–P5 make it scale.

## 5. Verification

- **Domain unit tests** for the outbox, using a fake repository with manually completed `Completer`s:
  - drag during in-flight write → op queued, LWW within the queue;
  - partial reject → only that target reverts;
  - transport failure → retry, then `syncPending`;
  - echo at or below confirmed revision → no fetch;
  - revision gap → one resync.
- **Widget tests** with a pending-write completer:
  - pointer down on node B while A's write is in flight → `onNodeDragStart(B)`, camera not panned;
  - field refresh landing mid-drag → **no node moves** until release, then exactly one compose and layout, and an animated transition;
  - failed write → node stays at the drop position with a "not saved" marker; retry succeeds and the marker clears; discard reverts;
  - the "Re-arrange" action is hidden before the first user move and shown after it;
  - a notice appearing mid-drag → drag continues;
  - a selection tap → zero layout runs (counter on `LayoutService`).
- **Stability property test:** for random diffs that don't touch node X's inputs, X's position is unchanged.
- **Slice controller:** a unit test with a fake clock and a synthetic per-item cost that steps up or down mid-job. The batch converges to the 4 ms setpoint within a few slices and never exceeds the hard cap.
- **Perf:** a P0 benchmark fixture asserts the I4 budgets in a profile-mode run (manual or CI-optional). Web e2e (`run_client_integration_web_local.sh`): drag A, immediately drag B, assert both persisted and no pan.
- **Server:** pg tests for `constellationAnchorsApply`:
  - batch atomicity, per-op reject;
  - one notification per statement, carrying the revision;
  - `notModified` when the version is unchanged and a fresh build when any stamp component bumps.

## 6. Decisions (owner, 2026-10-06)

1. **Failure UX:** the node stays where the user put it, marked **"not saved"**, with copy that frames it as a server problem. Retry and discard are available (§3.1).
2. **"Re-arrange" action:** yes. It appears only after the user has moved something themselves (§3.4).
3. **Ordering:** the server protocol (P3) goes before render layering (P4).
4. **Outbox persistence:** in memory only.
5. **Freeze scope:** the whole graph freezes while a node is in hand. Buffered data is applied after release as one smooth transition (§3.3).
6. **Acceleration structures:** chosen by benchmark (P5a). No spatial structure is built unless measurements at realistic N show it beats brute force, including its build and invalidation cost.
7. **Time slicing:** an adaptive, congestion-control-style (AIMD) batch controller with a 4 ms setpoint, not fixed chunks (§3.4).
