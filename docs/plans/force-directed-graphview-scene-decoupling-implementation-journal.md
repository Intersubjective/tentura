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
| M01 pure scene value types | pending | M00 accepted | `feat(graph): add stable scene identity values` |
| M02 ID-keyed layout port and legacy adapter | pending | M01 accepted | `feat(graph): introduce id-keyed layout requests` |
| M03 scene controller plus legacy delegation | pending | M02 accepted | two focused commits in plan order |
| M04 rendering, ordering, focus, gesture snapshots | pending | M03 accepted | focused renderer migration commits |
| M05 Tentura graph layouts/adapters | pending | M04 accepted | one focused commit per algorithm/mode |
| M06 Constellation migration and handoff | pending | M05 accepted | three focused commits in plan order |
| M07 remove legacy architecture | pending | M06 and R8 pre-removal gate accepted | `refactor(graph): remove object-keyed layout compatibility` |
| M08 architecture enforcement/documentation | pending | M07 accepted | focused documentation/enforcement commit if needed |

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
