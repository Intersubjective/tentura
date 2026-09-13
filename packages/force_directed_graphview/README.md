# force_directed_graphview

**Tentura vendored fork** of [pub.dev `force_directed_graphview` 0.6.2](https://pub.dev/packages/force_directed_graphview), resolved via the repo-root `pubspec_overrides.yaml`. Upstream badges and the stock `example/` tree are not maintained here.

## Architecture (stable scene API)

Graph **identity**, **topology**, **layout**, **transient presentation**, **camera**, and **rendered payloads** have separate owners. Production code uses **string node and edge IDs** (`GraphNodeId`, `GraphEdgeId`); render payload `==` / `hashCode` never keys layout, presentation, paint order, or drag.

### Layers

| Layer | Owns | Must not own |
| --- | --- | --- |
| **Pure scene** (`lib/src/scene/`, layout port) | `GraphTopology`, `SceneLayout`, `ScenePresentation`, tickets/tokens, `SceneLayoutAlgorithm` | Flutter, Tentura, persisted anchors, server revisions |
| **`GraphSceneController`** | Topology revision, layout subscription, accepted layout, presentation holds, layout transition, notifications | Domain entities, authorization, optimistic command outcomes |
| **Flutter adapter** (`GraphView`, widgets, `GraphController`) | `TransformationController`, viewport, gesture capture, explicit camera ops | Mutable algorithm working state, implicit camera reset on topology |
| **Tentura UI adapters** (`packages/client/…/graph`, `…/constellation/ui`) | Map domain layout results → `GraphLayoutFrame`, stable ID encoding, drag handoff tickets | Normalized Constellation anchor coordinates in scene types |

**Forbidden dependency directions:** Constellation **domain** → this package or `package:flutter`; this package → `package:tentura`; layout algorithms → render payload types as map keys.

Constellation anchor persistence, normalized `[-10, +10]` coordinates, and placement policy live under `packages/client/lib/features/constellation/domain`. The UI adapter converts a completed domain layout to terminal `ScenePoint` values only at the boundary.

### Layout tickets and frames

Asynchronous layout is explicit:

1. `requestLayout` mints a monotonic **`GraphLayoutTicket`** (controller-owned identity + topology revision + generation).
2. A **`SceneLayoutAlgorithm`** receives a **`GraphLayoutRequest`** (canvas size, ID-keyed nodes/edges, optional `previous` layout hint) and yields **`GraphLayoutFrame`** values (sequence, complete position map, `isTerminal`).
3. The controller accepts a frame only when the **full ticket matches** the active ticket, sequence increases strictly, and positions cover **exactly** the active topology node IDs.
4. The stream must end with **exactly one** accepted terminal frame. Stale, partial, duplicate-sequence, and post-terminal frames are ignored; malformed frames fail the ticket.
5. **`releaseOnTerminal`** presentation tokens are cleared in the **same notification** as terminal layout acceptance (no flash between override and accepted layout).

Presentation overrides use opaque **`GraphPresentationToken`** values; stale tokens cannot move a newer drag.

Resolved position for a node in the active topology:

```text
override → transition → accepted layout → seed (new IDs only)
```

### Public controller surface (Tentura)

- **Topology:** `GraphController.reconcileTopology` / `applyTopology` on the underlying `GraphSceneController` — camera is preserved; no `clear(recenter:)`.
- **Layout:** `requestSceneLayout(SceneLayoutAlgorithm, releaseOnTerminal: …)`; algorithms implement `SceneLayoutAlgorithm` and emit ticketed frames (e.g. `FruchtermanReingoldSceneLayoutAlgorithm`, client `ConstellationSceneLayoutAlgorithm`).
- **Drag presentation:** `beginNodePresentationDrag`, `updatePresentation`, `cancelPresentation`, `clearPresentationForNodeId`.
- **Camera:** explicit `resetCamera`, `fitCamera`, `focusCamera`, `setCameraInteractionGated` — never as a side effect of topology updates.
- **Rendering:** one immutable `GraphSceneSnapshot` per paint/hit-test pass; node paint order is `List<GraphNodeId>`.

### Compatibility removal (M07)

The following **removed** APIs are not supported; do not reintroduce them:

- `GraphLayout` / `GraphLayoutBuilder` keyed by `NodeBase`
- `GraphLayoutAlgorithm` / `LegacyGraphLayoutAlgorithmAdapter` / `BoundSceneLayoutAlgorithm`
- `useLayoutAlgorithm`, `clear(recenter:)`, node-instance presentation setters
- Layout or presentation maps keyed by render object identity

`Node` / `Edge` remain optional **payload** types for builders and painters; scene state is always ID-keyed.

Further normative detail: `docs/plans/force-directed-graphview-scene-decoupling-plan.md` in the Tentura repository.

## Tentura-specific rendering fix

Nodes and edges whose endpoints lack a layout position yet are skipped during rendering instead of asserting in layout lookup. Positions arrive from async layout streams, so new topology can be position-less for a frame; with `LazyBuilding.none` the stock package could crash on null positions.

## Fruchterman–Reingold scaling

Time complexity is `O(N² + E)` per iteration. Large graphs need bounded iteration counts or non-FR layouts.

## License

[MIT](https://opensource.org/license/mit/)
