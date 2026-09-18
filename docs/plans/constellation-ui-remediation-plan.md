# Constellation UI remediation plan

Date: 2026-09-14

Status: proposed, **revision 2** (reviewed against source the same day). Implementation has not started.

Baseline inspected: `a77deba06`; source re-checked at `3f205d144` (only `constellation_screen.dart` changed in between: the Field tab now reloads when reselected).

Scope: remediate the findings from the screenshot review, plus the defects found in the source (UI-09 to UI-13) and the marker placement defect raised in review (UI-14).

Audience: an implementing agent that follows the steps literally. Every unit lists the files, the code changes, the tests with concrete assertions, and a "done when" check. When a step says **do not**, it protects a product contract; do not trade it away to make a test pass.

---

## 0. Revision 2 review summary

### 0.1 Corrections to revision 1

| Rev 1 said | Actually true (source-checked) | Effect on the plan |
|---|---|---|
| UI-09 source is `_scheduleLabelBudgetUpdate` (~69) | The method is `_ConstellationBodyState._syncLabelBudget` (`constellation_body.dart:64-80`). It is called **inside `LayoutBuilder.builder`**, which is during build. | R01 names the right method and moves the call to a post-frame callback |
| The budget bug makes the field too sparse, so fixing it "suddenly displays more Requests" and must not ship alone | `updateLabelBudgetContext` only relayouts (`_reconcileLayout`) and **never recomposes**. The first composition therefore always uses the default budget `1200×900 @ 1.0` (3 per author, 150 total). Later recomposes (filter change, expand/collapse, anchor refresh, and since `3f205d144` **tab reselect**) use `scale 14`. At 375×547 that gives **1 per author and 2 in total**. The screenshot's "ещё 3" under Vadim (3 shown + 3 hidden) is the first-load default-budget state. | The corrected budget (1 per author, 28 total at 375×547) is **never denser** than today's first load. R01 is a standalone bug fix and ships first. |
| `ConstellationLayoutAlgorithm._computePositions` | The class is `ConstellationSceneLayoutAlgorithm` (`tentura_layout_algorithms.dart:269`). The cubit never passes `nodeSizes`, so the constructor's `nodeSizes` only ever supplied sizes for **non-scene** ids. | R04 keeps body sizes and footprints as separate inputs instead of "fixing merge precedence" |
| Pale edges: "numeric contrast has not been measured" | Tier-1 paths use `colorScheme.outline` = `TenturaPalette.border` `#E2E8F0` on `bg` `#F8FAFC`. That is **1.18:1** (light) and **1.73:1** (dark, `#334155` on `#0A1826`). Tier-2 and stub edges use the seed-derived `outlineVariant`. Attachments use the darker `secondary`. | R05 has concrete tokens with computed contrast |
| `constellationNavLabel` is "Поле" | `constellationTitle` = "Поле"/"Field". `constellationNavLabel` = "Моё поле"/"My field". The compact Field tab was made icon-only **on purpose** on 2026-09-09 (commits `9f2bdcde6`, `35c711cfa`). | Showing that label reverses a recent explicit decision. It is now an **open decision** (§6.1). The default is no change. |
| Ego-branch crowding needs a fixture to find the cause | Source-confirmed. `_computeSemanticIdeals` fans the ego's own Requests with `branchUnitDirection(parentPos: centre)`. With no grandparent that returns `Offset(0, 1)`, which is **straight down**. The fan radius is `satelliteOffset = 56`, and the minimum chord is `2·56·sin 15° ≈ 29 px`, smaller than one 36 px Request body. | R04 gives an explicit direction and spacing algorithm |
| Label box `100×20` only causes truncation | The label box is also shorter than one line at text scale ≥1.3 (`13 × 1.35 × 1.3 = 22.8 px > 20 px`). The status/pin marker row is drawn at `bottom: -tt.iconSize` from the node, which puts it **on top of** the label text (see UI-14). | R03 step 8 splits the markers into top-corner badges |
| Baseline client version 7.6.15 | HEAD is 7.6.16. The working tree carries an uncommitted 7.6.17 bump from concurrent work. | R08 reads the version at implementation time |

### 0.2 Newly found defects (source-confirmed)

- **UI-10: the budget is applied late and inconsistently.** See the second row of §0.1. Toggling one author's "+N more" recomposes the whole field with the broken budget, so the counts of **other** authors change.
- **UI-11: hidden Requests take up layout space.** `_rebuildGraph` sets `layoutVisibleRequestsByAuthor = plan.layoutRequestsByAuthor`, which holds **all** Requests, including overflow-hidden ones. Hidden Requests are placed by `computeConstellationPlacedLayout`, and their default 64×64 boxes (not in the scene, so no real size) block visible nodes. They also take fan slots. `layoutInputFromComposition` (pin-from-text) already filters to drawn Requests, so the map and pin-from-text disagree today.
- **UI-12: overflow chips use stale positions.** `_MapOverflowOverlay` is passed as `GraphView.builder`. `GraphLayoutView` applies that builder **outside** its `AnimatedBuilder`, so the chip reads positions only when `ConstellationBody` rebuilds. It does not follow layout completion, the 350 ms transition, or drags.
- **UI-13: the collapse control disappears after expansion.** When an author is expanded, `_buildLabelDisplayPlan` computes `hidden = 0`, so the author has no entry in `overflowHiddenCountByAuthor` and the map chip is not built. The map has no way back to the collapsed state. `ConstellationOverflowGroup` already has an `expanded` icon state that can never show.
- **UI-14: pin and status markers sit under the node, on top of its label.** `_ConstellationMapNode` (`constellation_body.dart:727-750`) stacks `ConstellationRequestStatusMarker` at `Positioned(bottom: -tt.iconSize)` with `Clip.none`, centred horizontally. The marker row (19 px glyphs: status, then pin) therefore occupies roughly 3–22 px below the body, the same band where `BottomLabelBuilder` starts the label (`nodePosition + (0, nodeSize / 2)`). This affects both kinds of node: Requests show status + pin, and people show the pin alone (`showStatus: false`). In the screenshot, the pin covers the title "didjdjeh" and the status circle covers "Test Beacon" and "blabla". The pin is the main cue for the D20 "pins may overlap" contract, so it must stay visible and must never cover the name or title.
- **One tap is delivered twice (part of UI-07).** A tap on a node body fires both `GraphNodeWidget.onTap` (a `GestureDetector`) and `GraphView.onNodeTap` (the pointer-up of the `NodeDragGesture` `Listener`). Today this is harmless only because the second `emit` equals the first. `GraphPersonContextCubit.selectProfile` still runs twice. Verify this with a counting test in R06.

### 0.3 Simplifications (reversible; they reduce risk for the implementer)

1. **No edge detour routing.** Labels move to an opaque screen-space layer drawn above all edges, so edges can no longer show through label text. Automatic placement also prefers candidates whose attachment line does not cross another body. General edge rerouting is deferred and recorded as a follow-up in R08.
2. **Canonical (maximum) label footprints for placement.** Scene placement uses the maximum plate size per node kind (person: 1 line; Request: 2 lines), not per-title measurement. Title edits therefore never cause a relayout. Exact per-title measurement is used only for drawing plates in screen space.
3. **Person placement is unchanged.** Label footprints of people act as obstacles for Requests, but people keep today's placement (body-only collision). This preserves the A3 stability contract exactly. Only Request satellites move.
4. **No re-allocation loop.** If a Request cannot be placed without overlap, the existing least-overlap fallback stays, and the screen-space layer suppresses the colliding labels. The per-author list already exists as the fallback: tapping an author opens `GraphPersonContextPanel`, which lists all of their discoverable Requests. No new list UI.
5. **No callouts and no automatic fit when the Field opens.** Opening the Field keeps today's camera (`jumpToCenter` puts the ego at the canvas centre at scale 1.0). Selecting a Request opens its preview, which already shows the full title.
6. **Keyboard access to graph nodes stays in the Text view**, as the feature spec documents. Map chips and camera buttons are focusable because they are standard Material buttons. Tab traversal between graph nodes is not added.

---

## 1. Evidence and intended outcome

Reference screenshot: `/home/vader/Pictures/Screenshots/Screenshot From 2026-09-14 17-46-25.png` (375 × 667). It shows the compact Russian Field screen with Vadim at the centre. Node sizes in the image imply a camera scale of about 0.7: a 40 px avatar renders about 28 px wide.

The remediated screen must let a user identify a person or Request, follow its connection, read its title, expand and collapse an author's hidden Requests, and recover the camera, without precise tapping or illegible text. Automatic layout must avoid preventable collisions. Overlapping pins placed by the viewer remain valid (D20–D23).

### 1.1 Findings

| ID | Priority | Finding | Root cause (source) | Units |
|---|---|---|---|---|
| UI-01 | P0 | "ещё 3" overlaps the Request below Vadim; ownership is unclear | Chip placed at a fixed `x-80, y+size/2+48` (`constellation_body.dart:797-798`) with no collision check. The ego fan points straight down at radius 56, so the Request sits exactly there. | R03, R04 |
| UI-02 | P0 | Edges run through labels; nodes and labels compete for space | Labels are not in the layout's collision model. The author is exempt from collisions with its own Requests (`collisionIgnore = {authorId}`, `constellation_layout.dart:249-257`). Markers overlap the label (UI-14). | R03, R04 |
| UI-03 | P0 | Graph labels become much smaller than the rest of the UI text | Labels and chips are inside the transformed canvas (`LabelsView` and `GraphView.builder`), so a camera scale of 0.7 renders 13 px as about 9 px | R03 |
| UI-04 | P1 | Request titles are cut off before they convey meaning | `BottomLabelBuilder(labelSize: Size(100, 20))`, one line with ellipsis. The box is shorter than one line at text scale ≥1.3. | R03 |
| UI-05 | P1 | Satellites crowd into a vertical branch below the ego | Ego fan direction `(0,1)`, radius 56, chord 29 px < body size. Hidden Requests (UI-11) also take slots. | R04 |
| UI-06 | P1 | Pale person connections disappear next to dark attachments | Tier-1 contrast is 1.18:1 (light) and 1.73:1 (dark). Attachments use `secondary`. | R05 |
| UI-07 | P1 | Small nodes and markers are hard to recognise and tap | Hit rect = body (36–40 scene px, so about 25 px on screen at 0.7). Double tap dispatch. Markers are 19 px and overlap the label (UI-14). | R03, R06 |
| UI-08 | P2 | No visible camera recovery; the compact Field tab has no label; mode icons are cryptic | No fit/centre controls on the Field (the People graph has them in `graph_app_bar_actions.dart`). The legend button uses `Icons.map`, which reads as "Map mode". `_labelsFit` ignores `TextScaler`. The Row splits free space 1:1 between `Expanded(title)` and `Flexible(toggle)`, so the toggle hides its labels at 375 px. The nav label was hidden on purpose (see §6.1). | R07 |
| UI-09 | P1 | The label budget receives a font size instead of a ratio | `_syncLabelBudget` passes `TextScaler.scale(14)` into the ratio-based `constellationLabelBudget` | R01 |
| UI-10 | P0 | The budget is applied late; counts jump after unrelated actions | `updateLabelBudgetContext` never recomposes. The first load uses the default budget; later recomposes use the broken one (tab reselect: about 2 Requests total on a phone). | R01 |
| UI-11 | P1 | Hidden Requests take up layout space | Scene layout input includes all Requests, not only the drawn ones | R04 |
| UI-12 | P0 | Overflow chips drift away from their author | `GraphView.builder` is outside the per-frame `AnimatedBuilder` | R03 |
| UI-13 | P1 | No way to collapse an expanded author on the map | `hidden == 0`, so no chip is built | R03 |
| UI-14 | P1 | The pin icon (and the Request status glyph) sits under the node and covers the name/title | Marker row at `Positioned(bottom: -tt.iconSize)` in `_ConstellationMapNode`, in the label's band; applies to people (pin) and Requests (status + pin) | R03 (step 8), R04 (footprint) |

### 1.2 Source map (line numbers at `3f205d144`)

| Responsibility | Where |
|---|---|
| Budget sync, graph stack, fixed labels, map node + markers, overflow overlay, edge painter | `packages/client/lib/features/constellation/ui/widget/constellation_body.dart`: `_syncLabelBudget` 64, `build` 357 (LayoutBuilder 465), `_buildGraphStack` 526, `BottomLabelBuilder` 597, `_ConstellationMapNode` 727, `_MapOverflowOverlay` 753, `ConstellationEdgePainter` 821 |
| Budget formula + allocation | `domain/constellation_density.dart` (`constellationLabelBudget`, `allocateVisibleRequests`) |
| Composition (drawn / overflow / eligible sets) | `domain/constellation_anchor_composition.dart`: `composeConstellationPresentation` 112, `_buildLabelDisplayPlan` 352 |
| Cubit: budget context 951, recompose 1586, `_reconcileLayout` 1619, `_rebuildGraph` 1630 (layout request maps set at 1682-1685), `toggleSatelliteOverflow` 1191, `orderedNodesForPaint` 1043, `mapNodeAtSceneCentre` 1362 (only used by `constellation_scene_handoff_test.dart`), scene layout getter 216 | `ui/bloc/constellation_cubit.dart` |
| Automatic placement | `domain/constellation_layout.dart`: `computeConstellationPlacedLayout` 156, `placeAutomatic` 240, `_chooseAutomaticPosition` 358, `_totalIntersectionArea` 513, `_computeSemanticIdeals` 571 |
| Pin-from-text layout input | `domain/constellation_pin_position.dart`: `layoutInputFromComposition` 98 |
| Fan helpers | `features/graph/domain/layout/radial_hop_positions.dart`: `branchUnitDirection` 197, `localFanPositions` 301, `kFanRadiusMultiplier = 3`, `kDefaultMaxFanRadians = 2π/3` |
| Scene adapter | `features/graph/ui/utils/tentura_layout_algorithms.dart`: `ConstellationSceneLayoutAlgorithm` 269 (value `==` at 391; **new fields must join `==`/`hashCode`**, because `GraphView.didUpdateWidget` re-applies configuration when the algorithm is unequal) |
| Node widget + semantics | `features/graph/ui/widget/graph_node_widget.dart` (with `onTap == null` it returns **without** Semantics or GestureDetector, lines 146-162) |
| Edge ids | `features/constellation/ui/utils/constellation_graph_scene.dart` (`constellationSceneEdgeId`, `constellationEdgeIdForEdge` suffix scan) |
| Overflow chip | `ui/widget/constellation_overflow_group.dart` |
| Status / pin markers | `ui/widget/constellation_request_status_marker.dart` |
| App bar row + mode toggle | `ui/widget/constellation_app_bar.dart` |
| Legend swatches | `features/graph/ui/widget/graph_legend_content.dart` (Constellation rows 104-116; dash swatch painter 515+, dash 5 / gap 4 vs painter 6 / 4) |
| Home nav | `features/home/ui/screen/home_screen.dart:298` (`label: ''`, `commandChrome: true`), `features/home/ui/widget/home_bottom_navigation_bar.dart` (`_CommandNavDisk` size `(64+44)/2 = 54`) |
| Graph package | `packages/force_directed_graphview/lib/src/`: `controller.dart` (`fitToNodeIds` 161, `sceneToViewportLocal` 200, `jumpToPosition` 431, `fitToRect` 487, `_applyConfiguration` ~880, `_updateViewport` 915), `graph_view.dart` (`_CameraGatedInteractiveViewer`), `widget/graph_layout_view.dart`, `widget/labels_view.dart`, `widget/nodes_view.dart`, `widget/edges_view.dart`, `widget/node_drag_gesture.dart` (`_onPointerDown` 103, `_onPointerMove` 171, `_onPointerUp` 210, `_hitTestTopmostNodeIdInSnapshot` 279), `configuration.dart`, `edge_painter/edge_painter.dart` |
| People-graph camera pattern to copy | `features/graph/ui/widget/graph_app_bar_actions.dart` (`_navIconButton`, `TestIds.graphFit`, `TestIds.graphCenterView`), `GraphCubit.jumpToEgo(resetScale: true)` |
| Tokens | `lib/design_system/tentura_tokens.dart` (a new field is edited in **5 places**: constructor + field, `light`, `dark`, `copyWith`, `lerp`; see how `graphPersonContextWidth` appears at lines ~59, 151, 205, 256, 480, 561) |

### 1.3 Facts the implementer must know

- **Coordinate spaces.** *Scene* is the 4096×4096 canvas; the ego is at `(2048, 2048)` (`kConstellationCanvasCentre`); saved anchors use v1 units of 170 scene px. *Viewport* is the logical pixels of the `GraphView` box. `viewport = controller.sceneToViewportLocal(scene)`. *Camera scale* is `TransformationController.value.getMaxScaleOnAxis()`. The **readable scale is 1.0**: at scale 1.0, one scene px equals one logical px.
- **Node ids.** Always use `tenturaGraphNodeId(node)` or `constellationGraphNodeIdForTarget(target)`. Never build id strings by hand.
- **Body sizes.** `FieldPersonNode.size = 40`, `FieldRequestNode.size = 36`. Scene nodes are square with side = `size`.
- **Paint order.** `cubit.orderedNodeIdsForPaint()` puts unanchored nodes first, then anchors by `ConstellationAnchor.comparePaintOrder`, then the node being placed. Later entries paint **and** hit-test on top (D21/D22). Every new layer uses this same order.
- **Tokens.** `tt.tightGap = 2`, `tt.iconTextGap = 6`, `tt.rowGap = 8`, `tt.iconSize = 22`, `tt.buttonHeight = 44`, `tt.bottomNavHeight = 64`, `TenturaText.labelSmall` = 13 px w500 height 1.35, `labelLarge` = 15 px w700. Use `kMinInteractiveDimension` (48) for graph tap targets.
- **Lints** (`packages/tentura_lints`): no inline font sizes, raw colours, raw `BorderRadius`, raw `EdgeInsets` numbers, or raw `TextStyle` in `features/**` and `ui/**`. Token-derived expressions such as `EdgeInsets.symmetric(horizontal: tt.iconTextGap)` are allowed. Behavioural numeric constants (thresholds) are fine as named `const` values.
- **Codegen.** No `ConstellationState` (freezed) field is needed by this plan. If you add one anyway, run build_runner for `packages/client`. After editing ARB files, run `flutter gen-l10n` in `packages/client`. Never hand-edit generated files.
- **Concurrent work.** The tree may contain other agents' uncommitted edits (for example `tentura_top_bar.dart`, updates chrome, the version bump). Never stage or revert files you did not change for this plan.

---

## 2. Contracts that remediation must preserve

Read together with [the feature spec](../features/constellation.md), [edge semantics](constellation-edge-semantics.md), [pinning decisions](constellation-pinning-plan.md), and [scene decoupling plan](force-directed-graphview-scene-decoupling-plan.md).

1. **Pinned positions are authoritative.** D20 allows overlapping anchors. D21 requires ordinary topmost interaction (no chooser, fan-out, or cluster). D22 orders pins by server placement time with stable tie-breaks. Opening a preview must not raise a pin. Pins never enter any automatic fallback.
2. **Pinned and automatic budgets are independent (D23).** Every eligible pin stays represented. Never hide, aggregate, evict, or move a pin to satisfy density.
3. **Semantic placement stays meaningful.** The ego is at the centre; people keep path-depth rings, stable sectors, residual-ring membership, and today's placement (see §0.3.3); Requests stay near their authors; the narrowed A3 stability scope holds.
4. **Presentation never widens access.** Filters, caps, dormant pins, preflight, eligible Request ids, and Map/Text parity stay unchanged. A hidden label is not a hidden Request.
5. **Edges keep their meaning.** Tier-1, tier-2, attachment, and residual stub stay distinct. Do not add, merge, or re-parent edges to reduce crossings.
6. **Scene identity stays id-based.** Keep layout-ticket rejection, presentation tokens, lifecycle cancellation, and same-frame paint/hit consistency.
7. **Dependency direction is inward.** The domain (`constellation_layout.dart`) receives plain numbers and ids. Text measurement, transforms, and themes stay in UI or the graph package. No new `Request` domain entity (enforced by `no_request_domain_entity`).
8. **The design system is authoritative.** Use `context.tt`, `TenturaText.*`, and `ColorScheme` roles; add missing tokens centrally; text respects system scaling.

Non-goals: server/schema/permission changes, saved-coordinate migration, a new graph navigation architecture, changes to field membership, general edge rerouting, keyboard traversal of graph nodes, and closing unrelated release gates.

---

## 3. Target design

### 3.1 Layers after remediation

```
ConstellationBody._buildGraphStack (Stack)
├─ GraphView                          ← scene space, transformed by the camera
│   ├─ EdgesView     (ConstellationEdgePainter; repaints on camera change)
│   ├─ LabelsView    (labelBuilder: null for Constellation → empty)
│   └─ NodesView     (bodies + top-corner badges: pin top-end, status top-start;
│                     nothing below the body; no GestureDetector on the body)
│      NodeDragGesture Listener: body hit = drag; nodeTapHitTester = tap
├─ ConstellationViewportOverlay       ← NEW, viewport space, not transformed
│   ├─ label plates   (IgnorePointer + ExcludeSemantics; fixed screen size)
│   └─ author chips   (interactive; "+N more" / "Show fewer")
├─ ConstellationCameraControls        ← NEW (R07), top-right
├─ LinearPiActive, legend, person panel, provisional placement bar (unchanged)
```

- Labels are `IgnorePointer`, so a tap or pan that starts on a label reaches the `InteractiveViewer`. The package tap hit tester maps the tap to the label's node (R02/R06). Starting a pan on a label pans the camera. Only a painted **body** can start a node drag.
- Chips are real buttons and absorb their own taps. A pan cannot start on a chip, which is acceptable for a button.
- `GraphView.builder` (the old `_MapOverflowOverlay`) is removed for Constellation.

### 3.2 Graph package seams (all opt-in; defaults unchanged)

Add to `packages/force_directed_graphview` (exported from `force_directed_graphview.dart` where new files are added):

```dart
// controller.dart
final ValueNotifier<int> _cameraRevision = ValueNotifier<int>(0);
/// Increments on every camera transform change (pan/zoom/fit/jump).
ValueListenable<int> get cameraRevision => _cameraRevision;
/// Current uniform camera scale; 1.0 before a view is attached.
double get cameraScale =>
    _transformationController?.value.getMaxScaleOnAxis() ?? 1.0;
/// Viewport size in logical pixels, or null before the first layout.
Size? get viewportSize => _viewportPixelSize;

void fitToRect(
  Rect rect, {
  double padding = 48,
  EdgeInsets viewportInsets = EdgeInsets.zero, // NEW: usable region
  double? maxScale,                            // NEW: e.g. 1.0 for "show all"
});
void jumpToPosition(
  Offset position, {
  bool resetScale = false,
  EdgeInsets viewportInsets = EdgeInsets.zero, // NEW: centre in usable region
});

// configuration.dart
/// Optional tap resolver. Returns the node for a short press at
/// [scenePosition], or null for "no opinion" (the package then uses its
/// default body hit test). Never used to start a drag.
typedef NodeTapHitTester = GraphNodeId? Function(
  Offset scenePosition,
  List<GraphNodeId> orderedNodeIds,
);
// GraphView gains `NodeTapHitTester? nodeTapHitTester`, passed via GraphViewConfiguration.

// edge_painter.dart
/// Edge painter that must repaint when [repaint] notifies (e.g. camera scale).
abstract interface class RepaintingEdgePainter<N, E> implements EdgePainter<N, E> {
  Listenable get repaint;
}
```

### 3.3 Viewport presentation frame (client, pure Dart)

New file `packages/client/lib/features/constellation/ui/utils/constellation_presentation_frame.dart`. It holds pure value types and functions only: it may import `dart:ui` and `package:flutter/foundation.dart`, but **no widgets or `BuildContext`**. This keeps it unit-testable.

```dart
enum ConstellationDetailLevel { normal, overview }

const kConstellationNormalDetailScale = 0.85;   // at or above → normal
const kConstellationOverviewDetailScale = 0.70; // below → overview
// Between the two thresholds, keep the previous level (hysteresis).

ConstellationDetailLevel nextConstellationDetailLevel(
  double cameraScale,
  ConstellationDetailLevel previous,
) {
  if (cameraScale >= kConstellationNormalDetailScale) return ConstellationDetailLevel.normal;
  if (cameraScale < kConstellationOverviewDetailScale) return ConstellationDetailLevel.overview;
  return previous;
}

@immutable
final class ConstellationFrameNodeInput {
  final GraphNodeId id;
  final Offset centre;        // viewport px
  final double bodyDiameter;  // viewport px = size * cameraScale
  final double badgeOverhang; // viewport px the top badges extend above the body (0 = no badge)
  final Size labelSize;       // viewport px, measured plate size (Size.zero = no label)
  final int priority;         // 0 selected, 1 ego, 2 person, 3 request
  final int ring;             // for stable person ordering; 0 for requests
  final bool labelCandidate;  // false → label suppressed by detail policy
}

@immutable
final class ConstellationFrameChipInput {
  final String authorId;
  final GraphNodeId authorGraphId;
  final Size size;            // viewport px, measured chip size
}

@immutable
final class ConstellationPresentationFrame {
  final Object snapshot;             // identical() check against controller.renderSnapshot
  final int cameraRevision;          // equality check against controller.cameraRevision.value
  final ConstellationDetailLevel detail;
  final List<GraphNodeId> paintOrder;
  final Map<GraphNodeId, Rect> bodies;     // viewport px
  final Map<GraphNodeId, Rect> labels;     // only placed labels
  final Map<GraphNodeId, Rect> tapTargets; // body rect grown to ≥ 48×48
  final Map<String, Rect> chips;           // authorId → rect
  final Set<GraphNodeId> forcedLabels;     // mandatory labels placed despite overlap (diagnostics)
}

ConstellationPresentationFrame computeConstellationPresentationFrame({
  required Object snapshot,
  required int cameraRevision,
  required ConstellationDetailLevel detail,
  required Size viewport,
  required List<ConstellationFrameNodeInput> nodesInPaintOrder,
  required List<ConstellationFrameChipInput> chips,
  required double gap,        // tt.tightGap
  required double minTarget,  // kMinInteractiveDimension
  required bool rtl,
});
```

Algorithm, deterministic with no randomness:

1. `bodies[id] = Rect.fromCircle(center: centre, radius: bodyDiameter / 2)`. For collision purposes (steps 3–5 only; not for tap resolution) use the *decorated* body `Rect.fromLTRB(b.left - badgeOverhang, b.top - badgeOverhang, b.right + badgeOverhang, b.bottom)`, because the corner badges stick out above and to the sides. An "above" label must never cover the pin. Cull: skip nodes whose body grown by `max(labelSize.width, labelSize.height) + gap` does not intersect `Offset.zero & viewport`.
2. `tapTargets[id]` = the body rect grown symmetrically so each side is at least `minTarget`.
3. `occupied` = every culled-in body rect grown by 1 px.
4. **Chips first** (they are controls and are mandatory). For each chip, sorted by `authorId`: take the author's body rect `B` (skip the chip if the author is culled), then build `U = B ∪ (the author's label rect below B)`. Before any label is placed, reserve the author's own label slot as the "below" candidate. Candidates, in order: below `U`, end of `B`, start of `B`, above `B`, each separated by `gap`; *end* is right in LTR and left in RTL. Take the first candidate fully inside the viewport that does not intersect `occupied`. Otherwise take candidate 0. Add it to `occupied`.
5. **Labels.** Sort candidate nodes by `(priority, ring, id)`. For each node with `labelCandidate && labelSize != Size.zero`, the candidates are below / above / end / start of the body. Below and above are centred horizontally; end and start are centred vertically. Accept the first candidate inside the viewport that does not intersect `occupied`. If none fits and `priority <= 1` (selected or ego), place "below" anyway and add the node to `forcedLabels`. Otherwise suppress the label. Add each placed rect to `occupied`.
6. Return the frame. Brute-force rectangle checks are fine: at most about 300 nodes, well under 1 ms. Add a uniform grid only if R08 profiling shows the frame costs more than 2 ms.

Detail policy for `labelCandidate`:

- **normal**: every node.
- **overview**: the selected node, the ego, and people with `ring <= 1` only.

Chips are always candidates. Selection does not change pin order.

### 3.4 Tap resolution (client, pure Dart, same file or `constellation_tap_resolver.dart`)

```dart
/// Returns the node for a tap at [p] (viewport px), or null for "no opinion".
GraphNodeId? resolveConstellationTap(ConstellationPresentationFrame f, Offset p) {
  // 1. Label plates, topmost first (labels are drawn above all bodies).
  //    Iterate f.paintOrder in reverse; return the first id whose label contains p.
  // 2. Painted bodies, reverse paint order (D21/D22: topmost pin wins).
  // 3. Tap targets: among ids whose tapTarget contains p, return the one with
  //    the nearest body centre; on a tie, the one later in paint order.
  // 4. null.
}
```

The Constellation `nodeTapHitTester` closure:

```dart
(scenePosition, orderedIds) {
  final frame = _frameHolder.frame;
  final c = cubit.graphController;
  if (frame == null ||
      !identical(frame.snapshot, c.renderSnapshot) ||
      frame.cameraRevision != c.cameraRevision.value) {
    return null; // stale → package default body hit test
  }
  return resolveConstellationTap(frame, c.sceneToViewportLocal(scenePosition));
}
```

`_frameHolder` is a plain mutable holder (`final class ConstellationPresentationFrameHolder { ConstellationPresentationFrame? frame; }`) owned by `_ConstellationBodyState`. The overlay writes it on every frame computation; it does **not** notify.

### 3.5 Structural (scene) placement changes

The implementation is in R04. Summary:

- **Footprint type** (domain, `constellation_layout.dart`):

  ```dart
  /// Distances from the node centre to each side of its readable footprint,
  /// in scene px at readable camera scale 1.0. All values are >= 0.
  typedef ConstellationFootprint = ({double left, double top, double right, double bottom});
  typedef ConstellationFootprintMetrics = ({
    double labelGap,
    double personLabelWidth, double personLabelHeight,   // 1-line plate
    double requestLabelWidth, double requestLabelHeight, // 2-line plate
    double chipWidth, double chipHeight,
    double badgeOverhang, // how far top-corner badges extend past the body edge
  });
  enum ConstellationFootprintKind { person, request }
  ConstellationFootprint constellationNodeFootprint({
    required ConstellationFootprintKind kind,
    required double bodySize,
    required bool hasAuthorChip,
    required ConstellationFootprintMetrics metrics,
  }) {
    final r = bodySize / 2;
    final labelW = kind == ConstellationFootprintKind.person
        ? metrics.personLabelWidth : metrics.requestLabelWidth;
    final labelH = kind == ConstellationFootprintKind.person
        ? metrics.personLabelHeight : metrics.requestLabelHeight;
    var half = math.max(r + metrics.badgeOverhang, labelW / 2);
    var bottom = r + metrics.labelGap + labelH;
    if (hasAuthorChip) {
      bottom += metrics.labelGap + metrics.chipHeight;
      half = math.max(half, metrics.chipWidth / 2);
    }
    return (left: half, top: r + metrics.badgeOverhang, right: half, bottom: bottom);
  }
  ```

- **Layout input** gains `Map<String, ConstellationFootprint> footprints` (default `const {}`). Missing entries fall back to a symmetric box from the body size. With an empty map, behaviour is exactly as today (legacy tests stay valid).
- **Obstacles.** Every placed node (pinned, support, and automatic people; placed Requests) records its footprint rect as an obstacle.
- **People** are tested with body-only boxes, exactly as today. **Requests** are tested with their full footprint against every obstacle, **including their author**.
- **Satellite radius** = `max(satelliteOffset, authorBody/2 + spacing + requestHalfExtent)`, where `requestHalfExtent = max(fp.left, fp.right, fp.top, fp.bottom)`. The fan `minChord = fp.left + fp.right + spacing`. Both apply only when footprints are supplied.
- **Ego fan direction** is the bisector of the largest angular gap between the ego's depth-1 people (their ideal angles). With no people, it is `(0,1)`. The fan span is limited to `min(kDefaultMaxFanRadians, gap * 0.8)`.
- **Candidate ranking** for Requests, compared in order: (a) zero footprint overlap; (b) the author→candidate attachment segment crosses no other node's body box; (c) existing candidate order. If no candidate satisfies (a), keep today's least-intersection fallback.
- **Layout set.** Only **drawn, unpinned** Requests are laid out (fixes UI-11). Pin-from-text uses the same helper.

---

## 4. Ordered implementation work

Each unit ends with its focused checks and a journal entry in `docs/plans/constellation-ui-remediation-journal.md`. The entry lists changed files, commands run with results, deviations, and remaining failures. Run one heavy process (flutter test/build) at a time. Commit only this unit's files when commits are requested.

Dependency order: **R00 → R01 (ships alone) → R02 → R03 → R04 → R05 → R06 → R07 → R08.** R05 needs only R02. R07 needs R02 and R03.

### R00: Shared fixture and baseline record

Dependencies: none.

Steps:

1. Create `packages/client/test/features/constellation/fixtures/constellation_reference_fixture.dart` containing:
   - `const kRefEgo = Profile(id: 'ego', displayName: 'Vadim');`
   - `ConstellationField constellationReferenceField({int egoRequestCount = 6})`. Model it on `_baseField` in `constellation_density_widget_test.dart` and use `req-` id prefixes.
     - Peers: `am` ("agent m9x4u2k7"), `in` ("invite6"), `sm` ("SurmatMG").
     - Tier-1 edges `ego↔am`, `ego↔in`, `ego↔sm`.
     - Requests:
       - `ego`: `req-ego-1` "Тентура: Autumn release planning", `req-ego-2` "Tentura: UI polish pass before the release", `req-ego-3` "blabla", and `req-ego-4`..`req-ego-6` with long mixed-script titles.
       - `am`: `req-am-1` "Test Beacon".
       - `in`: `req-in-1` "Blabla" and `req-in-2` "didjdjeh".
       - `sm`: `req-sm-1` "I need documents translated into English for the visa office".
     - Every request has `status: 0`.
   - `ConstellationFieldCase constellationCaseForField(ConstellationField f)`. Move the `_StubRepository` / `_caseForField` pattern from `constellation_density_widget_test.dart`.
   - `Future<ConstellationCubit> loadReferenceCubit({ConstellationField? field})`: construct the cubit and wait for `StateIsSuccess`.
   - `Future<void> pumpConstellationBody(WidgetTester tester, {required ConstellationCubit cubit, Size size = const Size(375, 547), double textScale = 1.0, Locale locale = const Locale('ru'), ThemeData? theme})`. Move `_pumpBody` from `constellation_body_test.dart:102`, with its `GraphPersonContextCubit` fake. Keep the old tests working by calling the shared helper.
2. Add `constellation_reference_fixture_smoke_test.dart`: the fixture loads, the body pumps at 375×547 without exceptions, and after `pumpAndSettle` the graph controller has positions for every scene node.
3. Record baseline numbers in the journal. You can gather them with a temporary local test that is **not committed**:
   - the budget the cubit receives with the body pumped at 375×547 (expect `textScaleFactor == 14.0`);
   - `overflowHiddenCountByAuthor` after the first load (expect `{ego: 3}`) and, with the body still pumped, after `toggleSatelliteOverflow('in')` twice (expect the ego's count to change to 5 because the recompose picks up the broken budget: the UI-10 proof);
   - label box size;
   - the chip rect vs. the `req-ego-*` body rects.
4. Optional in this unit, required in R08: a browser screenshot at 375×667 through the `local-debug` skill runbook. Record URL, build version, DPR, locale, theme, and camera scale.

Done when: the fixture and smoke test are committed and green, and the journal holds the baseline numbers.

### R01: Correct and apply the label budget (UI-09, UI-10). Ships alone.

Dependencies: R00.

Expected budgets from the unchanged formula (put them in tests):

| Graph viewport | Ratio | Budget `(perPerson, total)` |
|---|---|---|
| 375×547 | 1.0 | (1, 28) |
| 375×547 | 1.3 | (1, 21) |
| 375×547 | 14 (today's bug) | (1, 2) |
| 1200×900 | 1.0 | (3, 150) (today's first-load default) |

The per-author cap of 1 on phones is the formula's documented intent ("scales with viewport area", feature spec §Density). Do not change the formula in this unit. §6.1 lists it as an owner note.

Steps:

1. `constellation_body.dart`:
   - Wrap the **whole** `BlocBuilder` result, including the loading and error branches, in a `LayoutBuilder`. The viewport is then known before the first composition.
   - Replace `_syncLabelBudget` with `_scheduleLabelBudgetSync(BuildContext context, Size viewport)`:

     ```dart
     final style = TenturaText.labelSmall(Theme.of(context).colorScheme.onSurface);
     final reference = style.fontSize!; // 13, the graph label role
     final ratio = MediaQuery.textScalerOf(context).scale(reference) / reference;
     if (_lastLabelBudgetViewport == viewport && _lastLabelBudgetTextScale == ratio) return;
     _lastLabelBudgetViewport = viewport;
     _lastLabelBudgetTextScale = ratio;
     final cubit = context.read<ConstellationCubit>();
     WidgetsBinding.instance.addPostFrameCallback((_) {
       if (!mounted) return;
       cubit.updateLabelBudgetContext(viewport: viewport, textScaleFactor: ratio);
     });
     ```

   - Do **not** call the cubit synchronously from build.
2. `constellation_cubit.dart`:
   - Add `ConstellationLabelBudget? _appliedLabelBudget;` and `ConstellationLabelBudget _currentLabelBudget()`. The helper computes `constellationLabelBudget(...)` from the stored viewport and ratio and assigns `_appliedLabelBudget`. Use it at **all four** compose sites: `load` (both uses: pass the same local value), `_mergeConfirmedProjection`, `_recomposeAndLayout`, and `_displayPlan`.
   - Rewrite `updateLabelBudgetContext`:

     ```dart
     void updateLabelBudgetContext({required Size viewport, required double textScaleFactor}) {
       assert(textScaleFactor > 0 && textScaleFactor <= 4,
           'textScaleFactor is a dimensionless ratio, not a font size');
       if (isClosed || viewport.isEmpty || !viewport.isFinite) return;
       _labelBudgetViewport = viewport;
       _labelBudgetTextScale = textScaleFactor;
       final next = constellationLabelBudget(viewport: viewport, textScaleFactor: textScaleFactor);
       if (next == _appliedLabelBudget || state.field == null) return; // load() will use it
       if (_placementBusy) { _labelBudgetRecomposePending = true; return; }
       _recomposeAndLayout();
     }
     bool get _placementBusy =>
         state.hasPendingPlacementWrite ||
         (_anchorCase?.hasPendingWrite ?? false) ||
         _draggingNodeId != null;
     ```

   - In `_cancelUnsentPlacement`, after it emits: if `_labelBudgetRecomposePending`, clear the flag and call `_recomposeAndLayout()` instead of `_reconcileLayout()`. The write-outcome paths already recompose through `_mergeConfirmedProjection`; clear the flag there too.
   - Add `@visibleForTesting double get labelBudgetTextScaleForTest => _labelBudgetTextScale;`.
3. Leave `constellation_density.dart` unchanged apart from a doc comment on `textScaleFactor`: "dimensionless ratio; 1.0 = default text size".

Tests:

- `constellation_density_test.dart`: add the four rows of the table above.
- New `constellation_label_budget_context_test.dart` (uses the R00 fixture):
  - After load (default budget), `overflowHiddenCountByAuthor['ego'] == 3`.
  - `updateLabelBudgetContext(Size(375, 547), 1.0)` gives `overflowHiddenCountByAuthor['ego'] == 5` and `['in'] == 1`.
  - Calling it again with the same inputs does not change `layoutReconciliationCount`.
  - `toggleSatelliteOverflow('in')` twice leaves `['ego'] == 5` (the UI-10 regression).
  - During `beginDragExisting`, an update is deferred; `cancelPlacement()` then applies it.
- Widget test in `constellation_body_test.dart`: pump the body at 375×547.
  - With `TextScaler.linear(1.0)`, `labelBudgetTextScaleForTest == 1.0`.
  - With `linear(1.3)`, it is `closeTo(1.3, 1e-9)`.
  - With a non-linear scaler class (`scale(x) => math.min(x * 2, x + 6)`), it is `closeTo(19 / 13, 1e-9)`.
- `constellation_tab_reselect_test.dart`: after reselect → `load()`, overflow counts equal the counts before reselect.

Done when these tests pass, together with `flutter test test/features/constellation`. This unit may be released on its own (see R08 steps 5–6).

### R02: Graph package seams (no client behaviour change)

Dependencies: none, but land it after R01. It touches only `packages/force_directed_graphview`.

Steps:

1. **Camera listenable** (`controller.dart`).
   - Add `_cameraRevision`, `cameraRevision`, `cameraScale`, and `viewportSize` from §3.2.
   - In `_applyConfiguration`, if the incoming `transformationController` is not identical to the current one, call `_transformationController?.removeListener(_onCameraChanged)`, assign the new one, and `addListener(_onCameraChanged)`.
   - `void _onCameraChanged() => _cameraRevision.value++;`.
   - Remove the listener where the binding detaches (the code that sets `_transformationController = null`, ~line 872). Dispose `_cameraRevision` in `dispose()`.
2. **Insets / maxScale.**
   - `fitToRect`: `usable = Rect.fromLTRB(insets.left, insets.top, pixel.width - insets.right, pixel.height - insets.bottom)`. If `usable` is empty, fall back to the full viewport. `scale = min(usable.width / padded.width, usable.height / padded.height).clamp(_boundaryMinScale(), maxScale == null ? _maxScale : math.min(maxScale, _maxScale))`. The matrix is `translate(usable.center) · scale · translate(-padded.center)`.
   - `jumpToPosition`: translate to `usable.center` instead of the pixel centre.
   - Defaults (`EdgeInsets.zero`, `maxScale: null`) must produce identical matrices to today.
3. **Tap hit tester.**
   - Add `NodeTapHitTester` to `configuration.dart`, the `nodeTapHitTester` field on `GraphViewConfiguration`, and the `GraphView` constructor parameter.
   - In `node_drag_gesture.dart`:
     - Add `GraphNodeId? _pendingTapNodeId`.
     - `_onPointerDown`: compute `bodyId` exactly as today. Compute `tapId = _configuration.nodeTapHitTester?.call(pos, pass.orderedNodeIds) ?? bodyId`, using the same `_captureDragPassSnapshot()` order. If both are null, return. Set `_pendingNodeId = bodyId` (may be null), `_pendingTapNodeId = tapId`, and the pointer/down position as today.
     - `_canStartTouchNodeDrag` and the mouse-capture branch keep using `_pendingNodeId` only. A null value means the gesture is a camera pan.
     - `_onPointerMove`: at the top, handle the tap-only case. If `_pendingNodeId == null && _pendingTapNodeId != null && event.pointer == _pendingPointer` and the move is `>= kTouchSlop`, clear the pending tap (`_cancelPendingCapture()`) and return. The rest is unchanged.
     - `_onPointerUp`: tap with `_pendingTapNodeId ?? nodeId`.
     - `_cancelPendingCapture` clears `_pendingTapNodeId`.
4. **Repainting edge painter.**
   - Add `RepaintingEdgePainter` to `edge_painter.dart`.
   - In `edges_view.dart`, generalise the painter's `animation` input to `Listenable? extraRepaint`: `AnimatedEdgePainter(:final animation) => animation`, `RepaintingEdgePainter(:final repaint) => repaint`, `_ => null`. Merge it into `repaint` as today. Keep `shouldRepaint` as is.

Tests (package):

- `controller_test.dart`:
  - `cameraRevision` increments after `jumpToPosition` and after `zoomBy`.
  - `cameraScale` equals the matrix scale.
  - `fitToRect(rect, viewportInsets: EdgeInsets.only(right: 100), maxScale: 1.0)` puts `sceneToViewportLocal(rect.center)` within 0.5 px of the usable-region centre, with scale ≤ 1.0.
  - Default arguments produce the same matrix as before the change: compare against a matrix computed with the old formula in the test.
- `node_drag_gesture_test.dart` (the existing tests must pass unchanged):
  - With a tester that maps a point 30 px below node `b` to `b`: a tap there calls `onNodeTap(b)` once.
  - A 40 px drag starting there changes the camera transform and never calls `onNodeDragStart`.
  - A tester that returns null still lets a body tap select via the default path.
- `scene_rendering_test.dart`: a `RepaintingEdgePainter` whose `repaint` notifier fires causes one more `paint` call (count calls).
- Then run `flutter test` (full package) and `dart analyze --format machine` in `packages/force_directed_graphview`, plus `flutter test test/features/graph` in `packages/client` (the People graph must be unaffected).

Done when package tests, analysis, and client graph tests are all green, and no client file changed except `GraphView` call sites (none are required).

### R03: Screen-space labels, chips, and markers (UI-03, UI-04, UI-12, UI-13, UI-14; part of UI-01/UI-02/UI-07)

Dependencies: R02.

Steps:

1. **Tokens** (`tentura_tokens.dart`, 5 places each; same value in light and dark):
   - `graphLabelMaxWidthPerson: 120` (outer plate width);
   - `graphLabelMaxWidthRequest: 144`.
2. **Frame module.** Implement §3.3 and §3.4 in `ui/utils/constellation_presentation_frame.dart`, plus `ConstellationPresentationFrameHolder`.
3. **Label measurement helper** (in the overlay file):

   ```dart
   Size measureConstellationLabelPlate({
     required String text, required TextStyle style, required int maxLines,
     required double plateWidth, required EdgeInsets padding,
     required TextScaler textScaler, required TextDirection direction,
   }) {
     final painter = TextPainter(
       text: TextSpan(text: text, style: style),
       maxLines: maxLines, ellipsis: '…',
       textDirection: direction, textScaler: textScaler,
     )..layout(maxWidth: plateWidth - padding.horizontal);
     return Size(painter.width + padding.horizontal, painter.height + padding.vertical);
   }
   ```

   - Style: `TenturaText.labelSmall(scheme.onSurface)`.
   - Padding: `EdgeInsets.symmetric(horizontal: tt.iconTextGap, vertical: tt.tightGap)`.
   - People use 1 line with `graphLabelMaxWidthPerson`; Requests use 2 lines with `graphLabelMaxWidthRequest`.
   - Text: `person.shownName`; for Requests, `request.title`, or `l10n.beaconViewTitle` if the title is blank.
   - Cache results in a `Map<(String, int, double, double), Size>` keyed by `(text, maxLines, plateWidth, textScaler.scale(13))`. Clear it when the theme brightness, locale, or text scaler changes, and when the cache grows past 4× the node count.
4. **Chip size helper.** Add `Size constellationOverflowChipSize(BuildContext context, String label)` in `constellation_overflow_group.dart`. It mirrors the widget: `width = 2*tt.screenHPadding + tt.iconSize + tt.iconTextGap + textWidth(labelLarge, textScaler)`, `height = max(tt.buttonHeight, textHeight + 2*tt.tightGap)`. Wrap the chip's `Material` in `SizedBox.fromSize(size: ...)` so the drawn size equals the measured size. Add a test that `tester.getSize(chip)` equals the helper within 0.5 px.
5. **Collapse control (UI-13).**
   - In `_buildLabelDisplayPlan`, also compute `expandedExtraCountByAuthor[author] = automaticIds.length - (allocated[author]?.length ?? 0)` for expanded authors when positive. Add it to `ConstellationLabelDisplayPlan` as a new final field, and pass `const {}` from `_rebuildGraph`'s legacy branch.
   - Mirror it into a cubit field `expandedExtraCountByAuthor` in `_rebuildGraph`.
   - `ConstellationOverflowGroup`:
     - collapsed state: label `constellationMoreRequests(count)`;
     - expanded state: new ARB key `constellationFewerRequests` (en "Show fewer", ru "Свернуть");
     - semantics label: new ARB key `constellationMoreRequestsByAuthor` with ICU plural and `{name}`. En: `"{count, plural, one{1 more request by {name}} other{{count} more requests by {name}}}"`. Ru: `"{count, plural, one{Ещё {count} запрос от {name}} few{Ещё {count} запроса от {name}} many{Ещё {count} запросов от {name}} other{Ещё {count} запроса от {name}}}"`. When expanded, the semantics label is the "Show fewer" text plus the name. Pass the name in via a new `authorName` parameter.
   - Run `flutter gen-l10n` in `packages/client`, then `bash scripts/check-user-facing-terminology.sh`.
6. **Overlay widget.** Add `ui/widget/constellation_viewport_overlay.dart` (`ConstellationViewportOverlay`, with parameters `cubit` and `frameHolder`):
   - `BlocBuilder<ConstellationCubit, ConstellationState>` with `buildWhen` on `selectedPersonId`, `selectedRequestId`, `graphRevision`, `placementPhase`, `viewMode`, wrapping a `ListenableBuilder(listenable: Listenable.merge([controller, controller.cameraRevision]))`.
   - In the builder:
     - If `!controller.canLayout`, return `SizedBox.shrink()`.
     - `snapshot = controller.renderSnapshot`.
     - `order = controller.orderedRenderNodeIds(snapshot, configuredPaintOrder: cubit.orderedNodeIdsForPaint())`.
     - `scale = controller.cameraScale`.
     - Update `_detail = nextConstellationDetailLevel(scale, _detail)`. Keep `_detail` in the overlay's `State`, starting at `normal`.
     - Build the inputs:
       - `centre = controller.sceneToViewportLocal(Offset(p.x, p.y))`, with `p` from `snapshot.resolvePosition(id)`;
       - `bodyDiameter = sceneNode.size.width * scale`;
       - `badgeOverhang = overhang * scale` when the node is pinned (person or Request) or is a Request with a known status, otherwise 0;
       - priority: 0 if selected, 1 if ego, 2 person, 3 Request;
       - `ring` from `FieldPersonNode.ring`;
       - chips for every author in `overflowHiddenCountByAuthor ∪ expandedExtraCountByAuthor` whose author node is in `order`.
     - Compute the frame and store it in `frameHolder.frame`.
     - Return a `Stack(clipBehavior: Clip.hardEdge)` containing:
       - one `Positioned.fromRect(rect: frame.labels[id]!, child: IgnorePointer(child: ExcludeSemantics(child: _LabelPlate(...))))` per placed label, in paint order, with key `ValueKey('constellation.label.$id')`;
       - one `Positioned.fromRect(rect: frame.chips[author]!, child: ConstellationOverflowGroup(...))` per chip.
   - `_LabelPlate`:
     - `DecoratedBox(decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(tt.buttonRadius), border: Border.all(color: scheme.outlineVariant)))`;
     - inside it, `Padding` with the same padding as step 3 and a `Text(text, maxLines:, overflow: TextOverflow.ellipsis, style:)`.
     - Opaque; do not use alpha on the plate colour.
7. **`constellation_body.dart` wiring.**
   - Remove `builder: (context, child) => _MapOverflowOverlay(...)` and delete the `_MapOverflowOverlay` class.
   - Set `labelBuilder: null`.
   - In `_buildGraphStack`, add `Positioned.fill(child: ConstellationViewportOverlay(cubit: cubit, frameHolder: _frameHolder))` directly after `GraphView`.
   - Add `final _frameHolder = ConstellationPresentationFrameHolder();` to `_ConstellationBodyState`.
8. **Pin and status markers as top-corner badges (UI-14).** Nothing may be drawn below the node body except the label.
   - Split the single marker row into **two independent badges**. The current row puts both glyphs side by side, about 40 px wide, which would cover the whole top of a 36 px Request.
     - **Pin badge:** top-**end** corner (top-right in LTR, top-left in RTL). Shown for pinned people **and** pinned Requests.
     - **Status badge:** top-**start** corner. Shown for Requests only; people keep `showStatus: false`.
   - In `constellation_request_status_marker.dart`, add a `ConstellationMarkerBadge` widget that renders one glyph: `ConstellationMarkerBadge.pin()` or `ConstellationMarkerBadge.status(rawStatus: ...)`.
     - The glyph size is `tt.iconSize * 0.85`, as today.
     - Put the glyph on a `DecoratedBox(decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant)))` with `Padding(EdgeInsets.all(tt.tightGap))`, so it stays legible over avatars and tiles.
     - Reuse `constellationRequestStatusPresentation` for the status icon and colour. The pin keeps `Icons.push_pin` in `tt.info`.
     - Keep the existing `Semantics` / `TestIds` (`constellationRequestStatusMarker`, `constellationPinMarker`) on the respective badge. They stay `ExcludeSemantics` under the node wrapper (R06 step 2), because the node label already carries status and pin.
     - Keep `ConstellationRequestStatusMarker` (the row) unchanged for the Text view and legend, which use it inline.
   - In `_ConstellationMapNode`, replace the `markers` parameter with `pinBadge` and `statusBadge` (both `Widget?`). Place them in the existing `Stack(clipBehavior: Clip.none)`:

     ```dart
     if (statusBadge != null)
       PositionedDirectional(top: -overhang, start: -overhang, child: statusBadge),
     if (pinBadge != null)
       PositionedDirectional(top: -overhang, end: -overhang, child: pinBadge),
     ```

     Here `overhang = badgeDiameter / 3`, and `badgeDiameter = tt.iconSize * 0.85 + 2 * tt.tightGap`. The badge centre sits just inside the corner of the body's bounding box and overlaps the body's rim, not the space below it.
   - Delete the old `Positioned(bottom: -tt.iconSize, ...)`. No marker may use a `bottom:` offset.
   - Badges live in scene space and scale with the camera, like the body. This is acceptable because status and pin are also in the node semantics (R06), the preview, and the Text view.
   - Taps on a badge resolve to its node. Badges are not separate targets: the part outside the node square receives no Flutter hit test, and pointer taps resolve through the package hit tester (§3.4).
   - Report the overhang to layout, so labels and neighbours never cover a badge:
     - viewport frame: `badgeOverhang = overhang * cameraScale` for nodes that show at least one badge, otherwise 0 (see §3.3 step 1);
     - scene footprint: `metrics.badgeOverhang = overhang` (see §3.5; it is part of `ConstellationFootprintMetrics`, filled in step 9).
9. **Pass footprint metrics to the cubit** (they are consumed in R04; plumb them here).
   - Compute `ConstellationFootprintMetrics` in the body. The label widths come from the tokens; the heights come from `measureConstellationLabelPlate` with a probe string `'Ág'` (1 line) and `'Ág\nÁg'` (2 lines) at the current scaler; the chip size comes from the helper with `constellationMoreRequests(99)`; `labelGap` is `tt.tightGap`; `badgeOverhang` is the step 8 `overhang`.
   - Send them with `cubit.updateFootprintMetrics(metrics)` in the same post-frame callback as the budget, skipping duplicates by record equality.
   - The cubit stores the metrics and, on change, calls `_reconcileLayout(deferAutomaticReflow: true)`. Until R04 nothing reads them.

Tests:

- New `constellation_presentation_frame_test.dart` (pure unit tests):
  - Two distant nodes: both labels below.
  - A node 10 px above the bottom edge: its label goes above.
  - Two nodes 30 px apart horizontally: the second label does not intersect the first (it goes above, end, or start).
  - Overview: Request labels are suppressed, while ego and depth-1 labels are present.
  - An ego label with no room is placed and listed in `forcedLabels`.
  - A chip never intersects any body rect when a free candidate exists.
  - The same input twice gives equal outputs (compare the maps).
  - Tap resolver: a point in a label returns that label's node even over another body; two overlapping bodies return the later one in paint order; a point outside all bodies but inside two tap targets returns the nearest centre; anything else returns null.
- New `constellation_viewport_overlay_test.dart` (reference fixture, `pumpConstellationBody` at 375×547, after `pumpAndSettle`):
  - Call `controller.zoomBy(0.5)` and pump. The label for `fieldPerson:sm` has `tester.getSize(...)` height ≥ `13 * 1.35` (independent of camera scale). Find the `Text` inside it and check that its `style.fontSize == 13`.
  - The chip for `ego` stays adjacent to the ego body: its global rect lies within `2 * kMinInteractiveDimension` of the ego body's global rect. After a 100 px pan (`tester.drag` on empty canvas), the chip rect and the body rect move by the same delta (±1 px).
  - After tapping the chip: `isSatelliteOverflowExpanded('ego')`, the chip still exists with the text "Свернуть"; tapping it again collapses.
  - `tester.takeException()` is null at text scale 2.0.
  - **UI-14 badge placement** (reference fixture with `req-in-2` and person `am` pinned through the anchor fixtures in `constellation_anchor_contract_fixtures.dart`; run at text scale 1.0 and 2.0, in `ru` and in an RTL `Directionality`):
    - `find.byKey(TestIds.key(TestIds.constellationPinMarker))` finds one badge per pinned node. For each badge, `badge.center.dy < body.center.dy` (upper half). `badge.center.dx > body.center.dx` in LTR and `< body.center.dx` in RTL (end side).
    - For every Request, the status badge centre is in the upper half, on the start side.
    - No badge rect (pin or status) intersects **any** placed label rect in the frame, including its own node's label and an "above" label. Assert with `frameHolder.frame!.labels.values`.
    - No badge's `bottom` extends below `body.bottom`. This is the direct regression check for `bottom: -tt.iconSize`.
    - An unpinned person has no pin badge and no status badge; a Request with an unknown raw status has no status badge.
- Update existing tests that looked up label `Text` under `LabelsView`, or used `ConstellationOverflowGroup(hiddenCount:)` directly, so they work with the new constructor parameters.

Done when:

- the new tests pass;
- `flutter test test/features/constellation test/features/graph` passes;
- `./scripts/check-custom-lints.sh packages/client` is clean against `scripts/custom-lint-baseline.txt` (re-read the baseline: it only drifts down);
- at a camera scale of 0.5 you have looked at one screenshot of the reference fixture (golden or `flutter run`) and seen the labels at readable size.

### R04: Collision-aware Request placement (UI-02, UI-05, UI-11; part of UI-01)

Dependencies: R03 (metrics plumbing).

Steps:

1. **Drawn-only layout set (UI-11).**
   - In `constellation_anchor_composition.dart`, add:

     ```dart
     ({Map<String, List<String>> byAuthor, Set<String> egoOwn}) constellationDrawnSatellites(
       ConstellationLabelDisplayPlan plan,
     )
     ```

     It keeps the ids that are in `plan.drawnRequestIds` and **not** in `plan.pinnedRequestIds`, drops empty lists, and returns `egoOwn = plan.egoOwnRequestIds ∩ drawn − pinned`.
   - Use it in `_rebuildGraph` (to set `layoutVisibleRequestsByAuthor` / `layoutEgoOwnRequestIds`) **and** in `layoutInputFromComposition` (replacing its local `visibleByAuthor` loop and `egoOwnRequestIds: labelPlan.egoOwnRequestIds`).
   - `_scratchInputAddingTarget` already adds a hidden target for pin-from-text; leave it.
2. **Footprints into the domain.**
   - Add the §3.5 types and `constellationNodeFootprint` to `constellation_layout.dart`.
   - Add `Map<String, ConstellationFootprint> footprints` to `ConstellationPlacedLayoutInput`. The record type change forces every construction site to pass it: `computeConstellationLayout` passes `const {}`; the two sites in `constellation_pin_position.dart` pass the incoming value through; `layoutInputFromComposition` gets a new optional `footprints` parameter.
   - Add `footprints` to `ConstellationSceneLayoutAlgorithm`, including `==` (`MapEquality`) and `hashCode`, and pass it into the input.
   - In the cubit, build `_layoutFootprints` in `_rebuildGraph` once `_footprintMetrics != null`. The key is the **domain** id (`node.id`); the kind comes from the node type; `hasAuthorChip` is `overflowHiddenCountByAuthor.containsKey(id) || expandedExtraCountByAuthor.containsKey(id)`. Pass it in `constellationSceneLayoutAlgorithm`, and in `pinFromText` / `canPinTarget` so both layouts agree.
3. **Obstacle model in `computeConstellationPlacedLayout`.**
   - Keep a local `Map<String, ConstellationBounds> obstacles`.
   - After each node is placed (pinned people and Requests at the top, then support people, automatic people, and Requests), store `_footprintBounds(id, point)`. That is the footprint when present, else today's `_sizeFor` box.
   - Change `_chooseAutomaticPosition` to take a `bool isRequest` and a `ConstellationFootprint candidateFootprint`:
     - people keep `size`-based bounds against `placed`/`placedSizes` exactly as today, so their results are bit-for-bit identical;
     - Requests test `candidate + candidateFootprint` (inflated by `spacing/2`) against `obstacles`.
   - Delete the `collisionIgnore` computation in `placeAutomatic` (no author exemption).
4. **Satellite geometry.**
   - In `_computeSemanticIdeals`, accept `footprints` and `spacing`.
   - When footprints are present, for each author (and the ego) compute `radius = max(satelliteOffset, authorBody/2 + spacing + maxExtent(requestFootprint))` and `minChord = requestFootprint.left + requestFootprint.right + spacing`, and pass `ringGap: radius, minChord: minChord` to `localFanPositions`. Use the first drawn Request's footprint; all Requests share the same canonical footprint.
   - Ego direction: add `({Offset direction, double gap}) constellationEgoSatelliteDirection(List<double> depthOneAngles)`. Normalise the angles to `[0, 2π)` and sort them. Add a wrap gap `first + 2π − last`, and choose the largest gap; on equal gaps, the smaller start angle wins. Return `Offset(cos(mid), sin(mid))`, where `mid = start + gap/2`. For an empty list return `(Offset(0, 1), 2π)`.
   - The angles are the `angle[id]` values (sector centres) of tree peers with `depth == 1`. `_computeSemanticIdeals` places a node at `angle − π/2`, so convert with the same `− π/2` offset.
   - Pass `maxFanRadians: math.min(kDefaultMaxFanRadians, gap * 0.8)` for the ego fan.
5. **Attachment-crossing preference.**
   - For Request candidates, first collect all candidates with zero overlap, in order. Return the first one whose segment from the author centre to the candidate does not intersect any obstacle body box (use `_sizeFor` body boxes, not footprints, and skip the author and the node itself). If every zero-overlap candidate crosses a body, return the first zero-overlap candidate. If there are no zero-overlap candidates, keep today's least-intersection fallback.
   - Implement `bool _segmentIntersectsRect(Offset a, Offset b, ConstellationBounds r)` with Liang–Barsky clipping.
6. **Diagnostics for tests.** Add `@visibleForTesting Set<(String, String)> constellationFootprintOverlaps(ConstellationPlacedLayoutInput input, ConstellationLayout layout)`. It returns sorted id pairs whose footprints (from `input.footprints`, falling back to body size) intersect, excluding pairs where **both** ids are pinned.

Tests (`constellation_layout_test.dart`, plus the R00 fixture through the cubit):

- **Drawn-only.** With the reference fixture at budget (1, 28), `layout.positions` contains no hidden `req-ego-*` ids, and `layoutInputFromComposition` gives the same satellite map as the cubit's scene algorithm.
- **No avoidable overlap.** With metrics from the fixture (hard-code a realistic metrics record in the test: `labelGap 2`, person `120×22`, Request `144×40`, chip `110×44`), `constellationFootprintOverlaps` is empty for the reference fixture, both collapsed and with `ego` expanded.
- **Author exemption removed.** For every automatic Request, its footprint rect does not intersect its author's footprint rect.
- **People unchanged (A3 guard).** Person positions are identical with `footprints: {}` and with footprints (`expect(mapA, mapB)` restricted to person ids).
- **Ego direction.**
  - Peers at angles {90°, 215°, 327°} (screen convention) → the direction is within 1° of 152.5°.
  - With no peers → `(0, 1)`.
  - The mean angle of the ego's satellites lies inside the largest gap.
- **Pins exact.** Two pins with identical anchors are both at exactly that point (D20), and `constellationFootprintOverlaps` does not report the pair.
- **Crossing preference.** Build a case where the ideal slot's attachment crosses a third body and another zero-overlap candidate does not; the chosen point is the one without the crossing.
- **Existing tests.** Run `constellation_p06_composition_layout_test.dart`, `constellation_scene_layout_test.dart`, `tentura_layout_algorithms_test.dart`, and the density tests. Where an expectation encoded hidden-Request slots, author overlap, or the downward ego fan, update it and record each changed expectation, with its reason, in the journal. Never loosen a pin or person assertion.

Done when all of the above pass and a screenshot of the reference fixture at 375×667 shows no overlaps between bodies, labels, and chips.

### R05: Edge legibility (UI-06)

Dependencies: R02.

Steps:

1. **Colour token.** Add `graphEdgePath` (Color) to `TenturaTokens`: light `TenturaPalette.textMuted` `#64748B` (4.55:1 on `bg`), dark `TenturaPalette.textMutedDark` `#94A3B8` (6.99:1 on `bgDark`). Edit all 5 token sites.
2. **Shared style function.** Create `features/constellation/ui/utils/constellation_edge_style.dart`:

   ```dart
   typedef ConstellationEdgeStyle = ({Color color, double width, double dash, double gap});
   // dash == 0 → solid
   ConstellationEdgeStyle constellationEdgeStyle(
     ConstellationEdgeKind kind, TenturaTokens tt, ColorScheme scheme,
   ) => switch (kind) {
     ConstellationEdgeKind.tier1Path  => (color: tt.graphEdgePath, width: 2.0, dash: 0, gap: 0),
     ConstellationEdgeKind.tier2Path  => (color: tt.graphEdgePath, width: 2.0, dash: 6, gap: 4),
     ConstellationEdgeKind.ringStub   => (color: tt.graphEdgePath, width: 1.5, dash: 2, gap: 4),
     ConstellationEdgeKind.attachment => (color: scheme.secondary,  width: 1.5, dash: 0, gap: 0),
   };
   ```

   Kinds differ by pattern and width, not only colour.
3. **Painter.** In `ConstellationEdgePainter`:
   - Implement `RepaintingEdgePainter` with `repaint: controller.cameraRevision` and a `double Function() cameraScale` field.
   - Take `tt` instead of hard-coded consts.
   - Screen-constant strokes when zoomed out: `final k = cameraScale() < 1 ? 1 / cameraScale() : 1.0;` then multiply `width`, `dash`, and `gap` by `k`.
   - Replace `_trimAttachmentLine` with `_trim(src, dst, srcRadius + 2, dstRadius + 2)` applied to **every** kind, dropping the `length * 0.15` gap.
   - Replace the suffix scan: `_rebuildGraph` builds `Map<String, ConstellationEdgeKind> edgeKindByPair` keyed `'$srcGraphId->$dstGraphId'`, with an `assert(!edgeKindByPair.containsKey(key))` before insert (parallel kinds between one pair do not occur today). The painter looks kinds up in O(1). Keep `edgeKinds` (id → kind) for `edgeIdOf`.
4. **Legend.** In `graph_legend_content.dart`, build the Constellation rows from `constellationEdgeStyle` (colour, width, and dash pattern: the swatch painter takes `dash`/`gap`). The `features/graph` → `features/constellation` import already exists in this file.

Tests:

- `constellation_edge_style_test.dart`:
  - For both `TenturaTheme.light()` and `dark()`, every kind's `color` has contrast ≥ 3.0 against `tt.bg`. Write a `contrastRatio(Color a, Color b)` helper with `computeLuminance()`, compositing alpha over `bg` first.
  - Tier-1 and tier-2 have different `dash`; the stub differs from both in `(dash, gap)`.
- Painter unit test: record into a `PictureRecorder` with a fake `cameraScale` of 0.5 and check that stroke width `2.0 * 2` is used. Assert through a small `@visibleForTesting static double effectiveWidth(double width, double scale)`.
- Legend widget test: the tier-1 row's swatch colour equals `constellationEdgeStyle(tier1Path, ...).color`.

Done when these pass and you have looked at light and dark screenshots of the reference fixture: tier-1 paths are clearly visible, and the four kinds are distinguishable in greyscale.

### R06: Targeting and semantics (UI-07, double dispatch)

Dependencies: R02, R03.

Steps:

1. Pass `nodeTapHitTester: (scene, ordered) => ...` (the §3.4 closure) to `GraphView` in `_buildGraphStack`.
2. **Remove the double dispatch.** In the Constellation `nodeBuilder`, construct `GraphNodeWidget(onTap: null, ...)` for both kinds. Wrap the result:

   ```dart
   Semantics(
     button: true,
     selected: isSelected,
     label: constellationNodeSemanticLabel(...),
     onTap: () => _onNodeTap(context, cubit, node),
     child: MouseRegion(
       cursor: SystemMouseCursors.click,
       child: ExcludeSemantics(child: _ConstellationMapNode(...)),
     ),
   )
   ```

   Pointer taps now arrive only through `GraphView.onNodeTap`; screen readers use `Semantics.onTap`. Keep `TestIds.key(TestIds.graphNode(node.id))` on the `GraphNodeWidget`.
3. **Semantic label** (new function in `constellation_request_label.dart` or a new `constellation_node_semantics.dart`):
   - person: `displayLabel`, plus `l10n.constellationPinMarkerSemantics` when pinned;
   - Request: `'${l10n.beaconViewTitle}: $title'` plus `constellationRequestMarkerSemantics(...)` (status + pin), joined with ", ".
   - The ego gets the same person label (it is not tappable, so no `onTap`).
   - Label plates are already `ExcludeSemantics` (R03), so each node has exactly one semantics node.
4. Leave `mapNodeAtSceneCentre` as a body-only test seam. Add a doc comment saying production taps resolve through `nodeTapHitTester`.
5. Placement gating: no code change. Add regression assertions (below).

Tests (`constellation_anchor_interaction_test.dart` / `constellation_body_test.dart`):

- **Single dispatch.** With a counting `GraphPersonContextCubit` fake, one tap on `fieldPerson:am` calls `selectProfile` exactly once.
- **Expanded target.** A tap 21 px right of a Request's centre (outside the 18 px radius, inside the 48 px target) at camera scale 1.0 selects that Request.
- **Label tap.** A tap on the centre of `constellation.label.fieldRequest:req-sm-1` opens that Request's preview (find the preview sheet).
- **Pan from a label.** A 60 px drag starting on a label moves the camera (the transform changed) and does not start a node drag (`placementPhase` stays `idle`).
- **Overlapping pins.** With two anchors at the same coordinates and different placement times, a tap selects the later one. After dragging that one away, a tap selects the other (D21/D22).
- **Semantics.** `find.bySemanticsLabel(RegExp('I need documents'))` finds exactly one node, and its label contains the Open status label.
- **Gating.** During `draggingExisting`, `controller.isCameraGated` is true; after `cancelPlacement()` it is false.

Done when these pass and `flutter test test/features/constellation test/features/graph` is green.

### R07: Camera recovery and app-bar clarity (UI-08)

Dependencies: R02, R03 (R04 improves the fit bounds).

Steps:

1. **ARB.**
   - Add `constellationFitAll` (en "Show whole field", ru "Показать всё поле").
   - Reuse the existing `graphCenterView` (en "Center view", ru "Центрировать"). It already means "centre on me at normal scale" in the People graph.
   - Add `TestIds.constellationFitAll = 'constellation.camera.fit_all'` and `TestIds.constellationCenterOnMe = 'constellation.camera.center_on_me'`.
   - Run `flutter gen-l10n`.
2. **Cubit.**
   - `void fitWholeField({required EdgeInsets insets})`:
     - return early if `!graphController.canLayout` or `state.placementPhase != ConstellationPlacementPhase.idle`;
     - bounds = the union over all scene nodes of the scene footprint rect (`_layoutFootprints[node.id]` around the node position, falling back to the body rect);
     - `graphController.fitToRect(bounds, padding: kMinInteractiveDimension, viewportInsets: insets, maxScale: 1.0)`.
   - `void centerOnEgo({required EdgeInsets insets})`: under the same guards, `graphController.jumpToPosition(egoCentre, resetScale: true, viewportInsets: insets)`.
   - Neither method changes filters, expansion, selection, or pins.
3. **Widget.** Add `ui/widget/constellation_camera_controls.dart`: a `Column` of two `IconButton.filledTonal` buttons. Use `Icons.fit_screen` with tooltip `constellationFitAll`, and `Icons.my_location` with tooltip `graphCenterView`. Set `constraints: BoxConstraints.tightFor(width: tt.buttonHeight, height: tt.buttonHeight)` and give the buttons `SizedBox(height: tt.tightGap * 2)` spacing. The keys are the TestIds above. `onPressed` is null while `placementPhase != idle`.
4. **Placement and insets** in `_buildGraphStack`:
   - The toolbar is `Positioned(top: tt.rowGap, right: tt.screenHPadding + (panelVisible && !compact ? tt.graphPersonContextWidth + tt.screenHPadding : 0), child: SafeArea(left: false, bottom: false, child: ConstellationCameraControls(...)))`.
   - Insets passed to the cubit: `EdgeInsets.only(right: tt.buttonHeight + 2 * tt.screenHPadding + (panelVisible && !compact ? tt.graphPersonContextWidth + tt.screenHPadding : 0), bottom: panelVisible && compact ? MediaQuery.sizeOf(context).height * tt.graphPersonContextCompactMaxHeightFraction : 0)`.
5. **App bar** (`constellation_app_bar.dart`):
   - Legend button icon: `Icons.legend_toggle` for both states. Check that the constant exists in the pinned Flutter SDK; if not, use `Icons.info_outline`. It must no longer read as "Map".
   - Replace `Expanded(title)` + `Flexible(toggle)` with a `LayoutBuilder` over the row. Measure the title width with a `TextPainter` using the `titleLarge` style **and** `MediaQuery.textScalerOf(context)`. Give the toggle `maxWidth = available − titleWidth − 2 * tt.buttonHeight − tt.rowGap`. Keep the title in a `Flexible` with ellipsis so it can still shrink at 200% text.
   - `_labelsFit`: pass `textScaler: MediaQuery.textScalerOf(context)` and `textDirection: Directionality.of(context)` to the `TextPainter`. Choose segment content in priority order: icon + label if it fits; else **label only** (text-only segments, `icon: null`) if it fits; else icon only with tooltip.
6. **Compact Field nav label**: blocked on §6.1. Default: no change to `home_screen.dart` / `home_bottom_navigation_bar.dart`.
7. **No automatic fit on open**: keep the controller's initial `jumpToCenter`. Refresh, filter change, expansion, and Map/Text switches must not move the camera. Existing behaviour; add a regression test.

Tests:

- `constellation_camera_controls_test.dart` (reference fixture, 375×547):
  - After `zoomBy(0.3)` and a 300 px pan, tap Show whole field. Every scene node's footprint, converted to the viewport, lies inside the usable region (viewport minus insets, ±1 px), and `cameraScale <= 1.0`.
  - Tap Center: the ego is at the usable centre (±0.5 px) and `cameraScale == 1.0`.
  - Both buttons are disabled during `beginDragExisting`.
  - A single-node field (ego only) gives a finite transform and scale `== 1.0` after Show whole field.
- `constellation_app_bar_test.dart`: at width 375 and text scales 1.0 and 1.3 (ru and en), `find.text('Карта')` / `find.text('Map')` finds one widget (labels visible) and `tester.takeException()` is null. At 2.0 there is no overflow exception, and each segment keeps a tooltip.
- **Camera stability.** Record the transform, then: `toggleSatelliteOverflow('ego')`, `setFilterLocation(...)`, `setViewMode(text)` then `map`, and `load()`. Afterwards the transform is unchanged.

Done when the tests pass and the journal holds 375×667 screenshots before and after using both controls.

### R08: Integrate, verify, release

Dependencies: R00–R07.

1. Run §5.3 serially and fix regressions, including in the People / forward / genealogy graphs.
2. Record before/after screenshots of the same fixture and camera intent, plus the measured values: overlaps, contrast ratios, tap-target sizes, and the frame cost profile. View every changed golden before accepting it.
3. Update `docs/features/constellation.md`:
   - Density: the budget uses the text-scale ratio and applies to every composition.
   - Overflow: chips can collapse.
   - Labels are screen-space plates.
   - Camera controls.
   - Pins may overlap (the no-overlap guarantee is for automatic layout only).

   Keep D20–D23 unchanged. Add a "Follow-ups" line for general edge rerouting (§0.3.1).
4. Journal: separate statuses for focused tests, full suites, browser proof, accessibility checks, and release artifacts. Never mark an unavailable check as passed.
5. Version: read `packages/client/pubspec.yaml` at implementation time. Follow the repository's recent convention (patch bumps for client fixes, e.g. `7.6.15 → 7.6.16`), and sync `packages/client/web/index.html` `flutter_bootstrap.js?v=` in the same commit. If R01 ships first, it gets its own bump.
6. No server minimum-version change; there is no protocol change.
7. Prepare a focused diff. No push or deploy is part of this plan.

---

## 5. Verification and acceptance

### 5.1 Fixture matrix (pairwise, not Cartesian)

| Dimension | Cases |
|---|---|
| Viewport | 320×568, 375×667 (reference), 390×844, landscape 667×375, 600 / 840 breakpoint edges, 1280×800 |
| Text / locale | 1.0, 1.3, 2.0; a non-linear scaler (unit test); ru and en |
| Theme / content | light and dark; long names and titles, blank title, no avatar, mixed scripts; every lifecycle status; pinned and unpinned |
| Graph shape | empty, ego-only, reference, high-degree author (8 Requests, expanded), dense multi-author (use `constellation_p06_composition_layout_test.dart` fixtures), residual ring peers |
| Placement | no pins; a nearby pin; overlapping pins with tied timestamps; provisional new pin; drag, cancel, save; a dormant pin restored after clearing filters |
| Camera / lifecycle | initial open; min and max scale; pinch oscillating around 0.7–0.85 (no label flicker); pan offscreen; resize; preview open and close; refresh / tab reselect; Map/Text switch |
| Input | mouse, touch emulation, real touch when available, keyboard (chips, camera buttons, Text view), screen reader |

Run the reference fixture in both themes at all three text scales.

### 5.2 Measurable gates

1. **Geometry.** For feasible automatic layouts, `constellationFootprintOverlaps` is empty. At camera scale 1.0, no placed label rect intersects another label, a body, or a chip (≤ 1 px tolerance). Pin collisions are asserted separately and allowed. No pin or status badge extends below its node body, and no badge intersects any placed label (UI-14).
2. **Overflow.** Chip count text equals the hidden count. The collapse chip exists while expanded. Expand/collapse never moves pins or the camera. Counts of other authors are unchanged by one author's toggle.
3. **Readability.** Rendered label text is 13 px × text scale at every camera scale. Chip text is 15 px. Nav labels keep the 12.5 exception. Full titles remain reachable (preview / Text view).
4. **Edges.** Every kind has ≥ 3:1 contrast against `bg` in both themes. Kinds are distinguishable without colour. The legend matches the painter.
5. **Interaction.** Tap targets are ≥ 48×48 viewport px at every tested scale. One tap dispatches once. Label taps and expanded targets resolve as §3.4. D21/D22 topmost pin order holds.
6. **Stability.** Person positions are unchanged by R04 (A3 guard). Camera gestures never issue anchor writes (`writeCount` unchanged). Unchanged inputs produce identical layout and frame.
7. **Parity.** Map/Text eligible Request ids, filters, and pins are unchanged by R01–R07. Authorisation, preflight, and anchor lifecycle tests stay green.
8. **Compatibility.** The People graph and other `GraphView` users run unchanged with the new seams unset. The package's full suite is green.
9. **Performance.** Profile the dense fixture in profile mode before and after on a recorded device/build. The overlay's frame computation should be ≤ 2 ms p95 while panning. Investigate any raster-time regression above 10%. Report measured numbers, not FPS claims.

### 5.3 Commands (run serially)

```bash
# repository root
git diff --check
bash scripts/check-user-facing-terminology.sh

# packages/force_directed_graphview
flutter test test/controller_test.dart test/node_drag_gesture_test.dart test/scene_rendering_test.dart test/scene_layout_protocol_test.dart test/scene_controller_layout_lifecycle_test.dart
flutter test
dart analyze --format machine

# packages/client
flutter gen-l10n                       # only if ARB files changed
flutter test test/features/constellation test/architecture/constellation_domain_graph_boundary_test.dart
flutter test test/features/graph test/features/home/constellation_nav_test.dart test/design_system

# repository root: package-root custom lints (flutter analyze does NOT prove lint cleanliness)
./scripts/check-custom-lints.sh packages/client

# packages/client: final full suite
flutter test

# repository root: browser journeys (the path is relative to packages/client)
./scripts/run_client_integration_web_local.sh integration_test/constellation_readability_test.dart
./scripts/run_client_integration_web_local.sh integration_test/constellation_pinning_test.dart
```

- Golden tests (optional, recommended for the reference layout, expanded chip, overview, and overlapping pins): follow `test/design_system/tentura_section_header_golden_test.dart`. Run `flutter test --update-goldens <exact file>` only for an intentional change, and open every changed PNG.
- If lint rules change (not planned), run `dart test` in `packages/tentura_lints`.
- Before a browser run, check whether port 8888 is already served (see `scripts/run_client_integration_web_local.sh`) instead of starting a second dev server.

### 5.4 Browser journeys (`integration_test/constellation_readability_test.dart`)

Use the existing TestIds plus the new ones (`constellation.label.<graphId>`, `constellation.overflow.<authorId>`, `constellation.camera.*`). At each checkpoint record the viewport, camera scale, and a screenshot.

1. Open the Field at 375×667. Tap the ego's chip and one Request's **label** (not its body); the preview opens.
2. Expand the crowded author's chip, open a newly shown Request, go back, and collapse with the same chip. The camera transform is unchanged.
3. Zoom out to about 0.5. The labels still read at 13 px; Request labels drop out in overview; tapping a Request still opens its full title.
4. Pan away, press Show whole field, then Center. Repeat with the person panel open and at text scale 1.3.
5. Pin a person and a Request. The pin glyph appears at the top-end corner of each node and never covers its name or title, at text scale 1.0 and 1.3. Then place two pins on top of each other; the last placed is hit first. Drag it away and select the one underneath. No chooser, no hidden pin.
6. Switch Map → Text → Map, apply a filter, reselect the Field tab. Request-set parity holds; chip counts are unchanged by the reselect.
7. Keyboard: Tab reaches the chips and camera buttons; Enter activates them; the Text view completes selection. Record a screen-reader check separately from emulation.

---

## 6. Risks, decisions, and completion record

### 6.1 Open decisions for the owner

1. **Compact Field tab label (UI-08 part).** The label was hidden on purpose on 2026-09-09 (`9f2bdcde6` "Hide the compact bottom-nav label", `35c711cfa` command disk). Showing "Моё поле" under a 54 px disk does not fit the 64 px bar without shrinking the disk or dropping the command chrome. **Default: no change.** If the owner wants the label, add a unit that renders the disk at `tt.buttonHeight` with the standard label slot and updates `constellation_nav_test.dart`.
2. **Owner note, not blocking.** With R01, phones show **1 Request per author** by the documented formula, where the buggy first load showed 3. To show more, change `_kReferenceViewportWidth/Height` in `constellation_density.dart` as a separate, explicit product change.

### 6.2 Risks

| Risk | Response |
|---|---|
| Screen-space overlay drifts from the scene during transitions | The overlay listens to the same controller notifications as `GraphLayoutView`, plus `cameraRevision`. The tap tester rejects stale frames (snapshot identity + camera revision). R03/R06 tests cover pan and expand. |
| Tap tester steals pans or drags | Tap-only pending state cancels on `kTouchSlop`, and drags start only from painted bodies (R02 tests). |
| Footprints push Requests far from their authors | The satellite radius is derived from the footprint. Candidates keep the fan order first, and the attachment preference keeps lines short. Tests assert no overlap on the reference and dense fixtures. |
| People move (A3 regression) | People keep body-only placement. A bit-for-bit person-position test guards it. |
| Shared package change breaks other graphs | All seams are opt-in with unchanged defaults; the full package suite and client graph tests run. |
| Label flicker near the detail threshold | Hysteresis between 0.70 and 0.85. The matrix includes a pinch-oscillation case. |
| Lint or terminology failures from new copy | Use tokens only; run `check-custom-lints.sh` and the terminology script in every unit that touches UI or ARB. |

### 6.3 Completion record

Completion requires a journal entry for every unit R00–R08 and a final table marking each of UI-01 to UI-14 as **passed**, **failed**, or **blocked**, with a test or artifact reference. Passing a source review or focused suite alone does not establish browser or release acceptance.
