# Force-directed graph scene decoupling implementation journal

## Scope

- **Objective:** Implement `docs/plans/force-directed-graphview-scene-decoupling-plan.md` end to end while preserving all existing unrelated worktree changes.
- **Repository:** `/home/vader/MY_SRC/tentura`
- **Branch / starting HEAD:** `feature/pin_constellation` / `d84acc9403392b0759e399a5cf50b43ebd768000`
- **Plan owner:** Cursor Plan Overseer using fresh sequential `composer-2.5` workers.

## Starting worktree boundary

The following paths predate this plan and are never to be staged, amended, reverted, or otherwise changed by this work:

- `CONTEXT.md`
- `docs/plans/inbox-activity-ia-architecture.md`
- `packages/force_directed_graphview/analysis_options.yaml`
- `CLAUDE.local.md`
- `dart-defines`
- all pre-existing untracked files under `docs/plans/`, **except** this journal when updated by an active plan worker
- `graph-ego-neighbors-layout-issue.md`
- `key.fb`
- `out.key`
- `product_testing_compact_buglist.md`
- `product_testing_detailed_report.md`
- `tg_style_research.md`

The protected `packages/force_directed_graphview/analysis_options.yaml` change is explicitly called out by the plan. Baseline package analysis has existing diagnostics; it is evidence only, not a green result.

## Ordered manifest

| Unit | Status | Dependency | Required commit behavior |
| --- | --- | --- | --- |
| M00 baseline behavior inventory | **accepted** | none | `test(graph): characterize scene identity and lifecycle` |
| M01 pure scene value types | **accepted** | M00 accepted | `feat(graph): add stable scene identity values` |
| M02 ID-keyed layout port and legacy adapter | **accepted** | M01 accepted | `feat(graph): introduce id-keyed layout requests` |
| M03 scene controller plus legacy delegation | **accepted** | M02 accepted | two focused commits in plan order |
| M04 rendering, ordering, focus, gesture snapshots | **accepted** | M03 accepted | focused renderer migration commits |
| M05 Tentura graph layouts/adapters | **accepted** | M04 accepted | one focused commit per algorithm/mode |
| M06 Constellation migration and handoff | pending | M05 accepted | three focused commits in plan order |
| M07 remove legacy architecture | **accepted** | M06 and R8 pre-removal gate accepted | `refactor(graph): remove object-keyed layout compatibility` |
| M08 architecture enforcement/documentation | **accepted** | M07 accepted | `docs(graph): record stable scene architecture` |

## Required gates

- Run verification serially. Do not run Flutter, browser, analyzer, PostgreSQL, or integration tests in parallel.
- Package-focused: exact owned Flutter tests; package-root `dart analyze --format machine` recorded separately from test results.
- Client-focused: exact M00 paths; client custom lints and terminology check when relevant.
- Final: graph package and client suites; relevant custom lint/terminology checks; required browser and multi-client proof from the parent plan. Hardware-only touch may be BLOCKED only where the parent plan permits it.
- No generated file edits, no secrets, no pushes, deploys, resets, stashes, or rewrites.

---

## M00 — Baseline and behavior inventory (worker: Composer 2.5, 2026-09-12)

### Public API (`packages/force_directed_graphview/lib/force_directed_graphview.dart`)

| Export area | Primary types / entry points |
| --- | --- |
| Widget | `GraphView`, `ChildBuilder` |
| Controller | `GraphController`, `GraphMutator` (via `graph_view.dart` part) |
| Configuration | `GraphConfiguration`, drag/focus typedefs, `nodePaintOrder` |
| Layout | `GraphLayout`, `GraphLayoutBuilder`, `GraphLayoutAlgorithm`, `FruchtermanReingoldAlgorithm` |
| Model | `NodeBase`, `Node`, `EdgeBase`, `Edge`, `GraphCanvasSize`, `LazyBuilding` |
| Builders / paint | `NodeBuilder`, `DefaultNodeBuilder`, `LabelBuilder`, `BottomLabelBuilder`, `EdgePainter`, `LineEdgePainter`, `AnimatedDashEdgePainter` |

**Controller surface (production-relevant):** `mutate`, `clear({recenter})`, `useLayoutAlgorithm`, `replaceNode`, `setPinned`, `setNodePresentationPosition`, `clearPresentationPosition`, `clearAllPresentationPositions`, `getPosition` / `getPositionOrNull`, `orderedNodes`, `spawnPositionResolver`, camera ops (`jumpToNode`, `jumpToPosition`, `jumpToCenter`, `zoomBy`, `fitToNodes`, `fitToRect`), `setCameraInteractionGated`, layout transition getters, `dispose`.

**Not present today (target in plan):** stable edge/node ID types, layout tickets, terminal frame protocol, `GraphSceneController`, token-based presentation holds, ID-keyed topology application.

### Production callers (Tentura `packages/client/lib`)

| Surface | Files | Graph API usage |
| --- | --- | --- |
| **Trust / shared graph** | `features/graph/ui/bloc/graph_cubit.dart`, `graph_body.dart`, `graph_app_bar_actions.dart` | `GraphController<NodeDetails, EdgeDetails>`, `RadialHopLayoutAlgorithm`, `LayeredDagLayoutAlgorithm`, `FruchtermanReingoldAlgorithm`, `replaceNode`, `fitToNodes`, `jumpToNode`, `spawnPositionResolver`, `clear()` |
| **Forwards** | same cubit/body (mode branches) | `LayeredDagLayoutAlgorithm(rootIds: …)`, focus/jump camera paths |
| **Genealogy** | same cubit/body | layered DAG + `NodeDetails` subtypes with opaque `nodeKey` |
| **Constellation** | `constellation_cubit.dart`, `constellation_body.dart`, `constellation_anchor_controls.dart` | `GraphController`, `ConstellationLayoutAlgorithm`, `clear(recenter: false)`, `useLayoutAlgorithm`, `setNodePresentationPosition`, `clearPresentationPosition`, `nodePaintOrder` |
| **Payload types** | `node_details.dart`, `edge_details.dart` | extend `NodeBase` / `EdgeBase` |
| **Layout adapters** | `tentura_layout_algorithms.dart` | three `GraphLayoutAlgorithm` impls + `GraphLayoutBuilder` |
| **Edge rendering** | `animated_highlighted_edge_painter.dart` | `EdgePainter` API |

No other production Dart importers of `force_directed_graphview` under `packages/client/lib` (R8 grep, 2026-09-12).

Constellation **domain** has no `force_directed_graphview` import; `dart:ui` `Offset`/`Size` only in layout/density helpers (expected).

### Client test anchors (R6 — exact paths, not run in M00)

| Mode | Test paths under `packages/client/test/features/` |
| --- | --- |
| Trust | `graph/tentura_layout_algorithms_test.dart`, `graph/graph_body_select_expand_test.dart`, `graph/graph_focus_path_visibility_test.dart`, `graph/graph_profile_projection_patch_test.dart`, `graph/reciprocal_edge_painter_golden_test.dart` |
| Forwards | `graph/forward_graph_focus_rules_test.dart`, `graph/graph_body_navigation_controls_test.dart`, `graph/tentura_layout_algorithms_test.dart` |
| Genealogy | `graph/graph_cubit_genealogy_test.dart`, `graph/graph_body_genealogy_test.dart`, `graph/graph_node_widget_genealogy_test.dart` |
| Constellation | `constellation/constellation_p06_composition_layout_test.dart`, `constellation/constellation_anchor_case_test.dart`, `constellation/constellation_anchor_cubit_test.dart`, `constellation/constellation_anchor_interaction_test.dart`, `constellation/constellation_body_test.dart` |

### Package test inventory (pre-existing + M00)

| File | Role |
| --- | --- |
| `test/controller_test.dart` | mutator errors, `fitToNodes`, `jumpToNode`, `clear` + relayout |
| `test/node_drag_gesture_test.dart` | paint order, pan/zoom vs drag, camera gate, presentation cancel, overlap hit, same-frame edge geometry, relayout suppression while dragging |
| `test/layout_transition_test.dart` | 350 ms layout interpolation |
| `test/graph_layout_lerp_test.dart` | `GraphLayout.lerp` + spawn |
| `test/fruchterman_reingold_algorithm_test.dart` | FR streaming / edge snapshot |
| **`test/scene_contract_test.dart` (M00)** | identity/layout coupling, parallel edges, presentation precedence, `clear(recenter: false)` zoom preservation, stale stream generation, isolated controllers |

### Green characterization added (M00)

Committed tests document **current** behavior:

- `GraphLayout` keys by node `==` (payload-sensitive nodes lose lookup when label/display changes but logical id string matches).
- `GraphController` can hold **two** nodes whose product logical id string collides when `==` differs (`_LogicalIdNode` fixture).
- `replaceNode` copies layout position to the replacement **instance** when `_layout` exists.
- `Node<int>` rejects duplicate `data` via set equality.
- Parallel edges allowed when `Edge.data` differs; identical edge not duplicated in set.
- Presentation override wins over layout; `clearPresentationPosition` snaps back in one step (not ticket-gated).
- `clear(recenter: false)` preserves camera scale across `clear` + `mutate` rebuild.
- Superseding `mutate` drops stale frames from an earlier `_relayoutGeneration` (no cross-controller ticket API).
- Two `GraphController` instances do not share topology or presentation maps.

### Documented baselines (not in committed suite — target for M03+)

These contracts **cannot** be expressed as green tests against today's API without asserting future behavior. Record for later packets; do **not** commit failing tests.

1. **Payload refresh via `clear()` + `mutate()` (Constellation `_rebuildGraph`):** new node instances drop object-keyed layout until async relayout; camera preservation relies on `clear(recenter: false)` (see `constellation_cubit.dart` ~1522). *Future:* ID-keyed `applyTopology` without layout wipe.

2. **Atomic drag → terminal layout handoff:** library exposes separate `clearPresentationPosition` / layout stream completion; Constellation sequences holds in the cubit (~736, pin rebuild paths). No single controller notification binds terminal layout + hold release. *Future:* M03 `requestLayout(releaseOnTerminal: …)`.

3. **Layout tickets / stale owner across two controllers:** only per-controller `_relayoutGeneration`; no `GraphLayoutTicket` to reject foreign streams. *Future:* M02–M03 ticket equality includes controller owner.

4. **FR terminal frame / partial stream rejection:** FR may emit multiple non-terminal iterations without a marked terminal frame (see plan R3). *Future:* M02b native FR + adapter tests.

**Optional local repro (manual, not CI):** extend `scene_contract_test.dart` locally with a widget test that `clear()`s, `mutate()`s with a new `_LogicalIdNode(logicalId: same, display: new)` and asserts `layout.getPositionOrNull(newInstance)` is null before `pumpAndSettle` — documents rebuild flash class; omitted from git to keep suite green.

### Verification (M00)

```bash
cd packages/force_directed_graphview && flutter test test/scene_contract_test.dart
# exit 0, 12 tests passed

cd packages/force_directed_graphview && flutter test
# exit 0, 40 tests passed (full package suite)
```

Analyzer not re-run for M00 (pre-existing package diagnostics; protected `analysis_options.yaml` unchanged).

### Changed paths (M00 commit)

- `packages/force_directed_graphview/test/scene_contract_test.dart` (new)
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md` (this file)

Production code: **no changes.**

### Limitations / decisions

- Did not modify `controller_test.dart` or `node_drag_gesture_test.dart`; existing coverage retained; new contracts live in `scene_contract_test.dart` to keep M00 diff focused.
- Did not run client graph/constellation suites in M00 (plan defers broad client gates; paths recorded above for M05–M06).
- `NodeDetails.operator ==` includes render fields (`node_details_equality_test.dart` is the client-side anchor); package `_LogicalIdNode` mirrors that coupling without importing Tentura.

### Commit

- **Subject:** `test(graph): characterize scene identity and lifecycle` — locate with `git log -1 --grep 'characterize scene identity'`.

---

## Manager checkpoint — 2026-09-12

- Cursor CLI authenticated; exact non-fast `composer-2.5` is available.
- **M00 accepted** — M01 is next (`feat(graph): add stable scene identity values`).
- Existing graph package analysis produces pre-existing warnings/info. Do not alter the protected analysis-options file to affect that result.

---

## M01 — Pure scene value types (worker: Composer 2.5, 2026-09-12)

### Work

Additive pure-Dart scene layer (no Flutter imports in `lib/src/scene/`):

- **A1:** `GraphNodeId` / `GraphEdgeId` typedefs; opaque string IDs.
- **A2:** `GraphSceneNode`, `GraphSceneEdge`, `GraphTopology.fromEntries` with duplicate/empty ID and missing-endpoint validation; parallel edges and self-loops allowed.
- **A5 (values only):** `SceneLayout`, `ScenePresentation` (+ `GraphPresentationHold`), `SceneTransition`, `GraphSceneSnapshot.resolvePosition` precedence (`override → transition → layout → seed`).
- Supporting: `ScenePoint`, `SceneSize`, `GraphLayoutTicket.mint`, `GraphPresentationToken.mint`, internal `scene_collections.dart` (not exported).
- Public exports added in `force_directed_graphview.dart`; legacy controller/widget APIs unchanged.

### Decisions

- `GraphLayoutTicket` / `GraphPresentationToken` minted via in-package `mintGraphLayoutTicket` / `mintGraphPresentationToken` helpers (not exported from the public barrel); see M01 remediation below.
- `SceneTransition` included in M01 so snapshot precedence is testable without a controller.
- Validation helpers use `void` return type (not `Never`) so success paths compile cleanly.

### Verification

```bash
cd packages/force_directed_graphview && flutter test test/scene_values_test.dart
# exit 0, 18 tests passed

cd packages/force_directed_graphview && flutter test
# exit 0, 58 tests passed (full package suite)

cd packages/force_directed_graphview && dart analyze --format machine
# exit 0; pre-existing warnings unchanged (controller.dart, tests, etc.)
# new scene files: INFO-only (PUBLIC_MEMBER_API_DOCS, DIRECTIVES_ORDERING, …)
```

Protected `analysis_options.yaml` not staged. No production client changes.

### Changed paths (M01 commit)

- `packages/force_directed_graphview/lib/src/scene/graph_ids.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/scene_geometry.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/graph_topology.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/graph_layout_ticket.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/graph_presentation_token.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/scene_collections.dart` (new, package-private)
- `packages/force_directed_graphview/lib/src/scene/scene_layout.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/scene_presentation.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/scene_transition.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/scene_snapshot.dart` (new)
- `packages/force_directed_graphview/lib/force_directed_graphview.dart` (exports)
- `packages/force_directed_graphview/test/scene_values_test.dart` (new)
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md` (this file)

### Commit

- **Subject:** `feat(graph): add stable scene identity values` — locate with `git log -1 --grep 'stable scene identity'`.

---

## Manager checkpoint — 2026-09-12 (post-M01)

- **M01 accepted** — M02 is next (`feat(graph): introduce id-keyed layout requests`).

---

## M01 remediation — ticket/token ownership (worker: Composer 2.5, 2026-09-12)

### Defect

Public `GraphLayoutTicket.mint` and `GraphPresentationToken.mint` factories (commit `5dd46fb81`) let any consumer of `package:force_directed_graphview/force_directed_graphview.dart` forge controller-owned identities, violating plan A4 / R1 (private constructor; controller-minted owner).

### Resolution

- Removed public `.mint` constructors from both types (private `._` constructors unchanged).
- Added `@internal` top-level `mintGraphLayoutTicket` and `mintGraphPresentationToken` in the same libraries as the types so they can call private constructors; **not** re-exported from `force_directed_graphview.dart` (`export … show GraphLayoutTicket` / `GraphPresentationToken` only).
- Future `GraphSceneController` (M03) and package tests import `package:force_directed_graphview/src/scene/graph_layout_ticket.dart` (and presentation token library) for minting. Normal app callers using only the public barrel cannot mint tickets or tokens.

Dart has no cross-library access to private constructors without same-library helpers; this is the minimal arrangement. Deep `src/` imports remain possible for determined callers; the contract enforced here is the supported public export surface.

### Verification

```bash
cd packages/force_directed_graphview && flutter test test/scene_values_test.dart test/scene_identity_ownership_test.dart
# exit 0, 20 tests passed

cd packages/force_directed_graphview && flutter test
# exit 0, 60 tests passed

cd packages/force_directed_graphview && dart analyze --format machine
# exit 0; pre-existing warnings unchanged; new scene mint docs: no new errors
```

`git diff --check`: clean (task-owned paths only).

### Changed paths (remediation commit)

- `packages/force_directed_graphview/lib/force_directed_graphview.dart`
- `packages/force_directed_graphview/lib/src/scene/graph_layout_ticket.dart`
- `packages/force_directed_graphview/lib/src/scene/graph_presentation_token.dart`
- `packages/force_directed_graphview/test/scene_values_test.dart`
- `packages/force_directed_graphview/test/scene_identity_ownership_test.dart` (new)
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md`

### Commit

- **Subject:** `fix(graph): keep scene ticket ownership opaque`

---

## M02 — ID-keyed layout port and legacy adapter (worker: Composer 2.5, 2026-09-12)

### Work

- **A3:** `GraphLayoutNode`, `GraphLayoutEdge`, `GraphLayoutRequest`, `GraphLayoutFrame`, `SceneLayoutAlgorithm` (Flutter-free except legacy adapter `dart:ui` / `NodeBase`).
- **A4 / R3:** `GraphLayoutFrameIngress` + `GraphLayoutFrameIngress.enforce` — stale ticket, partial/extra IDs, duplicate/backward sequence, post-terminal, non-finite positions; stream must end with exactly one accepted terminal frame. No controller lifecycle state (idle/running/holds) duplicated.
- **`LegacyGraphLayoutAlgorithmAdapter`:** snapshot-bound wrapper for unchanged `GraphLayoutAlgorithm`; maps legacy yields to non-terminal ID frames + one terminal on close; validates `simulationFixed` ↔ `NodeBase.pinned`; converts `SceneLayout` previous hints to `GraphLayout` for relayout.
- **`FruchtermanReingoldSceneLayoutAlgorithm`:** native scene FR with `graphNodeIdLayoutSeed` (opaque id, not payload hash); empty/zero-iteration terminal paths; self-loop attraction uses distance clamp (legacy FR attraction aligned).
- **`layout_id_seed.dart`:** package-private seed helper (not barrel-exported).
- **`GraphLayoutAlgorithm`:** signature untouched; production still uses legacy interface until M03/M05 migration.
- **No** `GraphSceneController`, client migrations, or `graph_layout.dart` API changes (adapter converts at boundary).

### Decisions

- Frame validation lives in `graph_layout_frame_protocol.dart` for M03 reuse; algorithms emit protocol-shaped streams; ingress is the subscription boundary guard.
- Native scene FR duplicates simulation math intentionally (minimal surgical diff vs extracting shared engine in M02).
- `layout_id_seed` not exported from public barrel — only scene FR uses it today.

### Verification

```bash
cd packages/force_directed_graphview && flutter test test/scene_layout_protocol_test.dart
# exit 0, 17 tests passed

cd packages/force_directed_graphview && flutter test
# exit 0, 75 tests passed

cd packages/force_directed_graphview && dart analyze --format machine
# exit 0; pre-existing WARNINGs unchanged (controller.dart, node_drag_gesture_test.dart, …)
# new layout files: INFO-only (PUBLIC_MEMBER_API_DOCS, DIRECTIVES_ORDERING, …)
# one new WARNING fixed before commit: unused import in graph_layout_request.dart
```

Protected `analysis_options.yaml` not staged.

### Changed paths (M02 commit)

- `packages/force_directed_graphview/lib/force_directed_graphview.dart`
- `packages/force_directed_graphview/lib/src/layout_algorithm/graph_layout_request.dart` (new)
- `packages/force_directed_graphview/lib/src/layout_algorithm/scene_layout_algorithm.dart` (new)
- `packages/force_directed_graphview/lib/src/layout_algorithm/graph_layout_frame_protocol.dart` (new)
- `packages/force_directed_graphview/lib/src/layout_algorithm/layout_id_seed.dart` (new)
- `packages/force_directed_graphview/lib/src/layout_algorithm/legacy_graph_layout_algorithm_adapter.dart` (new)
- `packages/force_directed_graphview/lib/src/layout_algorithm/fruchterman_reingold_scene_layout_algorithm.dart` (new)
- `packages/force_directed_graphview/lib/src/layout_algorithm/fruchterman_reingold_algorithm.dart` (attraction distance clamp)
- `packages/force_directed_graphview/test/scene_layout_protocol_test.dart` (new)
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md`

### Commit

- **Subject:** `feat(graph): introduce id-keyed layout requests`

---

## Manager checkpoint — 2026-09-12 (post-M02)

- **M02 accepted** — M03 is next (`feat(graph): add id-keyed scene controller`).

---

## M03a — ID-keyed scene controller (worker: Composer 2.5, 2026-09-12)

### Work

- **`GraphSceneController<N,E>`:** R2 frozen API (`applyTopology`, token presentation, `requestLayout` / `cancelLayout`, `resolvePosition`, `snapshot`, `layoutOutcome`); controller-local ticket/token minting; holds registered before stream subscription; ingress via `GraphLayoutFrameIngress.enforce`; terminal acceptance clears matching `releaseOnTerminal` overrides in one notification; failure/supersession preserves overrides; payload-only topology updates skip layout revision; layout-affecting topology filters prior layout and bumps revision; empty topology; disposal/cancellation guards; `clearPresentationForNode` for legacy bridge.
- **`GraphLayoutOutcome`:** idle / running / succeeded / failed / cancelled sealed hierarchy.
- **Tests:** `test/scene_controller_test.dart` — sync/async streams, hold handoff, stale foreign tickets, isolated controllers, malformed frames, token staleness.

### Verification

```bash
cd packages/force_directed_graphview && flutter test test/scene_controller_test.dart
# exit 0, 12 passed

cd packages/force_directed_graphview && flutter test
# exit 0, 87 passed
```

### Changed paths (M03a commit)

- `packages/force_directed_graphview/lib/src/scene_controller.dart` (new)
- `packages/force_directed_graphview/lib/src/scene/graph_layout_outcome.dart` (new)
- `packages/force_directed_graphview/lib/force_directed_graphview.dart`
- `packages/force_directed_graphview/test/scene_controller_test.dart` (new)
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md`

### Commit

- **Subject:** `feat(graph): add id-keyed scene controller`

---

## M03b — Legacy controller delegation (worker: Composer 2.5, 2026-09-12)

### Work

- **`GraphController`:** required `nodeIdOf` / `edgeIdOf` resolvers (`GraphNodeIdResolver` / `GraphEdgeIdResolver` in `configuration.dart`); owns single `GraphSceneController`; topology sync via `applyTopology` (no hidden relayout); layout only through `LegacyGraphLayoutAlgorithmAdapter` + `requestLayout`; legacy `GraphLayout` mirror excludes presentation overrides; canvas-center seeds for newly added nodes; `replaceNode` retains position via `initialPositions`; camera centering still explicit on first succeeded layout; removed parallel `_relayout` stream/`_relayoutGeneration`.
- **Scene controller fix:** drop in-flight partial layout when superseding a running ticket (stale-stream contract).
- **Tests:** `test/support/int_graph_controller.dart`; package tests updated for resolvers.

### Verification

```bash
cd packages/force_directed_graphview && flutter test
# exit 0, 87 passed

cd packages/force_directed_graphview && dart analyze --format machine
# exit 0; pre-existing WARNINGs unchanged
```

### Changed paths (M03b commit)

- `packages/force_directed_graphview/lib/src/controller.dart`
- `packages/force_directed_graphview/lib/src/graph_view.dart`
- `packages/force_directed_graphview/lib/src/configuration.dart`
- `packages/force_directed_graphview/lib/src/scene_controller.dart` (supersession partial-layout clear)
- `packages/force_directed_graphview/test/support/int_graph_controller.dart` (new)
- `packages/force_directed_graphview/test/controller_test.dart`
- `packages/force_directed_graphview/test/layout_transition_test.dart`
- `packages/force_directed_graphview/test/node_drag_gesture_test.dart`
- `packages/force_directed_graphview/test/scene_contract_test.dart`
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md`

### Commit

- **Subject:** `refactor(graph): adapt legacy controller to scene state`

---

## Manager checkpoint — 2026-09-12 (post-M03)

- **M03 accepted** — M04 is next (`refactor(graph): render and drag from stable scene snapshots`).

---

## M04 — Renderer snapshot pass (worker: Composer 2.5, 2026-09-12)

### Work

- **`GraphSceneRenderScope`:** one `GraphSceneSnapshot` + ordered node ids per `AnimatedBuilder` frame in `GraphLayoutView`.
- **Nodes / labels / edges:** `LayoutId` uses `GraphNodeId`; layout and paint read `snapshot.resolvePosition`; payloads rebuilt from topology; edges resolve both endpoints from the same snapshot in one `CustomPainter.paint`.
- **`GraphController`:** `renderSnapshot`, `visibleNodeIds`, `orderedRenderNodeIds`, token drag helpers, `nodePayloadForId`; lazy visibility recomputed from scene geometry (pre-viewport fallback for positioned nodes).
- **`NodeDragGesture`:** captures id + presentation token; hit test uses the same snapshot order as paint; legacy callbacks resolve current payload by id; cancel/dispose use `clearPresentationPosition` + `try/finally` gate cleanup.

### Verification

```bash
cd packages/force_directed_graphview && flutter test
# exit 0, 91 passed

cd packages/force_directed_graphview && dart analyze --format machine
# exit 0; pre-existing WARNINGs unchanged
```

### Changed paths

- `packages/force_directed_graphview/lib/src/graph_view.dart`
- `packages/force_directed_graphview/lib/src/controller.dart` (part)
- `packages/force_directed_graphview/lib/src/widget/graph_layout_view.dart`
- `packages/force_directed_graphview/lib/src/widget/nodes_view.dart`
- `packages/force_directed_graphview/lib/src/widget/labels_view.dart`
- `packages/force_directed_graphview/lib/src/widget/edges_view.dart`
- `packages/force_directed_graphview/lib/src/widget/node_drag_gesture.dart`
- `packages/force_directed_graphview/test/scene_rendering_test.dart` (new)
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md`

### Commit

- **Subject:** `refactor(graph): render and drag from stable scene snapshots`

---

## Manager checkpoint — 2026-09-13 (post-M04)

- **M04 accepted** at `649e04978` — M05 is next (Tentura layout algorithms and graph adapters).

---

## M05 — Tentura graph layouts/adapters (worker: Composer 2.5, 2026-09-13)

### Work

- **`BoundSceneLayoutAlgorithm`:** legacy [GraphLayoutAlgorithm] handle wrapping native [SceneLayoutAlgorithm] delegates; controller unwraps before [requestLayout] (no dual `layout` signature clash on Tentura algorithms).
- **`graph_scene_ids.dart`:** kind-prefixed injective [GraphNodeId] / [GraphEdgeId] at the UI boundary; domain id decode for radial/DAG pure helpers.
- **`RadialHopLayoutAlgorithm` / `LayeredDagLayoutAlgorithm`:** [SceneLayoutAlgorithm] only — ID-keyed [GraphLayoutRequest] frames, prior [SceneLayout] relayout for radial expand fans; no [NodeDetails] `==` / `hashCode` / presentation identity in layout.
- **`GraphCubit` / `GraphBody`:** [tenturaGraphNodeId] / [tenturaGraphEdgeId] on [GraphController]; [_jumpToNodeByStableId], [renderSnapshot] spawn resolver, help-offerer [replaceNode] by id; [BoundSceneLayoutAlgorithm] for trust/forwards/genealogy widget algorithms.
- **Constellation (adapter-only):** required id resolvers on [GraphController] for shared package API; no topology/handoff migration (M06).
- **Tests:** [graph_scene_ids_test.dart], scene layout test support, migrated [tentura_layout_algorithms_test.dart] (payload replacement + layout modes), stub [testGraphController] across graph widget tests.

### Decisions

- Layered DAG and radial hop share one [tentura_layout_algorithms.dart] commit because both live in the same file; cubit/body wiring is a separate commit.
- [ConstellationLayoutAlgorithm] remains legacy [GraphLayoutAlgorithm] until M06a.

### Verification

```bash
cd packages/force_directed_graphview && flutter test
# exit 0, 91 passed

cd packages/force_directed_graphview && dart analyze --format machine
# exit 0; pre-existing WARNINGs unchanged

cd packages/client && flutter test test/features/graph/graph_scene_ids_test.dart \
  test/features/graph/tentura_layout_algorithms_test.dart \
  test/graph_controller_test.dart \
  test/features/graph/graph_body_select_expand_test.dart \
  test/features/graph/forward_graph_focus_rules_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_cubit_genealogy_test.dart \
  test/features/graph/graph_body_genealogy_test.dart
# exit 0, 70 passed

./scripts/check-custom-lints.sh packages/client
# exit 0 (baseline ratchet; no new errors in owned paths)
```

Protected `packages/force_directed_graphview/analysis_options.yaml` not staged.

### Commits

1. `feat(graph): add bound scene layout algorithm handle` — `a915ccc1c`
2. `refactor(client): define stable graph scene ids at ui boundary` — `83220c079`
3. `refactor(client): migrate radial-hop layout to id-keyed scene port` — `2e3f2d4c6` (includes layered DAG in same file)
4. `refactor(client): wire graph modes to stable scene ids` — `2be9bae3a`

### Changed paths (M05)

- `packages/force_directed_graphview/lib/src/layout_algorithm/bound_scene_layout_algorithm.dart` (new)
- `packages/force_directed_graphview/lib/force_directed_graphview.dart`
- `packages/force_directed_graphview/lib/src/controller.dart`
- `packages/client/lib/features/graph/ui/utils/graph_scene_ids.dart` (new)
- `packages/client/lib/features/graph/ui/utils/tentura_layout_algorithms.dart`
- `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`
- `packages/client/lib/features/graph/ui/widget/graph_body.dart`
- `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart` (resolvers only)
- `packages/client/test/features/graph/graph_scene_ids_test.dart` (new)
- `packages/client/test/features/graph/scene_layout_test_support.dart` (new)
- `packages/client/test/features/graph/tentura_layout_algorithms_test.dart`
- `packages/client/test/graph_controller_test.dart`
- graph widget stub tests listed in commit 4

---

## Manager checkpoint — 2026-09-13 (post-M05)

- **M05 accepted** — M06 is next (Constellation topology and placement handoff).

---

## M06 — Constellation topology and placement handoff (worker: Composer 2.5, 2026-09-13)

### Work

- **`ConstellationSceneLayoutAlgorithm`:** native [SceneLayoutAlgorithm] over `computeConstellationPlacedLayout`; terminal [GraphLayoutFrame] only; prior hints from [GraphLayoutRequest.previous]; no normalized coordinates in scene.
- **`constellation_graph_scene.dart`:** stable [GraphNodeId]/[GraphEdgeId] helpers (`c:<kind>:…` semantic edge ids).
- **`GraphController`:** `reconcileTopology`, `requestSceneLayout(releaseOnTerminal:)`, `activePresentationTokenForNode`; `mutate` skips relayout on payload-only topology; constellation uses `layoutOnTopologyChange: false` + explicit layout request.
- **`ConstellationCubit`:** `reconcileTopology` instead of `clear`+`mutate`; [tenturaGraphNodeId] resolvers; placement handoff via `_placementHandoffGraphId` + `releaseOnTerminal`; drag presentation via scene tokens (gesture + programmatic test path).
- **Tests:** `constellation_scene_layout_test.dart`; body tests updated for semantic edge-id keys; `constellation_scene_handoff_test.dart` (terminal handoff release, failure/supersession hold, reconcileTopology while dragging).

### M06 handoff test recovery (worker: Composer 2.5, 2026-09-13)

- **Symptom:** `constellation_scene_handoff_test.dart` hung until default widget-test timeout (~30s+) on layout-failure and supersession cases.
- **Cause:** `_settleLayout` used `Future.delayed` without advancing `WidgetTester` fake async; layout stream completion never observed under `testWidgets`.
- **Fix (test-only):** pass `WidgetTester` into `_settleLayout` and `await tester.pump(...)`; supersession mid-flight wait uses `tester.pump` instead of bare `Future.delayed`.
- **Not a production lifecycle bug:** package `scene_controller_test.dart` already settles with real async; constellation proof unchanged (matching-ticket terminal releases override atomically; malformed/superseded layouts retain presentation).

```bash
cd packages/client && flutter test test/features/constellation/constellation_scene_handoff_test.dart
# exit 0, 4 passed (~4s)
```

### Verification

```bash
cd packages/force_directed_graphview && flutter test
# exit 0, 91 passed

cd packages/client && flutter test test/features/constellation/
# exit 0, 238 passed

./scripts/check-custom-lints.sh packages/client
# exit 0 (baseline 32; no new custom-rule growth)
```

Protected `packages/force_directed_graphview/analysis_options.yaml` not staged.

### Commits

1. `refactor(client): adapt constellation layout to graph scene`
2. `refactor(client): reconcile constellation topology by stable id`
3. `refactor(client): hand off drag presentation by layout ticket`

### Changed paths (M06)

- `packages/client/lib/features/graph/ui/utils/tentura_layout_algorithms.dart`
- `packages/client/lib/features/constellation/ui/utils/constellation_graph_scene.dart` (new)
- `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart`
- `packages/client/lib/features/constellation/ui/widget/constellation_body.dart`
- `packages/client/test/features/constellation/constellation_scene_layout_test.dart` (new)
- `packages/client/test/features/constellation/constellation_scene_handoff_test.dart` (new)
- `packages/client/test/features/constellation/constellation_body_test.dart`
- `packages/force_directed_graphview/lib/src/controller.dart`
- `packages/force_directed_graphview/lib/src/scene_controller.dart`
- `packages/force_directed_graphview/lib/src/graph_view.dart`
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md`

---

## M07 — Widget lifecycle remediation (worker: Composer 2.5, 2026-09-13)

### Diagnosis

- **Symptom:** `controller_test.dart` `--plain-name 'fitToNodes on a laid-out'` and `scene_contract_test.dart` hung; `flutter_tester` RSS climbed toward 10–15 GiB in ~30–45 s. `scene_values_test` / pure scene tests stayed fast.
- **Root cause (production):** M07 `GraphController._onSceneStateChanged` schedules a microtask that, while `GraphLayoutOutcomeSucceeded` remains active, calls `_handleAcceptedLayout` on **every** scene notification. With `layoutTransitionDuration == Duration.zero`, that always calls `GraphSceneController.setLayoutTransition(null)`, which always `_commit()`s even when `_transition` was already null → listener re-enters → unbounded microtask/rebuild loop (not a test pump workaround issue).
- **Secondary:** `GraphView.dispose` → `_detachTicker` touched a scene already disposed when tests dispose `GraphController` before widget teardown; late microtasks also called `notifyListeners` after dispose.

### Repair

- Gate `_handleAcceptedLayout` on **new** success tickets (`_lastHandledLayoutSuccessTicket`).
- `setLayoutTransition(null)` no-ops when transition already clear (no `_commit`).
- `_disposed` guards on microtask `apply` and `_detachTicker` scene mutation.

### Verification (serial, `--concurrency=1`, pipefail, RSS sampled ~3 s)

```bash
# BEFORE: Mem 61Gi total / ~41Gi avail; Swap 15Gi / ~5.1Gi free
cd packages/force_directed_graphview && flutter test test/controller_test.dart \
  --concurrency=1 --plain-name 'fitToNodes on a laid-out'
# exit 0 ~3.2s; peak flutter_tester RSS ~3 MiB (loader) — no growth
# AFTER: Mem avail unchanged

cd packages/force_directed_graphview && flutter test test/scene_contract_test.dart --concurrency=1
# exit 1 ~2.1s; 11 passed, 1 failed (pre-existing M07 expectation: getPosition on foreign
#   controller throws ArgumentError vs current StateError) — no hang, no RSS runaway

flutter test test/scene_controller_test.dart --concurrency=1 \
  --plain-name 'clearing layout transition'
# exit 0
```

Protected `packages/force_directed_graphview/analysis_options.yaml` not staged.

### Commit

- `e0f51f48d` — `fix(graph): stop scene layout success feedback loop`
  - `packages/force_directed_graphview/lib/src/controller.dart`
  - `packages/force_directed_graphview/lib/src/scene_controller.dart`
  - `packages/force_directed_graphview/test/scene_controller_test.dart`

### Remaining M07 (completed in follow-up packet)

See **M07 final — legacy removal** below.

---

## M07 final — legacy removal (worker: Composer 2.5, 2026-09-13)

### Work

- Removed production legacy layout stack: `GraphLayout`, `GraphLayoutBuilder`, `GraphLayoutAlgorithm`, `LegacyGraphLayoutAlgorithmAdapter`, `BoundSceneLayoutAlgorithm`, legacy `FruchtermanReingoldAlgorithm`, `useLayoutAlgorithm`, `clear(recenter:)`, `setNodePresentationPosition` / `clearPresentationPosition`, node-valued paint order.
- Public barrel exports scene-native types only (`SceneLayoutAlgorithm`, `GraphLayoutRequest`/`GraphLayoutFrame`, `FruchtermanReingoldSceneLayoutAlgorithm`, `GraphSceneSnapshot`, id typedefs).
- Client graph + constellation call sites use `SceneLayoutAlgorithm`, `requestSceneLayout` / `reconcileTopology`, `beginNodePresentationDrag`, `clearPresentationForNodeId`, `GraphNodeId` paint order.
- Tests: migrated `scene_contract_test` (foreign controller → `StateError`); `node_drag_gesture_test` enables drag hooks where required; `graph_layout_lerp_test` removed; FR tests target `FruchtermanReingoldSceneLayoutAlgorithm`; added `test/support/fixed_scene_layout.dart`, `settle_graph_layout.dart`.

### Decisions

- **Foreign controller `getPosition`:** unknown / not-yet-laid-out node throws `StateError` (not `ArgumentError`); contract test updated to match scene `resolvePosition` null path.
- **Node drag layer:** `GraphViewConfiguration.nodeDragEnabled` requires at least one drag callback; gesture tests pass no-op `onNodeDragStart` when exercising multi-pointer gating without product hooks.
- **Lifecycle repair** from `e0f51f48d` preserved (layout success ticket gate, transition null no-op, dispose guards).

### Pre-removal gate SHA

- `e0f51f48d` — `fix(graph): stop scene layout success feedback loop` (last commit before legacy deletion land).

### Verification (serial, `--concurrency=1`)

Memory before/after each command: MemAvailable ~47.6 GiB → ~46.6 GiB; SwapFree ~5.1 GiB stable. No `flutter_tester` RSS runaway (peak loader-scale during ~6.4 s package suite).

```bash
cd packages/force_directed_graphview && flutter test --concurrency=1
# exit 0, 88 passed (~6.4s)

cd packages/client && flutter test \
  test/features/constellation/constellation_scene_handoff_test.dart \
  test/features/constellation/constellation_scene_layout_test.dart \
  --concurrency=1
# exit 0, 7 passed (~7s)

rg -n "GraphLayoutAlgorithm|LegacyGraphLayoutAlgorithmAdapter|BoundSceneLayoutAlgorithm|GraphLayoutBuilder|GraphLayout\\b|clear\\(recenter|setNodePresentationPosition|clearPresentationPosition|useLayoutAlgorithm" \
  packages/force_directed_graphview/lib packages/client/lib
# exit 1, no matches (census clean)

cd packages/force_directed_graphview && dart analyze --format machine
# exit 0; pre-existing INFO/WARNING unchanged

git diff --check
# exit 0
```

Protected `packages/force_directed_graphview/analysis_options.yaml` not staged.

### Commits

1. `efa076d7e` — `refactor(client): migrate graph views to scene-native layout APIs`
2. `f7dce7afd` — `refactor(graph): remove object-keyed layout compatibility`

### Rollback (dependency-aware)

- Revert commit (2) first, then (1), to restore legacy package exports and client adapters together.
- Lifecycle fix `e0f51f48d` is independent; keep it when reverting only legacy removal.
- M08 enforcement/documentation still pending.

---

## M08 — Architecture enforcement and documentation (worker: Composer 2.5, 2026-09-13)

### Work

- **`packages/force_directed_graphview/README.md`:** final scene API — layers, ticket/frame lifecycle, resolved-position precedence, explicit camera, M07 compatibility removal list (no legacy `GraphLayout` examples).
- **`packages/force_directed_graphview/CHANGELOG.md`:** `0.6.2+tentura.3` entry for scene-native surface and removal notes.
- **`packages/client/test/architecture/constellation_domain_graph_boundary_test.dart`:** static import guard for `lib/features/constellation/domain` — forbids `package:flutter/` and `package:force_directed_graphview` (allows existing `dart:ui` geometry per C6).
- **`docs/plans/constellation-pinning-plan.md`:** C6 cross-reference to scene decoupling plan + package README (post-migration pointer only).
- **M07 review defect:** removed trailing blank line at EOF on this journal and `tentura_layout_algorithms.dart` so `git diff --check d84acc940..HEAD` is clean.

### Boundary violation proof (architecture test)

Deliberate violation (not committed):

```bash
# prepend to lib/features/constellation/domain/constellation_density.dart:
# import 'package:force_directed_graphview/force_directed_graphview.dart';
cd packages/client && flutter test test/architecture/constellation_domain_graph_boundary_test.dart --concurrency=1
# → failed: must not import force_directed_graphview

# remove the line → same command → passed
```

### Verification (serial, `--concurrency=1`, memory recorded per command)

MemAvailable ~46.9–47.4 GiB; SwapFree ~5.50 GiB stable (above 35 GiB gate).

```bash
# deliberate violation (prepend force_directed_graphview import to constellation_density.dart)
cd packages/client && flutter test test/architecture/constellation_domain_graph_boundary_test.dart --concurrency=1
# exit 1 — failed: must not import force_directed_graphview

cd packages/client && flutter test test/architecture/constellation_domain_graph_boundary_test.dart --concurrency=1
# exit 0, 1 passed (~2.3s)

git diff --check d84acc940..HEAD
# exit 0 (after EOF fix in this commit)
```

Protected `packages/force_directed_graphview/analysis_options.yaml` not staged.

### Changed paths (M08 commit)

- `packages/force_directed_graphview/README.md`
- `packages/force_directed_graphview/CHANGELOG.md`
- `packages/client/test/architecture/constellation_domain_graph_boundary_test.dart` (new)
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md`
- `docs/plans/constellation-pinning-plan.md` (C6 cross-reference)
- `docs/plans/constellation-pinning-implementation-journal.md` (M08 evidence)
- `packages/client/lib/features/graph/ui/utils/tentura_layout_algorithms.dart` (EOF whitespace only)

### Commit

- **Subject:** `docs(graph): record stable scene architecture` — locate with `git log -1 --grep 'record stable scene architecture'`.

### Rollback

- Revert the M08 commit only; M07 scene-native code and client adapters remain. Re-run `constellation_domain_graph_boundary_test.dart` after revert to confirm the check is removed.

---

## Manager checkpoint — 2026-09-13 (post-M08)

- **M08 accepted** — scene decoupling plan complete per completion criteria (documentation + boundary check; broad browser/PG gates deferred to parent Constellation plan where already accepted).

## STATUS

- **complete** — M00–M08 accepted on `feature/pin_constellation`.

## COMMITS

- `e0f51f48d` — lifecycle feedback-loop repair (prerequisite)
- `efa076d7e` — `refactor(client): migrate graph views to scene-native layout APIs`
- `f7dce7afd` — `refactor(graph): remove object-keyed layout compatibility`
- M08 — `docs(graph): record stable scene architecture` (`git log -1 --grep 'record stable scene architecture'`)

## TESTS

- Package: 88 passed serial (`flutter test --concurrency=1`) — M07 evidence
- Client constellation scene: 7 passed serial (handoff + layout paths) — M07 evidence
- M08: `git diff --check d84acc940..HEAD`; architecture boundary test; deliberate violation probe (journal)

## FILES

- `packages/force_directed_graphview/lib/**` (legacy layout removed; scene-native public API)
- `packages/force_directed_graphview/README.md`, `CHANGELOG.md`
- `packages/force_directed_graphview/test/**` (contract, drag, FR, support helpers)
- `packages/client/lib/features/graph/**`, `packages/client/lib/features/constellation/**`
- `packages/client/test/architecture/constellation_domain_graph_boundary_test.dart`
- `packages/client/test/features/constellation/constellation_scene_*_test.dart`
- `docs/plans/force-directed-graphview-scene-decoupling-implementation-journal.md`
- `docs/plans/constellation-pinning-plan.md` (C6 xref)
- `docs/plans/constellation-pinning-implementation-journal.md`

## FINDINGS

- Production census on `lib/` paths has zero legacy symbol hits post-removal.
- `nodeDragEnabled` is callback-gated; tests must register a no-op hook to exercise gesture/camera gating without constellation product wiring.
- Constellation domain still uses `dart:ui` `Offset`/`Size` for pure layout geometry; M08 check targets Flutter widgets and `force_directed_graphview` only.

## REMAINING

- Parent Constellation plan browser/multi-client gates remain as previously recorded (P10/P11); not re-run in M08 unless client contracts change.

## P1 — Astra quality review remediation (R4/R5) — 2026-09-13

### Work

- **R4:** `_freezeLayoutTransitionAtDisplay` stops layout tweens at the displayed snapshot (no target snap) for drag capture and `beginNodePresentationDrag`. Layout-success handling stops the ticker before stale `_onTransitionTick` frames can reapply an old transition map after terminal `releaseOnTerminal`.
- **R5:** `GraphView` view binding — one live `GraphController` per mounted view (second attach throws `StateError`). Controller swap/unmount detaches ticker/transformation, aborts gestures, and clears gated presentation. `LayoutBuilder` + viewport size changes abort active capture. `NodeDragGesture` registers lifecycle abort; drag start/update hooks use try/catch with gate cleanup; programmatic camera moves cancel gated capture.

### Verification (serial `--concurrency=1`, MemAvailable/SwapFree logged per test in `graph_view_p1_remediation_test.dart`)

```bash
cd packages/force_directed_graphview && flutter test test/graph_view_p1_remediation_test.dart --concurrency=1
cd packages/force_directed_graphview && flutter test --concurrency=1
# 98 passed (~7s)
```

Protected `packages/force_directed_graphview/analysis_options.yaml` not staged.

### Final acceptance after overlap-selection remediation (2026-09-13)

- `8c2c3b0e4` repaired the final scene-ID migration regression: Constellation paint order uses the actual graph node IDs, overlay Requests resolve for selection, and `GraphView` dispatches an ID-based scene hit-test tap.
- The single-client browser journey passed serially: `./scripts/run_client_integration_web_local.sh integration_test/constellation_pinning_test.dart`.
- The actor-echo-disabled multiclient gate passed five serial runs: `REALTIME_MULTICLIENT_DRIVER=constellation_pinning_multiclient_web_test.dart REALTIME_MULTICLIENT_ACTOR_ECHO_ENABLED=false ./scripts/run_realtime_multiclient_web_local.sh`. Required live convergence, reconnect, stale-delete, and authorization-loss journeys passed. Hardware-only journeys remain explicitly blocked.
- Final serial verification passed: graph package suite; client suite (`3124 passed, 29 skipped`); client and server custom lint gates; `packages/tentura_lints` tests; terminology check; and `git diff --check d84acc940..HEAD`.
- Rollback: revert `8c2c3b0e4` first, then M08 (`a5aaa2d14`), M07 deletion (`f7dce7afd`), and its client migration (`efa076d7e`) only as a dependency-aware sequence. Keep the independent lifecycle repair `e0f51f48d` unless that behavior itself must be reverted.

## P2 — Astra layout lifecycle remediation (R3/R4) — 2026-09-13

### Work

- **R3 (`scene_controller.dart`):** synchronous `algorithm.layout` throws and synchronous `listen` failures route through `_failLayout` → `GraphLayoutOutcomeFailed`, active ticket cleared, listeners notified; presentation overrides/holds untouched.
- **R4 (Constellation):** cubit observes owned `requestSceneLayout` outcomes only (`_awaitingConstellationLayoutOutcome`); one recovery rebuild from `confirmedProjection` with presentation tokens on the recovery ticket; second failure sets `graphLayoutFailureMessage` with `retryGraphLayoutAfterFailure` / `cancelGraphLayoutFailure` (no auto loop). Direct controller handoff tests (non-owned requests) unchanged.

### Verification (serial `--concurrency=1`, MemAvailable/SwapFree logged in test files)

```bash
grep -E 'MemAvailable|SwapFree' /proc/meminfo | head -2
cd packages/force_directed_graphview && flutter test test/scene_controller_layout_lifecycle_test.dart --concurrency=1
cd packages/client && flutter test test/features/constellation/constellation_layout_failure_recovery_test.dart test/features/constellation/constellation_scene_handoff_test.dart --concurrency=1
grep -E 'MemAvailable|SwapFree' /proc/meminfo | head -2
# graph 3 passed; client 8 passed (3 recovery + 5 handoff regression)
```

Protected `packages/force_directed_graphview/analysis_options.yaml` not staged.

### P2 verification remediation (2026-09-13)

- **Hang root cause (recovery widget test):** `ConstellationCubit` default `loadOnCreate: true` raced with explicit `await cubit.load()`, doubling layout/reconcile work and risking stuck `flutter_tester` under serial load. Harness now passes `loadOnCreate: false` (matches `constellation_scene_handoff_test.dart`).
- **Test harness:** dropped fixed 400 ms pump; layout progress uses bounded `tester.pump(16 ms)` frames only. Second-failure case pumps 24 frames with stable `relayoutInvocationCount` after the failure message is surfaced.
- **Scene lifecycle test:** malformed-stream case waits via `Future.microtask` spin (no `Future.delayed`).

```bash
grep -E 'MemAvailable|SwapFree' /proc/meminfo | head -2
cd packages/force_directed_graphview && flutter test test/scene_controller_layout_lifecycle_test.dart --concurrency=1
pgrep -a flutter_tester || true
grep -E 'MemAvailable|SwapFree' /proc/meminfo | head -2
cd packages/client && flutter test test/features/constellation/constellation_layout_failure_recovery_test.dart --concurrency=1
pgrep -a flutter_tester || true
grep -E 'MemAvailable|SwapFree' /proc/meminfo | head -2
cd packages/client && flutter test test/features/constellation/constellation_scene_handoff_test.dart --concurrency=1
pgrep -a flutter_tester || true
grep -E 'MemAvailable|SwapFree' /proc/meminfo | head -2
# graph 3 passed; client recovery 3 passed; client handoff 5 passed; no flutter_tester after each command
```
