# Graph navigation rework — step-by-step implementation guide (issue #86)

**Audience:** an implementing agent that follows instructions literally and does not
improvise. Every task below states the exact files, the exact edits, and the exact
command that proves the task is done.

**Companion document:** [`graph-navigation-rework-plan.md`](graph-navigation-rework-plan.md)
— the analysis and rationale. Read it once for context; this file is the executable part.

**Scope:** Phases 1–5 of "Plan 2" from the analysis. Arrowheads for the trust graph
(§4-bis.5 of the analysis) are **already done** — do not redo them.

---

## 0. Ground rules — read before touching anything

### 0.1 Repository layout

| Path | What it is |
|---|---|
| `packages/client` | Flutter app, Dart package name `tentura` |
| `packages/server` | Dart server + SQL migrations |
| `packages/force_directed_graphview` | **our fork** of the graph library, wired in via `pubspec_overrides.yaml` |
| `packages/tentura_lints` | custom analyzer plugin |
| `hasura/metadata.json` | Hasura metadata (tracked tables, functions, permissions) |

All `cd` paths below are relative to the repository root
`/home/vader/MY_SRC/tentura` unless stated otherwise.

### 0.2 Hard rules

1. **Never edit generated files.** These are generated: `*.g.dart`, `*.freezed.dart`,
   `*.gr.dart`, `*.config.dart`, `*.schema.dart`, `*.ast.gql.dart`, `*.req.gql.dart`,
   `*.data.gql.dart`, and everything in `packages/client/lib/ui/l10n/`
   (`l10n.dart`, `l10n_en.dart`, `l10n_ru.dart`). Edit the **source** and re-run codegen:
   - localization: edit `packages/client/l10n/app_en.arb` **and** `app_ru.arb`, then
     `cd packages/client && flutter gen-l10n`
   - GraphQL / freezed / injectable: edit the `.graphql` / annotated Dart source, then
     `cd packages/client && dart run build_runner build --delete-conflicting-outputs`
2. **Dependency direction is inward.** `ui/` → `data/` → `domain/` → nothing.
   `domain/` must not import from `data/` or `ui/`. This is lint-enforced.
3. **Client UI uses the design system.** No raw `Color`, `Colors.*`, `TextStyle(...)`,
   inline `fontSize:`, `EdgeInsets.all(8)`, or `BorderRadius.circular(12)` inside
   `packages/client/lib/features/**` or `packages/client/lib/ui/**`. Use
   `context.tt` tokens and `TenturaText.*`. Import the barrel:
   `import 'package:tentura/design_system/tentura_design_system.dart';`
   Layout math inside a `CustomPainter` (geometry, not styling) is exempt — painters
   already use raw doubles.
4. **User-visible changes require a version bump** in `packages/client/pubspec.yaml`
   (`version:` line). Bump the patch number once per phase, not once per task.
   Do **not** touch `kDefaultMinClientVersion` in `packages/server/lib/env.dart` —
   nothing here breaks old clients.
5. **Terminology.** Users see **Request** and **Chat**; code paths stay `beacon_*`.
   Never introduce a `Request` domain entity.
6. **Do not reformat files you are not changing.** Keep diffs minimal.

### 0.3 The verification commands

Learn these four; they are referenced by name throughout.

```bash
# V1 — analyzer, client
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos

# V2 — client tests
cd packages/client && flutter test

# V3 — custom lint gate (MUST be this script; `flutter analyze` does NOT load the plugin)
./scripts/check-custom-lints.sh packages/client

# V4 — library fork tests
cd packages/force_directed_graphview && flutter test
```

Current known-good state before you start: **V2 = 1497 passed, 14 skipped**;
**V3 = 112 issues, baseline 113**. If V3 reports a number **above** 113, you introduced
a violation — fix it, do not raise the baseline.

### 0.4 How the "fork" works — read this before Phase 1

**The fork is vendored source inside this repository. There is no second repository, no
submodule, and nothing to clone, push, or publish.**

Verified facts:

- there is **no** `.gitmodules` file;
- there is **no** nested `.git` directory in `packages/force_directed_graphview/`;
- `git ls-files packages/force_directed_graphview` lists **32 ordinary tracked files**;
- `pubspec_overrides.yaml` **is tracked by git**, and it points the dependency at the
  local path:

```yaml
dependency_overrides:
  # Vendored 0.6.2 + render guards: skip nodes/edges whose layout position
  # hasn't been produced yet by the async relayout (see package README).
  force_directed_graphview:
    path: packages/force_directed_graphview
```

Consequences for you, the implementing agent:

1. **Edit the files directly**, exactly like any other file in the repo. Use the normal
   Read/Edit tools on `packages/force_directed_graphview/lib/src/controller.dart` and
   friends. Do not `git clone` anything.
2. **Commit fork changes in the same branch and the same commit** as the rest of the work.
   They are not a separate deliverable.
3. `packages/client/pubspec.yaml` still declares `force_directed_graphview: ^0.6.2`, but
   that line is **never used to fetch anything** — the override wins, for every developer
   and for CI, because the override file is committed. The pub.dev package is irrelevant.
   Bumping the fork's version to `0.6.2+tentura.1` (Task 1.7) stays compatible with the
   `^0.6.2` constraint, since semver ignores `+build` metadata when comparing.
4. The fork is **not** a member of the pub workspace (the root `pubspec.yaml` lists only
   `packages/client`, `packages/server`, `packages/tentura_lints`). It has its own
   `pubspec.yaml` and `pubspec.lock`, so it is tested on its own — this is why `V4` is a
   separate command with its own `cd`. It is already resolved; if `flutter test` ever
   complains about missing packages, run `flutter pub get` in that directory first.
5. Upstream `cupofme/force_directed_graphview` is at 0.6.2 and effectively unmaintained,
   and the vendored copy already carries three local commits. **Do not** attempt to open a
   PR upstream, rebase onto upstream, or re-vendor a fresh copy.

### 0.5 Definition of "done" for every task

A task is done when: the stated edit is made, **V1 shows no new issue in the files you
touched**, and the task's own `Verify` command passes. Never mark a task done because
"it should work".

---

## Phase 1 — Fork patches

**Goal:** make the library able to (a) accept a new layout algorithm at runtime,
(b) animate between two computed layouts instead of rendering every solver iteration,
(c) fit a set of nodes into the viewport, (d) reset cleanly.

All work in this phase is inside `packages/force_directed_graphview/`.
**No client file changes in Phase 1.** The client keeps working unchanged because every
new parameter has a default that preserves today's behaviour.

### Task 1.1 — Make layout algorithms comparable by value

**Why:** Task 1.2 rebuilds the layout when `layoutAlgorithm != oldWidget.layoutAlgorithm`.
Without `==`, every `build()` produces a "different" algorithm and triggers an endless
relayout loop.

**File:** `packages/force_directed_graphview/lib/src/layout_algorithm/fruchterman_reingold_algorithm.dart`

**Do:** add `==` and `hashCode` to `FruchtermanReingoldAlgorithm`, immediately before
the closing brace of the class (after `defaultInitialPositionExtractor`).

```dart
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FruchtermanReingoldAlgorithm &&
          runtimeType == other.runtimeType &&
          iterations == other.iterations &&
          relayoutIterationsMultiplier == other.relayoutIterationsMultiplier &&
          showIterations == other.showIterations &&
          initialPositionExtractor == other.initialPositionExtractor &&
          temperature == other.temperature &&
          optimalDistance == other.optimalDistance;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        iterations,
        relayoutIterationsMultiplier,
        showIterations,
        initialPositionExtractor,
        temperature,
        optimalDistance,
      );
```

**Verify:**

```bash
cd packages/force_directed_graphview && flutter test
```

**Done when:** V4 passes.

---

### Task 1.2 — React to configuration changes (`didUpdateWidget`)

**Why:** `_applyConfiguration` is called only from `initState`, so the algorithm chosen
at first build is the only algorithm the graph will ever use.

**File:** `packages/force_directed_graphview/lib/src/graph_view.dart`

**Do:** in `_GraphViewState`, add `didUpdateWidget` directly after `_initController()`:

```dart
  @override
  void didUpdateWidget(covariant GraphView<N, E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller ||
        widget.layoutAlgorithm != oldWidget.layoutAlgorithm ||
        widget.canvasSize != oldWidget.canvasSize ||
        widget.lazyBuilding != oldWidget.lazyBuilding) {
      _initController();
    }
  }
```

**Verify:**

```bash
cd packages/force_directed_graphview && flutter test
```

**Done when:** V4 passes.

---

### Task 1.3 — Add `GraphLayout.lerp`

**Why:** the interpolation primitive used by Task 1.4.

**File:** `packages/force_directed_graphview/lib/src/model/graph_layout.dart`

**Do:** add this static method inside `class GraphLayout`, after `hasPosition`:

```dart
  /// Interpolates between two layouts.
  ///
  /// The key set of the result is the key set of [b] — nodes that exist only in
  /// [a] have been removed from the graph and must not be rendered. A node that
  /// exists only in [b] starts from [spawn] (when provided) so that a freshly
  /// expanded node visually travels out of the node it was expanded from,
  /// instead of appearing at its final position.
  static GraphLayout lerp(
    GraphLayout a,
    GraphLayout b,
    double t, {
    Offset? Function(NodeBase node)? spawn,
  }) {
    final positions = <NodeBase, Offset>{};
    for (final entry in b._nodePositions.entries) {
      final from =
          a._nodePositions[entry.key] ?? spawn?.call(entry.key) ?? entry.value;
      positions[entry.key] = Offset.lerp(from, entry.value, t)!;
    }
    return GraphLayout._(Map.unmodifiable(positions));
  }
```

**Verify:** create `packages/force_directed_graphview/test/graph_layout_lerp_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

void main() {
  final a = Node<String>(data: 'a', size: 10);
  final b = Node<String>(data: 'b', size: 10);

  GraphLayout build(Map<NodeBase, Offset> positions) {
    final builder = GraphLayoutBuilder(nodes: positions.keys.toSet());
    positions.forEach(builder.setNodePosition);
    return builder.build();
  }

  test('lerp moves shared nodes and keeps the target key set', () {
    final from = build({a: Offset.zero, b: const Offset(100, 0)});
    final to = build({a: const Offset(100, 100)});

    final mid = GraphLayout.lerp(from, to, 0.5);

    expect(mid.getPosition(a), const Offset(50, 50));
    expect(mid.hasPosition(b), isFalse);
  });

  test('a node missing from the source starts at the spawn position', () {
    final from = build({a: Offset.zero});
    final to = build({a: Offset.zero, b: const Offset(100, 0)});

    final mid = GraphLayout.lerp(from, to, 0.5, spawn: (_) => Offset.zero);

    expect(mid.getPosition(b), const Offset(50, 0));
  });
}
```

```bash
cd packages/force_directed_graphview && flutter test
```

**Done when:** both new tests pass and V4 is green.

---

### Task 1.4 — Animated layout transitions in the controller

**Why:** this is the core of the whole rework — "compute the layout first, then move to
it in one controlled transition".

**File:** `packages/force_directed_graphview/lib/src/controller.dart`

This is the largest patch in Phase 1. Apply the five edits below **in order**.

**1.4.a — imports.** `controller.dart` is `part of 'graph_view.dart'`, so add the import
to **`graph_view.dart`** instead (it already imports `flutter/material.dart`, which
re-exports `Ticker` via `scheduler`; add the explicit import to be safe):

```dart
import 'package:flutter/scheduler.dart';
```

**1.4.b — new fields.** In `class GraphController`, after `var _relayoutGeneration = 0;`:

```dart
  Ticker? _ticker;
  GraphLayout? _transitionFrom;
  GraphLayout? _transitionTarget;
  Duration _transitionDuration = Duration.zero;
  Curve _transitionCurve = Curves.easeOutCubic;
  double _minScale = 0.5;
  double _maxScale = 2;

  /// Resolves where a node that is new to the layout should start its transition.
  /// Set by the owner (e.g. "the node the user just expanded"). When the field
  /// is null, or the callback returns null, the new node appears directly at
  /// its final position.
  Offset? Function(NodeBase node)? spawnPositionResolver;
```

**1.4.c — publish through the transition.** Add these three methods after `_relayout()`:

```dart
  /// Single funnel through which every new layout reaches the renderer.
  void _publishLayout(GraphLayout next) {
    if (_transitionDuration == Duration.zero ||
        _layout == null ||
        _ticker == null) {
      _layout = next;
      notifyListeners();
      return;
    }

    _transitionFrom = _layout;
    _transitionTarget = next;
    _ticker!
      ..stop()
      ..start();
    notifyListeners();
  }

  void _onTransitionTick(Duration elapsed) {
    final from = _transitionFrom;
    final target = _transitionTarget;
    if (from == null || target == null) {
      _ticker?.stop();
      return;
    }

    final total = _transitionDuration.inMicroseconds;
    final t = total <= 0
        ? 1.0
        : (elapsed.inMicroseconds / total).clamp(0.0, 1.0).toDouble();

    _layout = GraphLayout.lerp(
      from,
      target,
      _transitionCurve.transform(t),
      spawn: spawnPositionResolver,
    );

    if (t >= 1.0) {
      _layout = target;
      _transitionFrom = null;
      _transitionTarget = null;
      _ticker?.stop();
    }
    notifyListeners();
  }

  void _detachTicker() {
    _ticker?.dispose();
    _ticker = null;
    final target = _transitionTarget;
    if (target != null) {
      _layout = target;
    }
    _transitionFrom = null;
    _transitionTarget = null;
  }
```

**1.4.d — route existing assignments through the funnel.** There are exactly **two**
places that assign `_layout` from a stream. Replace both.

In `_relayout()`, replace:

```dart
      _layout = layout;
      notifyListeners();
```

with:

```dart
      _publishLayout(layout);
```

In `_applyConfiguration()`, replace:

```dart
      _layout = layout;

      if (!_centered) {
        jumpToCenter();
        _centered = true;
      }
      notifyListeners();
```

with:

```dart
      _publishLayout(layout);

      if (!_centered) {
        jumpToCenter();
        _centered = true;
      }
```

**1.4.e — accept the ticker and the scale bounds.** Change the signature and body of
`_applyConfiguration` — add four parameters and set up the ticker **before** the
existing body runs:

```dart
  Future<void> _applyConfiguration({
    required GraphLayoutAlgorithm algorithm,
    required GraphCanvasSize size,
    required LazyBuilding lazyBuilding,
    required TransformationController transformationController,
    required TickerProvider vsync,
    required Duration transitionDuration,
    required Curve transitionCurve,
    required double minScale,
    required double maxScale,
  }) async {
    _transitionDuration = transitionDuration;
    _transitionCurve = transitionCurve;
    _minScale = minScale;
    _maxScale = maxScale;
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTransitionTick);

    _lazyBuilding = lazyBuilding;
    // ... rest of the existing body unchanged ...
```

**1.4.f — dispose.** `GraphController` does not override `dispose` today (it inherits it
from the `ChangeNotifier` mixin), and `GraphCubit.close()` already calls it. Add the
override to `GraphController`, right before `bool _hasNode(...)`:

```dart
  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
```

**1.4.g — wire the widget.** In `packages/force_directed_graphview/lib/src/graph_view.dart`:

- add three parameters to `GraphView`:

```dart
    this.layoutTransitionDuration = Duration.zero,
    this.layoutTransitionCurve = Curves.easeOutCubic,
```

with fields:

```dart
  /// How long the graph takes to move from the previous layout to a newly
  /// computed one. [Duration.zero] (the default) applies layouts instantly,
  /// which reproduces the pre-transition behaviour.
  ///
  /// Only meaningful together with a layout algorithm that emits its **final**
  /// layout once (e.g. `FruchtermanReingoldAlgorithm(showIterations: false)`).
  /// An algorithm that streams intermediate iterations restarts the transition
  /// on every emission and will look wrong.
  final Duration layoutTransitionDuration;

  /// Easing used for [layoutTransitionDuration].
  final Curve layoutTransitionCurve;
```

- make the state a ticker provider:

```dart
class _GraphViewState<N extends NodeBase, E extends EdgeBase<N>>
    extends State<GraphView<N, E>> with SingleTickerProviderStateMixin {
```

- pass everything through `_initController`:

```dart
  void _initController() {
    widget.controller._applyConfiguration(
      algorithm: widget.layoutAlgorithm,
      size: widget.canvasSize,
      lazyBuilding: widget.lazyBuilding,
      transformationController: _transformationController,
      vsync: this,
      transitionDuration: widget.layoutTransitionDuration,
      transitionCurve: widget.layoutTransitionCurve,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
    );
  }
```

- release the ticker when the widget goes away (the controller is owned by the cubit and
  usually outlives the widget). `_GraphViewState` has no `dispose` today, so this is a new
  method — it also fixes an existing leak of `_transformationController`:

```dart
  @override
  void dispose() {
    widget.controller._detachTicker();
    _transformationController.dispose();
    super.dispose();
  }
```

- add `layoutTransitionDuration` / `layoutTransitionCurve` to `didUpdateWidget`'s
  condition from Task 1.2.

**Verify:** add `packages/force_directed_graphview/test/layout_transition_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

void main() {
  testWidgets('graph interpolates towards a newly computed layout',
      (tester) async {
    final controller = GraphController<Node<String>, Edge<Node<String>, void>>();
    const a = Node<String>(data: 'a', size: 10);
    const b = Node<String>(data: 'b', size: 10);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<String>, Edge<Node<String>, void>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const FruchtermanReingoldAlgorithm(iterations: 1),
          layoutTransitionDuration: const Duration(milliseconds: 300),
          nodeBuilder: (_, _) => const SizedBox.shrink(),
        ),
      ),
    );

    controller.mutate((m) => m..addNode(a));
    await tester.pumpAndSettle();
    final first = controller.layout.getPosition(a);

    controller.mutate((m) => m..addNode(b));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Mid-transition the graph must be laid out and must not have snapped.
    expect(controller.canLayout, isTrue);
    expect(controller.layout.hasPosition(a), isTrue);

    await tester.pumpAndSettle();
    expect(controller.layout.hasPosition(b), isTrue);
    expect(first, isNotNull);

    controller.dispose();
  });
}
```

```bash
cd packages/force_directed_graphview && flutter test
```

**Done when:** V4 passes, including `controller_test.dart` which must be unaffected
(its `GraphView`s use the default `Duration.zero`).

---

### Task 1.5 — `fitToRect` / `fitToNodes`

**Why:** required by the "Fit current path" action; the library has no fit API at all.

**File:** `packages/force_directed_graphview/lib/src/controller.dart`

**Do:** add both methods after `zoomBy`:

```dart
  /// Fits [rect] (in canvas coordinates) into the viewport.
  void fitToRect(Rect rect, {double padding = 48}) {
    final transformation = _transformationController;
    final viewport = _actualViewport;
    if (transformation == null || viewport == null) {
      return;
    }

    final padded = rect.inflate(padding);
    if (padded.width <= 0 || padded.height <= 0) {
      return;
    }

    // `_actualViewport` is in canvas coordinates; multiplying by the current
    // scale converts it back to on-screen pixels.
    final currentScale = transformation.value.getMaxScaleOnAxis();
    final viewportWidth = viewport.width * currentScale;
    final viewportHeight = viewport.height * currentScale;

    final scale = math
        .min(viewportWidth / padded.width, viewportHeight / padded.height)
        .clamp(_minScale, _maxScale)
        .toDouble();

    final center = padded.center;
    transformation.value = Matrix4.identity()
      ..translate(viewportWidth / 2, viewportHeight / 2)
      ..scale(scale)
      ..translate(-center.dx, -center.dy);
  }

  /// Fits every node of [nodes] that has a position into the viewport.
  /// Nodes without a position (not laid out yet) are ignored.
  void fitToNodes(Iterable<NodeBase> nodes, {double padding = 48}) {
    final layout = _layout;
    if (layout == null) {
      return;
    }

    Rect? bounds;
    for (final node in nodes) {
      final position = layout.getPositionOrNull(node);
      if (position == null) {
        continue;
      }
      final nodeRect = Rect.fromCenter(
        center: position,
        width: node.size,
        height: node.size,
      );
      bounds = bounds == null ? nodeRect : bounds.expandToInclude(nodeRect);
    }

    if (bounds == null) {
      return;
    }
    fitToRect(bounds, padding: padding);
  }
```

`math.min` needs an import in **`graph_view.dart`**:

```dart
import 'dart:math' as math;
```

**Verify:** add to `packages/force_directed_graphview/test/controller_test.dart` a test
that after `fitToNodes` on two far-apart nodes, both node positions map inside the
viewport under the new matrix. If writing that assertion proves awkward, the minimum
acceptable test is: `fitToNodes` on a laid-out graph changes
`transformationController.value` and does not throw, and `fitToNodes([])` is a no-op.

```bash
cd packages/force_directed_graphview && flutter test
```

**Done when:** V4 passes.

---

### Task 1.6 — Honest `clear()`

**Why:** `clear()` currently sets `_layout = GraphLayout.empty()` and never re-centres;
after a reset the camera stays wherever it was, forever.

**File:** `packages/force_directed_graphview/lib/src/controller.dart`

**Do (two edits):**

1. Replace the body of `clear()`:

```dart
  /// Removes every node and edge. When [recenter] is true the next layout
  /// re-centres the viewport, as if the graph had just been created.
  void clear({bool recenter = true}) {
    _nodes.clear();
    _edges.clear();
    _layout = null;
    _transitionFrom = null;
    _transitionTarget = null;
    _ticker?.stop();
    if (recenter) {
      _centered = false;
    }
    notifyListeners();
  }
```

2. `_relayout()` currently bails out when `layout == null`, which after the change above
   means the graph never rebuilds after a `clear()`. Replace the guard and the stream
   selection:

```dart
  Future<void> _relayout() async {
    final currentAlgorithm = _currentAlgorithm;
    final currentSize = _currentSize;
    final layout = _layout;

    if (currentAlgorithm == null || currentSize == null) {
      return;
    }

    final generation = ++_relayoutGeneration;
    final nodesSnapshot = Set<N>.of(_nodes);
    final edgesSnapshot = Set<E>.of(_edges);

    final layoutStream = layout == null
        ? currentAlgorithm.layout(
            nodes: nodesSnapshot,
            edges: edgesSnapshot,
            size: currentSize,
          )
        : currentAlgorithm.relayout(
            existingLayout: layout,
            nodes: nodesSnapshot,
            edges: edgesSnapshot,
            size: currentSize,
          );

    await for (final layout in layoutStream) {
      if (generation != _relayoutGeneration) {
        return;
      }
      _publishLayout(layout);
    }
  }
```

**Verify:**

```bash
cd packages/force_directed_graphview && flutter test
```

**Done when:** V4 passes. `controller_test.dart` has no coverage of `clear()` today, so
nothing should break; add a test asserting the new contract — right after `clear()`,
`canLayout` is `false`, and after the next `mutate` + settle it is `true` again.

---

### Task 1.7 — Record the fork changes

**Files:** `packages/force_directed_graphview/CHANGELOG.md`, `pubspec.yaml`

**Do:** bump `version:` to `0.6.2+tentura.1` in the fork's `pubspec.yaml` and prepend to
`CHANGELOG.md`:

```markdown
## 0.6.2+tentura.1 (Tentura fork)

- Add `GraphView.layoutTransitionDuration` / `layoutTransitionCurve`: the controller now
  interpolates between the previous and the newly computed layout instead of applying
  every solver iteration directly.
- Add `GraphLayout.lerp`.
- Add `GraphController.fitToRect` / `fitToNodes`.
- Apply configuration changes at runtime via `didUpdateWidget` (the layout algorithm can
  now be swapped after the first build).
- `GraphController.clear()` resets the layout and re-centres on the next layout.
- `FruchtermanReingoldAlgorithm` now has value equality.
```

**Verify:** `cd packages/client && flutter pub get` still resolves.

**Phase 1 gate — all four must pass:**

```bash
cd packages/force_directed_graphview && flutter test
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test
./scripts/check-custom-lints.sh packages/client
```

The client is untouched in Phase 1, so V2 must still report **1497 passed, 14 skipped**.

---

## Phase 2 — Deterministic layout algorithms

**Goal:** replace the stochastic, order-dependent force simulation with pure functions.

**Design rule for this phase:** the geometry is a **pure function** in `domain/`, and a
thin adapter in `ui/` implements the library's `GraphLayoutAlgorithm`. The pure function
takes and returns primitives (`String` ids, `Offset`, `Size`) so it can be unit-tested
without Flutter widgets and without the graph library.

**Canvas bounds.** The canvas is a fixed `4096 × 4096` (`GraphBody.canvasSize`), so the
centre is at `(2048, 2048)`. With `ringGap = 170` a radial layout leaves the canvas past
hop 12, and a wide layer can overflow horizontally. Both pure functions must therefore
**clamp their final positions** into `[node radius, canvasSize.side - node radius]`, the
same way `FruchtermanReingoldAlgorithm._runIteration` does today. Since the pure functions
do not know node sizes, clamp with a fixed margin of `80` and document it. Clamping is the
last step and must not change the *relative* order of nodes in the common case.

### Task 2.1 — Radial hop layout (pure function)

**New file:** `packages/client/lib/features/graph/domain/layout/radial_hop_positions.dart`

**Contract:**

```dart
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Deterministic ego-centric layout: concentric rings by BFS hop distance.
///
/// Guarantees, all covered by tests:
///  * the result depends only on the arguments, never on iteration order of the
///    input sets (every neighbour list is sorted by id before use);
///  * a node's ring is its hop distance from [rootId] over the **undirected**
///    projection of [edges], so cycles are handled without special cases;
///  * adding a node does not move any node that was already present, as long as
///    its hop distance and its BFS parent did not change.
Map<String, Offset> radialHopPositions({
  required Set<String> nodeIds,
  required Set<(String, String)> edges,
  required String rootId,
  required Size canvasSize,
  List<String> focusPath = const [],
  double ringGap = 170,
});
```

**Algorithm — implement exactly this:**

1. Build an undirected adjacency map `Map<String, List<String>>`. For every
   `(src, dst)` in `edges` where **both** endpoints are in `nodeIds` and `src != dst`,
   append `dst` to `adj[src]` and `src` to `adj[dst]`. Then **sort every list and
   deduplicate it** (`list..sort()`, then `toSet().toList()`), so iteration order of the
   input `Set` cannot influence the result.
2. BFS from `rootId` using a `Queue<String>`, recording `depth[id]` and `parent[id]`.
   Process each node's neighbours in the sorted order from step 1.
3. Nodes in `nodeIds` never reached by the BFS (disconnected) get
   `depth = maxReachedDepth + 1` and `parent = rootId`. Sort them by id so their order
   is stable.
4. Compute `subtreeSize[id]`: 1 for a leaf, otherwise 1 plus the sum over its BFS
   children. Compute it by walking nodes in **descending depth order**.
5. Assign angular sectors top-down. `rootId` owns `[0, 2π)`. For a node owning
   `[start, end)`, split that span among its BFS children **proportionally to
   `subtreeSize`**, in ascending id order. A node's own angle is the centre of its
   sector.
6. Position: `centre + Offset(cos(a - π/2), sin(a - π/2)) * (depth * ringGap)`, where
   `centre = canvasSize.center(Offset.zero)` and the `-π/2` makes angle 0 point up.
7. **Focus path pinning.** If `focusPath.length >= 2` and `focusPath[1]` has a sector,
   rotate **every** angle by `-(angleOf(focusPath[1]))` so that the first step of the
   active path always points straight up. This is what makes the active path visually
   stable while unrelated nodes are added.
8. `rootId` itself is placed at `centre` exactly.

**Verify:** new file
`packages/client/test/features/graph/radial_hop_positions_test.dart` covering:

| Test | Assertion |
|---|---|
| root at centre | `positions['root'] == canvasSize.center(Offset.zero)` |
| ring by hop | a 2-hop node's distance from centre ≈ `2 * ringGap` (tolerance 0.01) |
| **order independence** | build the same graph from two `Set`s with different insertion order → identical maps |
| **stability** | compute for `{a,b}`, then for `{a,b,c}` where `c` hangs off `b`; `a`'s position is unchanged |
| cycles | a 3-cycle `a→b→c→a` with root `a` produces three finite, pairwise distinct positions |
| disconnected | a node with no edges still gets a position, on the outermost ring |

```bash
cd packages/client && flutter test test/features/graph/radial_hop_positions_test.dart
```

---

### Task 2.2 — Layered DAG layout (pure function)

**New file:** `packages/client/lib/features/graph/domain/layout/layered_dag_positions.dart`

**Contract:**

```dart
/// Deterministic layered ("Sugiyama-lite") layout for the invite genealogy and
/// the forwards graph: rank = distance from the root, drawn top to bottom.
Map<String, Offset> layeredDagPositions({
  required Set<String> nodeIds,
  required Set<(String, String)> edges,
  required Set<String> rootIds,
  required Size canvasSize,
  double layerGap = 150,
  double columnGap = 130,
});
```

**Algorithm — implement exactly this:**

1. Adjacency, both directions, sorted and deduplicated as in Task 2.1.
2. `rank[id]`: BFS over **directed** edges from every id in `rootIds` (all roots start at
   rank 0). If `rootIds` is empty, use every node with in-degree 0; if that is also empty
   (a pure cycle), use the lexicographically smallest id.
   Unreached nodes get `rank = maxRank + 1`, sorted by id.
3. Group node ids by rank into `layers`.
4. Order within each layer: two passes.
   - Pass 1, ranks ascending: sort each layer by
     `(barycentre of the x of already-placed predecessors, id)`. A node without placed
     predecessors uses barycentre `double.infinity` so it sorts last, deterministically.
   - Pass 2, ranks descending: same but using successors. Keep the pass-1 order as the
     tie-break.
   Assign each node its index in its layer.
5. Horizontal placement, per layer. For a layer holding `n` nodes, the node at index `i`
   gets `x = canvasSize.width / 2 + (i - (n - 1) / 2) * columnGap`. That centres every
   layer on the canvas centre line independently of how many nodes it holds.
6. Vertical placement. With `maxRank` the largest rank present,
   `y = canvasSize.height / 2 + (rank - maxRank / 2) * layerGap`.

**Verify:** `packages/client/test/features/graph/layered_dag_positions_test.dart`:

| Test | Assertion |
|---|---|
| ranks become rows | a chain `a→b→c` yields three distinct, increasing `y`, equal `x` |
| siblings share a row | `a→b`, `a→c` gives `b.dy == c.dy` and `b.dx != c.dx` |
| **order independence** | two differently-ordered input sets → identical maps |
| **no overlap** | no two nodes in the same layer are closer than `columnGap` on x |
| cycle safety | `a→b→c→a` terminates and gives every node a finite position |

---

### Task 2.3 — Algorithm adapters

**New file:** `packages/client/lib/features/graph/ui/utils/tentura_layout_algorithms.dart`

Two immutable classes implementing `GraphLayoutAlgorithm`. Both must:

- override `==` and `hashCode` over **all** their fields (Task 1.2 depends on it);
- ignore `existingLayout` in `relayout` and return the same result as `layout` — that is
  what makes the layout order-independent;
- return a single-element stream: `Stream.value(built)`;
- map `NodeBase` → id by casting to `NodeDetails` (`(node as NodeDetails).id`), and build
  the layout with `GraphLayoutBuilder`.

```dart
final class RadialHopLayoutAlgorithm implements GraphLayoutAlgorithm {
  const RadialHopLayoutAlgorithm({
    required this.rootId,
    this.focusPath = const [],
    this.ringGap = 170,
  });
  // ...
}

final class LayeredDagLayoutAlgorithm implements GraphLayoutAlgorithm {
  const LayeredDagLayoutAlgorithm({
    required this.rootIds,
    this.layerGap = 150,
    this.columnGap = 130,
  });
  // ...
}
```

**Important:** if `nodes` is empty, yield `const GraphLayout.empty()`; if the pure
function returns no position for some node (must not happen, but be defensive), fall back
to `canvasSize.center(Offset.zero)` — `GraphLayoutBuilder.build()` throws
`StateError('Not all nodes have position')` otherwise.

`focusPath` and `rootIds` are `List`/`Set` of `String`; implement `==` with
`ListEquality`/`SetEquality` from `package:collection`, otherwise every rebuild looks
like a change and Task 1.2 relayouts forever.

**Verify:** `packages/client/test/features/graph/tentura_layout_algorithms_test.dart`
— for each algorithm: (a) two instances with equal fields are `==`; (b) `layout` and
`relayout` produce identical positions for the same input; (c) the emitted layout has a
position for every input node.

---

### Task 2.4 — Delete `positionHint`

**Why:** `positionHint` is the insertion-order hack (`positionHint: _nodes.length`) and it
is part of `NodeDetails.hashCode`/`==`, which silently drops a node's position whenever
the hint changes. Deterministic layouts make it unnecessary.

**Files and edits:**

1. `packages/client/lib/features/graph/domain/entity/node_details.dart`
   — remove the `positionHint` field, the `copyWithPositionHint` method (from the sealed
   base and all four subclasses), and `positionHint` from `hashCode`/`==`.
2. `packages/client/lib/features/graph/ui/utils/initial_position_extractor.dart`
   — **delete the file**.
3. `packages/client/test/features/graph/initial_position_extractor_test.dart`
   — **delete the file**.
4. `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`
   — remove every `positionHint:` argument and every `.copyWithPositionHint(...)` call
   (lines around 477, 481, 509, 591, 612 in the current file), plus the
   `isolatedHelpOffererPositionHint` usage.
5. `packages/client/lib/features/graph/domain/forward_graph_focus_rules.dart`
   — remove `isolatedHelpOffererPositionHint` and its test in
   `test/features/graph/forward_graph_focus_rules_test.dart`.
6. `packages/client/lib/features/graph/ui/widget/graph_body.dart`
   — remove the `initialPositionExtractor` import and the `FruchtermanReingoldAlgorithm`
   default (it is replaced in Task 4.6).

**Verify:**

```bash
cd packages/client && grep -rn "positionHint\|initialPositionExtractor" lib test
```

must print nothing, then V1 + V2.

---

## Phase 3 — Server: edge closure over known nodes

**Goal:** guarantee that any edge between two visible nodes is actually delivered to the
client. Today the client only ever receives the neighbourhood of the current focus.

**Do not touch** `mr_graph`, `public.graph()`, or the `0, 100` window — that decision is
final (see §10.2 of the analysis).

### Task 3.1 — SQL migration

**New file:** `packages/server/lib/data/database/migration/m0134.dart`

The latest existing migration is `m0133`. Follow its exact shape (`part of`, a doc
comment, `final m0134 = Migration('0134', [ ... ]);`).

```dart
part of '_migrations.dart';

/// Structural closure for the trust graph.
///
/// `mr_graph` ranks *who* to show and only ever returns the neighbourhood of the
/// current focus, so an edge between two already-visible nodes never arrives
/// until the user happens to focus one of its endpoints. `user_trust_edge` is a
/// plain table, so the structure between a known set of nodes can be answered
/// with pure SQL. Returns `graph_score` so the existing Hasura relationships and
/// select permissions apply unchanged.
final m0134 = Migration('0134', [
  r'''
CREATE OR REPLACE FUNCTION public.graph_edges_between(
  node_ids text[],
  positive_only boolean
) RETURNS SETOF public.graph_score
  LANGUAGE sql
  STABLE
  AS $$
SELECT
  e.subject AS src,
  e.object AS dst,
  (0)::double precision AS src_score,
  e.prev_sent_weight AS dst_score,
  public.user_trust_edge_degree(e.subject, positive_only) AS src_total_neighbor_count,
  public.user_trust_edge_degree(e.object, positive_only) AS dst_total_neighbor_count
FROM public.user_trust_edge e
WHERE e.subject = ANY(node_ids)
  AND e.object = ANY(node_ids)
  AND (positive_only = false OR e.prev_sent_weight > 0);
$$;
''',
]);
```

Then register it in `packages/server/lib/data/database/migration/_migrations.dart`:
add `part 'm0134.dart';` next to the other `part` directives, and `m0134,` at the end of
the migration list (after `m0133,`).

**Verify:**

```bash
cd packages/server && dart analyze
```

---

### Task 3.2 — Track the function in Hasura

**File:** `hasura/metadata.json`

`graph_score` is already a tracked view with `select_permissions` for role `user`, so only
the function needs tracking. Find the `"functions"` array in `metadata.sources[0]` (it
currently holds `graph`, `my_field`, `rating`) and add:

```json
{
  "function": { "name": "graph_edges_between", "schema": "public" },
  "configuration": { "custom_root_fields": {} },
  "permissions": [{ "role": "user" }]
}
```

**Note:** unlike `graph`, this function takes **no** `hasura_session` argument, so it must
**not** have `"session_argument"` in its configuration.

**Verify:** `python3 -m json.tool hasura/metadata.json > /dev/null` (valid JSON), then
apply the metadata to the local stack and confirm the field appears in the schema. Use the
`local-debug` skill to bring the stack up if it is not running.

---

### Task 3.3 — Client query + repository method

**New file:** `packages/client/lib/features/graph/data/gql/graph_edges_between.graphql`

```graphql
query GraphEdgesBetween($node_ids: [String!]!, $positive_only: Boolean = true) {
  graph_edges_between(args: { node_ids: $node_ids, positive_only: $positive_only }) {
    src
    dst
    src_score
    dst_score
    src_total_neighbor_count
    dst_total_neighbor_count
  }
}
```

Then:

```bash
cd packages/client && dart run build_runner build --delete-conflicting-outputs
```

**File:** `packages/client/lib/features/graph/data/repository/graph_repository.dart`

Add a method next to `fetch`, following the same `requestDataOnlineOrThrow` pattern:

```dart
  /// Structural closure: every trust edge whose **both** endpoints are in [nodeIds].
  /// Complements [fetch], which only ever returns the neighbourhood of one focus.
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async { /* ... */ }
```

Return `EdgeDirected` records with `node: null` and `branch: null` — the cubit already
resolves missing nodes lazily. Return `const {}` immediately when `nodeIds.length < 2`.

**File:** `packages/client/lib/features/graph/data/repository/graph_source_repository.dart`

Add to the abstract class, with a default implementation so the forwards and genealogy
repositories do not have to implement it:

```dart
  /// Edges whose both endpoints are already known. Sources that have no notion
  /// of a wider graph (forwards, genealogy) return nothing.
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async => const {};
```

Since `GraphSourceRepository` is an `abstract class` (not an interface), a concrete method
body is allowed. `ForwardsGraphRepository` and `InviteGenealogyRepository` **implement**
it rather than extend it, so add the same trivial override to both.

**Verify:** V1, V2, plus a repository unit test asserting `fetchEdgesBetween` with fewer
than two ids performs no network call.

---

### Task 3.4 — Server regression tests

**New file:** `packages/server/test/graph_edges_between_test.dart`, tagged for Postgres.
Look at an existing `-x pg`-tagged test in `packages/server/test/` and copy its
setup/teardown exactly.

Four cases, exactly as issue #86 requires:

| Case | Fixture | Assertion |
|---|---|---|
| one-way | `A→B` only | querying `[A,B]` returns exactly one row, `src=A, dst=B` |
| reciprocal | `A→B` and `B→A` | returns exactly two rows, one per direction |
| transitive | `A→B→C` | querying `[A,B,C]` returns both edges; querying `[A,C]` returns **none** |
| cyclic | `A→B→C→A` | returns three rows and the query terminates |

Also assert that `positive_only = true` filters out an edge with
`prev_sent_weight <= 0`.

**Run:**

```bash
cd packages/server && dart test -x pg   # excludes pg tests
cd packages/server && dart test -t pg   # runs them (needs the local stack)
```

---

## Phase 4 — Cubit and UI

### Task 4.1 — Call the closure query after every expansion

**File:** `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`

In `_fetch()`, after the block that resolves nodes for the fetched edges and **before**
`emit(state.copyWith(status: StateStatus.isSuccess))`, add a closure pass that runs only
for the trust graph (`forwardsGraphBeaconId == null && !genealogyMode`):

```dart
      if (_usesFocusPathVisibility && !genealogyMode) {
        final closure = await _graphSource.fetchEdgesBetween(
          nodeIds: _nodes.keys.toSet(),
          positiveOnly: state.positiveOnly,
        );
        edges = {...edges, ...closure};
      }
```

Guard it with the same `try`/`catch` that already wraps `_fetch` — a failing closure query
must degrade to today's behaviour, not blank the screen.

**Then remove the isolated-focus fallback.** Delete the block commented
`// Add FocusNode in case there were no edges containing it` (currently lines 502–516)
**except** the help-offerer branch, which is a different, intentional case. A trust node
with no edge must no longer be rendered — that symptom is literally created by this block.

**Verify:** a new cubit test in `graph_focus_path_visibility_test.dart`: a fake source
whose `fetch` returns `A→B` and whose `fetchEdgesBetween` returns `B→C` results in both
edges being present in `graphController.edges` after one expansion.

---

### Task 4.2 — `positiveOnly` becomes a pure visibility filter

**File:** `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`

Rewrite `togglePositiveOnly` so it no longer resets anything:

```dart
  void togglePositiveOnly() {
    if (forwardsGraphBeaconId != null || genealogyMode) {
      return;
    }
    emit(state.copyWith(positiveOnly: !state.positiveOnly));
    _recomputeVisibility();
  }
```

Then apply the filter inside `_recomputeVisibility`. Several places copy an entry from
`_allEdges` into `visibleEdges` — the `focusId.isEmpty` bulk `addAll`, the forward and the
backward trail edge, the focus-incident loop, and the always-visible loop — so do **not**
paste the same guard five times. Add one local helper at the top of the method and route
every insertion through it:

```dart
    final hideNegative = state.positiveOnly;

    void reveal((String, String) key, EdgeDirected edge) {
      if (hideNegative && edge.weight < 0) return;
      visibleEdges[key] = edge;
    }
```

Replace `visibleEdges.addAll(_allEdges)` with a loop calling `reveal`, and replace each
`visibleEdges[k] = v` with `reveal(k, v)`.

Finally, in `_updateGraph`, **stop dropping** negative edges from `_allEdges` (remove the
`if (state.positiveOnly && e.weight < 0) continue;` in the `_usesFocusPathVisibility`
branch) — the cache must hold everything so the filter can be toggled without a refetch.

**Verify:** cubit test — after `togglePositiveOnly()` twice, the graph contains exactly the
same edges as before, and `_FakeGraphSource.calls` did not increase.

---

### Task 4.3 — Focus history: `popFocus`, `resetToEgo`, `fitCurrentPath`

**File:** `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`

```dart
  /// True when there is somewhere to go back to.
  bool get canPopFocus => _focusPathIds.length > 1;

  /// Steps one hop back along the exploration trail. Pure visibility change —
  /// never refetches, because everything on the trail is already cached.
  void popFocus() {
    if (!canPopFocus) return;
    _focusPathIds.removeLast();
    final previous = _focusPathIds.last;
    emit(state.copyWith(focus: previous == _focusRootId ? '' : previous));
    _recomputeVisibility();
    final node = _nodes[previous];
    if (node != null) unawaited(Future.value(graphController.jumpToNode(node)));
  }

  /// Returns to the origin without dropping the cache: clears the trail, unpins
  /// every node except the root, recomputes visibility and re-centres.
  void resetToEgo() {
    _resetFocusPathRoot(_focusRootId);
    _pinnedNodeIds
      ..clear()
      ..add(_focusRootId);
    for (final entry in _nodes.entries) {
      if (entry.value.pinned && entry.key != _focusRootId) {
        _nodes[entry.key] = entry.value.copyWithPinned(false);
      }
    }
    emit(state.copyWith(focus: ''));
    _recomputeVisibility();
    jumpToEgo();
  }

  /// Fits the active path into the viewport. With a trail of one (only the
  /// origin) it fits the origin together with all of its visible neighbours.
  void fitCurrentPath() {
    if (!graphController.canLayout) return;
    var ids = _focusPathIds.toSet();
    if (ids.length <= 1) {
      for (final edge in graphController.edges) {
        if (edge.source.id == _focusRootId) ids.add(edge.destination.id);
        if (edge.destination.id == _focusRootId) ids.add(edge.source.id);
      }
    }
    graphController.fitToNodes(
      graphController.nodes.where((n) => ids.contains(n.id)),
    );
  }
```

**Also:** remove the unconditional `_pinNode(node)` from `setFocus`. Pin only the root and
the nodes currently on `_focusPathIds`; everything else must stay free so the deterministic
layout can place it.

**Verify:** cubit tests — `popFocus` restores the previous visible edge set exactly and
does not increase `calls`; `resetToEgo` leaves only the root's neighbourhood visible and
does not increase `calls`; `canPopFocus` is false at the start.

---

### Task 4.4 — Split select from expand

**Files:** `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`,
`packages/client/lib/features/graph/ui/widget/graph_body.dart`

1. In the cubit, split the current `setFocus` into two public methods:
   - `void selectNode(NodeDetails node)` — sets `state.focus`, updates the trail, pins the
     trail, recomputes visibility. **Never fetches.**
   - `Future<void> expandNode(NodeDetails node)` — calls `selectNode` if the node is not
     already focused, then always runs `_fetch()` (which pages in the next
     `kFetchWindowSize` neighbours).
   Keep `setFocus` as a deprecated alias that forwards to `selectNode` **only if** other
   call sites still use it; otherwise delete it and update the call sites.

2. In `graph_body.dart`, delete `_doubleTapWindow`, `_lastTapNodeId`, `_lastTapTime` and
   the whole manual double-tap detection in `_onNodeTap`. Replace with:
   - single tap → `_graphCubit.selectNode(node)`;
   - the selected node shows an action panel (Task 4.5) whose buttons call
     `expandNode`, `showProfile` / `showBeacon`.

   The manual double-tap hack exists only because the first tap pinned and replaced the
   node, resetting gesture recognition. With pinning gone from the select path, it is no
   longer needed.

3. Per `cross-platform gesture affordances`: the client runs on touch **and** desktop.
   Never make long-press the only route to an action — every action in the panel must also
   be reachable by a normal tap on a visible control.

**Verify:** widget test — one tap on a node emits a new `focus` and performs **no** fetch;
tapping "Expand" performs exactly one fetch.

---

### Task 4.5 — Navigation controls

**File:** `packages/client/lib/features/graph/ui/widget/graph_body.dart`

Add four controls. They must be reachable on **every** window class — the current
`_GraphSideControls` is only built in the non-compact branch of the `LayoutBuilder`, which
is why a phone today has no graph controls at all.

| Control | Action | Enabled when |
|---|---|---|
| Back | `cubit.popFocus()` | `cubit.canPopFocus` |
| Reset to me | `cubit.resetToEgo()` | always |
| Fit current path | `cubit.fitCurrentPath()` | `graphController.canLayout` |
| Legend | existing toggle | always |

Implementation notes:
- put them in a `Positioned` overlay inside the existing `Stack` (the same place the legend
  already lives), so they render regardless of window class;
- use `IconButton` with `tooltip:` — already themed by `TenturaTheme`;
- keep tap targets ≥ 48 dp (`tt.buttonHeight`);
- spacing from `context.tt` (`tt.rowGap`, `tt.iconTextGap`), never raw `EdgeInsets`;
- add l10n keys to **both** `app_en.arb` and `app_ru.arb`, then `flutter gen-l10n`:
  `graphBack` / "Back" / "Назад",
  `graphResetToEgo` / "Reset to me" / "Вернуться к себе",
  `graphFitPath` / "Fit current path" / "Показать путь целиком".

Also make the origin visible: the ego node must stay visually distinct when focus moves
elsewhere. `_recomputeVisibility` already keeps `rootId` visible; give it a ring or badge
in `graph_node_widget.dart` using `colorScheme.primary`.

**Verify:** widget test at compact width (`setSurfaceSize(Size(400, 800))`) finds all four
controls; tapping Back with an empty trail is a no-op.

---

### Task 4.6 — Use the deterministic algorithms

**File:** `packages/client/lib/features/graph/ui/widget/graph_body.dart`

Replace the `layoutAlgorithm` constructor default with a mode-driven getter, and turn on
transitions:

```dart
  GraphLayoutAlgorithm get _layoutAlgorithm {
    if (_graphCubit.genealogyMode) {
      return LayeredDagLayoutAlgorithm(rootIds: {_graphCubit.state.egoNodeId});
    }
    if (_graphCubit.forwardsGraphBeaconId != null) {
      return LayeredDagLayoutAlgorithm(rootIds: _graphCubit.forwardsRootIds);
    }
    return RadialHopLayoutAlgorithm(
      rootId: _graphCubit.state.me.id,
      focusPath: _graphCubit.focusPath,
    );
  }
```

and in `_buildGraphView()`:

```dart
    layoutAlgorithm: _layoutAlgorithm,
    layoutTransitionDuration: const Duration(milliseconds: 350),
```

Expose what the getter needs from the cubit: `List<String> get focusPath =>
List.unmodifiable(_focusPathIds);` and a `Set<String> get forwardsRootIds` (the forwards
author id, empty set otherwise).

**The `BlocBuilder` in `build` currently rebuilds only when `isLoading` changes**
(`buildWhen`). The algorithm depends on `focus`/`focusPath`, so widen it:

```dart
    buildWhen: (previous, current) =>
        previous.isLoading != current.isLoading ||
        previous.focus != current.focus ||
        previous.positiveOnly != current.positiveOnly,
```

Set `spawnPositionResolver` on the controller so newly expanded nodes travel out of the
node they came from — in the cubit, before the mutate in `_recomputeVisibility`:

```dart
    graphController.spawnPositionResolver = (node) {
      final focusNode = _nodes[state.focus];
      if (focusNode == null || !graphController.canLayout) return null;
      return graphController.layout.getPositionOrNull(focusNode);
    };
```

Returning `null` is fine — `GraphLayout.lerp` then starts the node at its final position.

**Verify:** V1, V2, then run the app and expand three nodes: nothing jitters, nodes glide,
and expanding the same set in a different order produces the same picture.

---

### Task 4.7 — Legend becomes the filter

**Files:** `packages/client/lib/features/graph/ui/widget/graph_legend_content.dart`,
`graph_body.dart`

1. In `GraphLegendContent`, make the negative-edge row a toggle for
   `GraphMode.trust` only: wrap it in `BlocSelector<GraphCubit, GraphState, bool>` on
   `positiveOnly` and call `context.read<GraphCubit>().togglePositiveOnly()` on tap.
   Render it visibly as a control (a trailing `Switch` or `Checkbox`), and dim the colour
   swatch when the layer is off — otherwise the whole legend looks tappable.
2. Remove the `positiveOnly` `IconButton` from `_GraphSideControls` and the
   `togglePositiveOnly` `PopupMenuItem` from `graph_screen.dart` — one control, one place.
3. Add l10n for the toggle's semantics label
   (`graphLegendToggleNegative` / "Show negative connections" / "Показывать отрицательные
   связи").

This is only safe **after Task 4.2** — before it, toggling wipes the whole exploration.

**Verify:** widget test at compact width — the negative-edge row is tappable and toggling
it flips `state.positiveOnly` without a refetch.

---

### Task 4.8 — Reciprocal edges as a two-track railway

**Files:** `packages/client/lib/features/graph/domain/entity/edge_details.dart`,
`packages/client/lib/features/graph/ui/utils/animated_highlighted_edge_painter.dart`,
`packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`

Both directions of a mutual relationship are **already** created and drawn — they just sit
on the same straight line, so the two shaders overlap. Separate them.

1. `EdgeDetails`: add `final bool isReciprocal;` (default `false`), include it in `==` /
   `hashCode` and in `replaceNode`.
2. `_buildEdgeDetails` in the cubit: `isReciprocal: _allEdges.containsKey((dst.id, src.id))`.
   For forwards and genealogy pass `false`.
3. In the painter, when `isReciprocal` is true, offset the edge to the **left of its own
   direction of travel** and draw it as a quadratic curve:

```dart
    final delta = dst - src;
    final length = delta.distance;
    if (length <= 0) return;
    final normal = Offset(delta.dy, -delta.dx) / length; // left of travel
    final lateral = edge.isReciprocal
        ? math.min(edge.strokeWidth * 2, length * 0.12)
        : 0.0;
    final a = src + normal * lateral;
    final b = dst + normal * lateral;
    final control = (a + b) / 2 + normal * lateral;
```

   Build the shader with `ui.Gradient.linear(a, b, ...)` — a linear gradient's isolines are
   perpendicular to the `a→b` axis, so the highlight still runs **along** the curve.
   Draw with `canvas.drawPath(Path()..moveTo(a.dx, a.dy)..quadraticBezierTo(control.dx,
   control.dy, b.dx, b.dy), paint)`.
   Keep the arrowhead at the `b` end.

   Sanity check for the normal: for `delta = (1, 0)` (travelling right) the formula gives
   `(0, -1)` — up, i.e. left of travel, correct for screen coordinates with y pointing down.
   Because each edge offsets left of **its own** direction, the opposite edge automatically
   lands on the other side; the painter never needs to know about its counterpart.

4. Legend: add a "mutual / one-way" row for `GraphLegendMode.trust` with l10n in both arb
   files.

**Verify:** golden test on a pair of reciprocal edges — the two paths do not overlap except
near the nodes. Follow the golden pattern from
`test/features/inbox/inbox_item_tile_golden_test.dart`; regenerate deliberately with
`flutter test --update-goldens <path>` and look at the PNG.

---

## Phase 5 — Regression coverage

### Task 5.1 — Relationship-shape regressions (issue #86 requirement)

**File:** `packages/client/test/features/graph/graph_focus_path_visibility_test.dart`

Add one test per shape, all through the existing `_FakeGraphSource`:

| Shape | Fixture | Assertion |
|---|---|---|
| one-way | `A→B`, focus A | B visible with a drawn edge |
| reciprocal | `A→B`, `B→A` | two edges present, both `isReciprocal` |
| transitive | `A→B`, `B→C` | expanding A then B shows the full chain |
| cyclic | `A→B`, `B→C`, `C→A` | expanding around the cycle terminates and every node keeps exactly one position |
| **order independence** | expand `A→B→C` vs `A→C→B` (both reachable) | the final visible node **and** edge sets are equal |

### Task 5.2 — Layout stability

**File:** `packages/client/test/features/graph/radial_hop_positions_test.dart` (extend)

Assert explicitly what the ticket demands: expanding an unrelated node does **not** change
the position of any node already on the focus path.

### Task 5.3 — End-to-end scenario

Add to the web integration suite (see `docs/local-integration-tests.md`; run with
`scripts/run_client_integration_web_local.sh`) a scenario matching the ticket's acceptance
criterion:

> expand two or three hops → understand the active path → return to the previous focus →
> reset the graph — all without leaving the screen.

Assert: after Back the previous focus is restored; after Reset the trail is length 1 and
the viewport is centred on ego; no full-page reload happened.

---

## 6. Final gate

Everything below must pass before the work is considered complete:

```bash
cd packages/force_directed_graphview && flutter test
cd packages/tentura_lints && dart test
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test
cd packages/server && dart analyze && dart test -x pg
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh
```

Then bump `version:` in `packages/client/pubspec.yaml` once for the whole change.

**Manual smoke test** (use the `local-debug` skill to bring up the stack):

1. Open "Show Connections" from a profile.
2. Expand three hops. Nothing jitters; nodes glide into place.
3. Every visible person has a visible edge explaining why they are on screen.
4. Back returns to the previous focus; Reset returns to you; Fit frames the path.
5. Toggle the negative-connections layer in the legend — the graph filters instantly,
   with no loading bar and no loss of what you had explored.
6. Repeat step 2 expanding the **same** nodes in a **different** order — the final picture
   is the same.

---

## 7. Task order and parallelism

```
Phase 1 (fork)  ──┐
                  ├──> Phase 4 (cubit + UI)  ──> Phase 5 (tests)
Phase 2 (layout) ─┘         ▲
                            │
Phase 3 (server) ───────────┘
```

- Phases 1, 2 and 3 are independent of each other and may be done in any order.
- Task 4.6 requires Phases 1 and 2. Task 4.1 requires Phase 3. Task 4.7 requires Task 4.2.
- Tasks 4.4/4.5 (interaction) and 4.8 (reciprocal lanes) depend on nothing outside Phase 4
  and can be done first if an early user-visible improvement is wanted.
