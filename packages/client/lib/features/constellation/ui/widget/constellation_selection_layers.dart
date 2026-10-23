import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

import '../../domain/constellation_layout.dart';
import '../../domain/constellation_sector_arrangement.dart';
import '../../domain/layout/layout_geometry.dart';
import '../bloc/constellation_cubit.dart';
import '../bloc/constellation_selection_cubit.dart';
import '../util/layout_geometry_adapters.dart';
import '../utils/constellation_graph_scene.dart';

export '../bloc/constellation_selection_cubit.dart'
    show ConstellationSelectionCubit, maybeConstellationSelection;

/// Field multi-select (#642) and «Arrange in a sector» (#644) on the map.
///
/// Touch: the toolbar toggle turns a tap into "add to / remove from the
/// selection" (no long-press). Desktop: Shift-, Ctrl- or Cmd-click does the
/// same without the toggle, and a Shift-drag on the map draws a box that adds
/// everything inside it.

/// Handles a map node tap for the selection; true when the tap was used.
bool constellationSelectionTap(
  BuildContext context,
  ConstellationCubit cubit,
  NodeDetails node,
) {
  final selection = maybeConstellationSelection(context);
  if (selection == null ||
      cubit.state.isComposing ||
      selection.state.sector != null) {
    return false;
  }
  final byModifier = ConstellationSelectionCubit.modifierHeld;
  if (!selection.state.selecting && !byModifier) return false;
  final target = cubit.anchorTargetForNode(node);
  if (target != null) selection.toggle(target);
  // In select mode a tap on yourself does nothing rather than open.
  return target != null || selection.state.selecting;
}

/// App-bar toggle for select mode.
class ConstellationSelectionToggle extends StatelessWidget {
  const ConstellationSelectionToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = maybeConstellationSelection(context);
    if (selection == null) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocBuilder<
      ConstellationSelectionCubit,
      ConstellationMultiSelection
    >(
      bloc: selection,
      buildWhen: (previous, current) => previous.selecting != current.selecting,
      builder: (context, state) => IconButton(
        key: const Key('constellation.app_bar.select'),
        tooltip: l10n.constellationSelectMany,
        isSelected: state.selecting,
        onPressed: () => selection.setSelecting(!state.selecting),
        icon: const Icon(Icons.select_all),
        constraints: BoxConstraints(
          minWidth: tt.buttonHeight,
          minHeight: tt.buttonHeight,
        ),
      ),
    );
  }
}

/// The map layers of the selection, above the nodes: rings around selected
/// nodes, the Shift-drag box and, while editing, the sector and its handles.
class ConstellationSelectionLayers extends StatelessWidget {
  const ConstellationSelectionLayers({
    required this.cubit,
    this.hitsNode,
    super.key,
  });

  final ConstellationCubit cubit;

  /// The map's own tap hit test (labels included): a pointer it claims is
  /// left to the map, so a label tap still toggles its node.
  final bool Function(Offset local)? hitsNode;

  @override
  Widget build(BuildContext context) {
    final selection = maybeConstellationSelection(context);
    if (selection == null || cubit.state.isComposing) {
      return const SizedBox.shrink();
    }
    return BlocBuilder<
      ConstellationSelectionCubit,
      ConstellationMultiSelection
    >(
      bloc: selection,
      builder: (context, state) => Stack(
        fit: StackFit.expand,
        children: [
          if (!state.isEmpty)
            IgnorePointer(
              child: _SelectionRings(cubit: cubit, targets: state.targets),
            ),
          if (state.sector == null)
            _BoxSelect(
              cubit: cubit,
              selection: selection,
              hitsNode: hitsNode,
            )
          else
            _SectorEditor(cubit: cubit, selection: selection),
        ],
      ),
    );
  }
}

class _SelectionRings extends StatelessWidget {
  const _SelectionRings({required this.cubit, required this.targets});

  final ConstellationCubit cubit;
  final Set<ConstellationAnchorTarget> targets;

  @override
  Widget build(BuildContext context) {
    final controller = cubit.graphController;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.cameraRevision]),
      builder: (context, _) {
        final snapshot = controller.renderSnapshot;
        final scale = controller.cameraScale;
        final rings = <(Offset, double)>[];
        for (final target in targets) {
          final graphId = constellationGraphNodeIdForTarget(target);
          final node = snapshot.topology.nodesById[graphId];
          final point = snapshot.resolvePosition(graphId);
          if (node == null || point == null) continue;
          rings.add((
            controller.sceneToViewportLocal(Offset(point.x, point.y)),
            math.max(node.size.width, node.size.height) * scale / 2 +
                tt.tightGap * 2,
          ));
        }
        return CustomPaint(
          key: const Key('constellation.selection.rings'),
          painter: _RingsPainter(
            rings: rings,
            color: scheme.primary,
            stroke: TenturaSpacing.focusRing * 1.5,
          ),
        );
      },
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({
    required this.rings,
    required this.color,
    required this.stroke,
  });

  final List<(Offset, double)> rings;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final halo = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 3;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final (centre, radius) in rings) {
      canvas
        ..drawCircle(centre, radius + stroke, halo)
        ..drawCircle(centre, radius, ring);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.color != color ||
      old.stroke != stroke ||
      old.rings.length != rings.length ||
      !_sameRings(old.rings, rings);

  static bool _sameRings(List<(Offset, double)> a, List<(Offset, double)> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Moves the camera for gestures a selection layer takes from the map: two
/// fingers (or a trackpad) pan and pinch, the wheel zooms at the pointer.
final class _Camera {
  _Camera(this.controller);

  final GraphController<NodeDetails, EdgeDetails> controller;

  /// The scale of the running gesture at the last update; null between
  /// gestures.
  double? _scale;

  /// The InteractiveViewer wheel rate.
  static const _wheelRate = 200.0;

  // The recognizer ends and restarts its gesture when a finger joins or
  // leaves, and reports scale relative to that restart and focal movement
  // as a delta that leaves out the jump of the average; both are used as
  // given, so nothing is lost or doubled across a restart.
  void start(ScaleStartDetails _) => _scale = 1;

  void update(ScaleUpdateDetails details) {
    final scale = _scale ?? details.scale;
    final previous = details.localFocalPoint - details.focalPointDelta;
    // Zoom about where the fingers were, then carry that point along with
    // them, so the map stays under the fingers.
    if (scale > 0 && details.scale > 0 && details.scale != scale) {
      zoomAround(previous, details.scale / scale);
    }
    panBy(details.focalPointDelta);
    _scale = details.scale;
  }

  void end() => _scale = null;

  void wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      zoomAround(
        scroll.localPosition,
        math.exp(-scroll.scrollDelta.dy / _wheelRate),
      );
    });
  }

  void panBy(Offset delta) {
    final size = controller.viewportSize;
    if (size == null || delta == Offset.zero) return;
    controller.jumpToPosition(
      controller.viewportLocalToScene(size.center(Offset.zero) - delta),
    );
  }

  void zoomAround(Offset focal, double factor) {
    final size = controller.viewportSize;
    if (size == null || !factor.isFinite || factor <= 0) return;
    final before = controller.viewportLocalToScene(focal);
    controller.zoomBy(factor);
    final after = controller.viewportLocalToScene(focal);
    controller.jumpToPosition(
      controller.viewportLocalToScene(size.center(Offset.zero)) +
          (before - after),
    );
  }
}

/// Smallest screen extent a node takes for "is this on a node", so a node
/// drawn tiny at a low zoom still gets its taps and drags.
const double _minNodeHitExtent = kMinInteractiveDimension;

/// The nodes whose body, as drawn on screen, meets [rect] (viewport
/// coordinates), whatever the zoom.
List<ConstellationAnchorTarget> _targetsIn(
  ConstellationCubit cubit,
  Rect rect, {
  double minExtent = 0,
}) {
  final controller = cubit.graphController;
  final snapshot = controller.renderSnapshot;
  final scale = controller.cameraScale;
  final hits = <ConstellationAnchorTarget>[];
  for (final MapEntry(key: graphId, value: node)
      in snapshot.topology.nodesById.entries) {
    final point = snapshot.resolvePosition(graphId);
    final payload = controller.nodePayloadForId(graphId);
    if (point == null || payload is! NodeDetails) continue;
    final body = Rect.fromCenter(
      center: controller.sceneToViewportLocal(Offset(point.x, point.y)),
      width: math.max(node.size.width * scale, minExtent),
      height: math.max(node.size.height * scale, minExtent),
    );
    if (!body.overlaps(rect)) continue;
    final target = cubit.anchorTargetForNode(payload);
    if (target != null) hits.add(target);
  }
  return hits;
}

/// Whether a pointer at [local] lands on a node (yourself included).
bool _onNode(ConstellationCubit cubit, Offset local) {
  final controller = cubit.graphController;
  final snapshot = controller.renderSnapshot;
  final scale = controller.cameraScale;
  for (final MapEntry(key: graphId, value: node)
      in snapshot.topology.nodesById.entries) {
    final point = snapshot.resolvePosition(graphId);
    if (point == null) continue;
    final body = Rect.fromCenter(
      center: controller.sceneToViewportLocal(Offset(point.x, point.y)),
      width: math.max(node.size.width * scale, _minNodeHitExtent),
      height: math.max(node.size.height * scale, _minNodeHitExtent),
    );
    if (body.contains(local)) return true;
  }
  return false;
}

/// Pointers down anywhere in the app, so a gesture another layer already
/// owns (a finger on a node) keeps its next finger too.
final class _PointersDown {
  _PointersDown() {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  final _down = <int>{};

  bool get any => _down.isNotEmpty;

  void _route(PointerEvent event) {
    switch (event) {
      case PointerDownEvent() || PointerPanZoomStartEvent():
        _down.add(event.pointer);
      case PointerUpEvent() || PointerCancelEvent() || PointerPanZoomEndEvent():
        _down.remove(event.pointer);
      default:
    }
  }

  void dispose() =>
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
}

/// One pointer session of a selection layer: from the first pointer down to
/// the last one up. A scale gesture ends and restarts whenever a finger
/// joins or leaves; the session does not, so a box is never committed half
/// way and a pinch never turns back into a box or an aim.
final class _Session {
  final _pointers = <int>{};
  PointerDeviceKind? kind;

  /// More than one pointer took part: a pan or pinch from here on.
  bool multi = false;

  bool get active => _pointers.isNotEmpty;

  void down(PointerEvent event) {
    if (_pointers.isEmpty) {
      kind = event.kind;
      multi = false;
    }
    _pointers.add(event.pointer);
    // A trackpad gesture is a two-finger one.
    if (_pointers.length > 1 || event is PointerPanZoomStartEvent) {
      multi = true;
    }
  }

  void up(PointerEvent event) => _pointers.remove(event.pointer);
}

/// Rubber-band (box) selection (#642), the main way to pick several nodes.
///
/// It takes a pointer that goes down on empty map while the select tool is
/// on, or anywhere off a node while Shift is held; everything else (a tap or
/// a drag on a node or its label, a plain drag with the tool off) reaches the
/// map as before. One finger or the mouse draws the box; a second finger
/// turns the gesture into a pan and pinch of the map, and the wheel zooms.
///
/// On release: with Shift the nodes in the box are added, with Ctrl/Cmd they
/// are toggled; otherwise a mouse box replaces the selection and a touch box
/// adds to it (a touch screen has no modifier to add with).
class _BoxSelect extends StatefulWidget {
  const _BoxSelect({
    required this.cubit,
    required this.selection,
    this.hitsNode,
  });

  final ConstellationCubit cubit;
  final ConstellationSelectionCubit selection;

  /// The map's own tap hit test (labels included), when there is one.
  final bool Function(Offset local)? hitsNode;

  @override
  State<_BoxSelect> createState() => _BoxSelectState();
}

class _BoxSelectState extends State<_BoxSelect> {
  late final _camera = _Camera(widget.cubit.graphController);
  final _everywhere = _PointersDown();
  final _session = _Session();
  Offset? _start;
  Offset? _end;

  @override
  void dispose() {
    _everywhere.dispose();
    super.dispose();
  }

  bool _accepts(Offset local) {
    // The rest of a gesture this layer started stays with it.
    if (_session.active) return true;
    // A finger already down elsewhere (e.g. on a node): the map owns the
    // gesture, so this finger joins its pan or pinch.
    if (_everywhere.any) return false;
    final state = widget.cubit.state;
    if (state.isComposing ||
        state.placementPhase != ConstellationPlacementPhase.idle) {
      return false;
    }
    // Read now, not from the last build: the tool may have just turned on.
    if (!widget.selection.state.selecting &&
        !HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    return !_onNode(widget.cubit, local) &&
        !(widget.hitsNode?.call(local) ?? false);
  }

  void _down(PointerEvent event) {
    _session.down(event);
    if (_session.multi) _clearBox();
  }

  /// A cancelled pointer abandons the box.
  void _cancel(PointerEvent event) {
    _session
      ..up(event)
      ..multi = true;
    _clearBox();
  }

  void _clearBox() {
    if (_start == null && _end == null) return;
    setState(() {
      _start = null;
      _end = null;
    });
  }

  void _onStart(ScaleStartDetails details) {
    if (_session.multi || details.pointerCount > 1) {
      _clearBox();
      _camera.start(details);
      return;
    }
    setState(() {
      _start = details.localFocalPoint;
      _end = details.localFocalPoint;
    });
  }

  void _onUpdate(ScaleUpdateDetails details) {
    if (_session.multi || details.pointerCount > 1) {
      _camera.update(details);
      return;
    }
    setState(() => _end = details.localFocalPoint);
  }

  void _onEnd(ScaleEndDetails _) {
    _camera.end();
    final start = _start;
    final end = _end;
    // A finger joining or leaving ends the scale gesture, not the session:
    // only a box drawn by one pointer from start to finish is applied.
    if (_session.multi || _session.active) {
      if (_session.multi) _clearBox();
      return;
    }
    _clearBox();
    if (start == null || end == null) return;
    final rect = Rect.fromPoints(start, end);
    if (rect.longestSide < kTouchSlop) return;
    final keyboard = HardwareKeyboard.instance;
    final kind = _session.kind;
    final merge = keyboard.isControlPressed || keyboard.isMetaPressed
        ? ConstellationBoxMerge.toggle
        : keyboard.isShiftPressed ||
              kind == PointerDeviceKind.touch ||
              kind == PointerDeviceKind.stylus
        ? ConstellationBoxMerge.add
        : ConstellationBoxMerge.replace;
    widget.selection.applyBox(_targetsIn(widget.cubit, rect), merge);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = _start;
    final end = _end;
    return _HitTestWhen(
      enabled: _accepts,
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _session.up,
        onPointerCancel: _cancel,
        onPointerPanZoomStart: _down,
        onPointerPanZoomEnd: _session.up,
        onPointerSignal: _camera.wheel,
        child: GestureDetector(
          key: const Key('constellation.selection.box'),
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onStart,
          onScaleUpdate: _onUpdate,
          onScaleEnd: _onEnd,
          child: CustomPaint(
            key: const Key('constellation.selection.box_rect'),
            painter: start == null || end == null
                ? null
                : _BoxPainter(
                    rect: Rect.fromPoints(start, end),
                    color: scheme.primary,
                    stroke: context.tt.tightGap / 2,
                  ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  const _BoxPainter({
    required this.rect,
    required this.color,
    required this.stroke,
  });

  final Rect rect;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.08))
      ..drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.rect != rect || old.color != color || old.stroke != stroke;
}

/// Takes part in hit testing (opaquely) only where [enabled] says so, asked
/// at each pointer down rather than tracked, so a missed key-up never leaves
/// the map blocked.
class _HitTestWhen extends SingleChildRenderObjectWidget {
  const _HitTestWhen({required this.enabled, super.child});

  final bool Function(Offset position) enabled;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitTestWhen(enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHitTestWhen renderObject,
  ) {
    renderObject.enabled = enabled;
  }
}

class _RenderHitTestWhen extends RenderProxyBox {
  _RenderHitTestWhen(this.enabled);

  bool Function(Offset position) enabled;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      size.contains(position) &&
      enabled(position) &&
      super.hitTest(result, position: position);
}

/// The stored-position envelope in scene coordinates, a hair inside its
/// edges so a target on the edge survives rounding.
const LRect _envelope = (
  left:
      kConstellationCanvasCentre +
      kConstellationCoordinateMinUnits * kConstellationRingUnitPixels +
      1,
  top:
      kConstellationCanvasCentre +
      kConstellationCoordinateMinUnits * kConstellationRingUnitPixels +
      1,
  right:
      kConstellationCanvasCentre +
      kConstellationCoordinateMaxUnits * kConstellationRingUnitPixels -
      1,
  bottom:
      kConstellationCanvasCentre +
      kConstellationCoordinateMaxUnits * kConstellationRingUnitPixels -
      1,
);

/// The largest first-ring radius: across the whole envelope.
const double _maxSectorRadius =
    (kConstellationCoordinateMaxUnits - kConstellationCoordinateMinUnits) *
    kConstellationRingUnitPixels;

LPoint _clampToEnvelope(LPoint point) => (
  x: point.x.clamp(_envelope.left, _envelope.right),
  y: point.y.clamp(_envelope.top, _envelope.bottom),
);

/// The selected nodes «Arrange in a sector» can place now (drawn on the map
/// and draggable), by graph node id, and how many selected ones it cannot.
typedef ConstellationSectorItems = ({
  Map<String, ConstellationAnchorTarget> targets,
  List<ConstellationSectorMember> members,
  int skipped,
});

ConstellationSectorItems constellationSectorItems(
  ConstellationCubit cubit,
  ConstellationMultiSelection selection,
) {
  final controller = cubit.graphController;
  final snapshot = controller.renderSnapshot;
  final targets = <String, ConstellationAnchorTarget>{};
  final members = <ConstellationSectorMember>[];
  var skipped = 0;
  for (final target in selection.targets) {
    final graphId = constellationGraphNodeIdForTarget(target);
    final payload = controller.nodePayloadForId(graphId);
    final point = snapshot.resolvePosition(graphId);
    if (payload is! NodeDetails ||
        point == null ||
        !cubit.canDragNode(payload) ||
        cubit.anchorTargetForNode(payload) != target) {
      skipped++;
      continue;
    }
    targets[graphId] = target;
    members.add((id: graphId, position: (x: point.x, y: point.y)));
  }
  return (targets: targets, members: members, skipped: skipped);
}

/// The room each node takes in the sector: its marker and name (its layout
/// footprint when known) and a gap, the same in every direction.
double constellationSectorSpacing(
  BuildContext context,
  ConstellationCubit cubit,
  Iterable<ConstellationAnchorTarget> targets,
) {
  final tt = context.tt;
  final footprints = cubit.layoutFootprints;
  var extent = tt.graphLabelMaxWidthPerson;
  for (final target in targets) {
    if (target.kind == ConstellationAnchorTargetKind.beacon) {
      extent = math.max(extent, tt.graphLabelMaxWidthRequest);
    }
    if (footprints[target.id] case final footprint?) {
      extent = math.max(
        extent,
        math.max(
          footprint.left + footprint.right,
          footprint.top + footprint.bottom,
        ),
      );
    }
  }
  return extent + tt.rowGap;
}

/// Where the arranged nodes would go for the sector being edited, from where
/// they are drawn now (keyed by graph node id); null when there is no sector
/// or nothing to place.
ConstellationSectorLayout? constellationSectorPreview({
  required ConstellationMultiSelection selection,
  required ConstellationSectorItems items,
  required double minSpacing,
}) {
  final sector = selection.sector;
  if (sector == null || items.members.isEmpty) return null;
  return arrangeConstellationSector(
    centre: sector.centre,
    members: items.members,
    direction: sector.direction,
    span: sector.span,
    innerRadius: sector.radius,
    minSpacing: minSpacing,
    bounds: _envelope,
  );
}

/// The viewer's scene centre: where the field is arranged around.
Offset _viewerScenePoint(ConstellationCubit cubit) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(
    constellationGraphNodeIdForDomain(cubit.viewerId),
  );
  return point == null
      ? constellationCanvasCentrePoint().offset
      : Offset(point.x, point.y);
}

/// The sector a new arrangement starts with (#644).
///
/// Around the viewer when the viewer is on screen, as the field itself is
/// arranged around the viewer: pointed at the arranged nodes, its first ring
/// where the nearest of them is, so they move as little as possible. When the
/// viewer is off screen (the user is working on a far part of the field) a
/// full circle around the middle of the arranged nodes instead, so the
/// centre handle is on screen to grab.
ConstellationSectorDraft constellationSectorInitialDraft({
  required ConstellationCubit cubit,
  required ConstellationSectorItems items,
  required double minSpacing,
}) {
  final controller = cubit.graphController;
  final viewer = _viewerScenePoint(cubit);
  final size = controller.viewportSize;
  final points = [for (final member in items.members) member.position];
  final viewerOnScreen =
      size == null ||
      (Offset.zero & size)
          .deflate(kMinInteractiveDimension)
          .contains(controller.sceneToViewportLocal(viewer));
  if (viewerOnScreen || points.isEmpty) {
    var nearest = double.infinity;
    for (final point in points) {
      nearest = math.min(nearest, (point.offset - viewer).distance);
    }
    return ConstellationSectorDraft(
      centre: _clampToEnvelope(viewer.lPoint),
      radius: nearest.isFinite
          ? nearest.clamp(minSpacing, _maxSectorRadius)
          : minSpacing,
      direction: constellationSectorCentroidDirection(
        centre: viewer.lPoint,
        points: points,
      ),
    );
  }
  var x = 0.0;
  var y = 0.0;
  for (final point in points) {
    x += point.x;
    y += point.y;
  }
  return ConstellationSectorDraft(
    centre: _clampToEnvelope((x: x / points.length, y: y / points.length)),
    radius: minSpacing,
    direction: -math.pi / 2,
    span: kConstellationSectorMaxSpan,
  );
}

/// The parts of the sector a press can grab, in the order a press is tested
/// against them where their hit areas overlap.
enum _SectorGrip { radius, endEdge, startEdge, direction, centre, body }

Offset _unit(double angle) => Offset(math.cos(angle), math.sin(angle));

/// The resize cursor closest to a drag along [angle] (screen radians, y
/// down): the radius handle resizes along its own radius.
MouseCursor _radialResizeCursor(double angle) {
  // Fold to [0, π): a resize cursor points both ways.
  final a = angle % math.pi;
  const eighth = math.pi / 8;
  if (a < eighth || a >= 7 * eighth) return SystemMouseCursors.resizeLeftRight;
  if (a < 3 * eighth) return SystemMouseCursors.resizeUpLeftDownRight;
  if (a < 5 * eighth) return SystemMouseCursors.resizeUpDown;
  return SystemMouseCursors.resizeUpRightDownLeft;
}

/// The radians from [from] to [to], the short way round: in (-π, π].
double _turn(double from, double to) {
  var delta = (to - from) % (2 * math.pi);
  if (delta > math.pi) delta -= 2 * math.pi;
  return delta;
}

/// The sector as drawn now, in viewport coordinates. The shape follows the
/// scene (it grows and shrinks with the zoom); the handles keep their size
/// and are kept apart from each other at any zoom.
final class _SectorGeometry {
  factory _SectorGeometry({
    required GraphController<NodeDetails, EdgeDetails> controller,
    required ConstellationSectorDraft draft,
    required ConstellationSectorLayout? preview,
    required double minSpacing,
    required double hit,
    required double gap,
  }) {
    final scale = controller.cameraScale;
    final inner = math.max(draft.radius, minSpacing) * scale;
    final outermost = preview == null || preview.rings.isEmpty
        ? inner
        : preview.rings.last * scale;
    // The shape reaches half a spacing past the outer ring, so the nodes on
    // it sit inside.
    final reach = outermost + minSpacing * scale / 2;
    final radiusHandle = math.max(inner, hit / 2);
    // The outer handles sit past the shape and the radius handle, and far
    // enough out that a narrow sector does not stack them up.
    final apart = math.min(
      hit / (2 * math.sin(math.max(draft.span, 1e-3) / 4)),
      hit * 4,
    );
    return _SectorGeometry._(
      draft: draft,
      preview: preview,
      centre: controller.sceneToViewportLocal(draft.centre.offset),
      scale: scale,
      inner: inner,
      reach: reach,
      handleReach: math.max(math.max(reach + gap, radiusHandle + hit), apart),
      radiusHandle: radiusHandle,
      hit: hit,
    );
  }

  _SectorGeometry._({
    required this.draft,
    required this.preview,
    required this.centre,
    required this.scale,
    required this.inner,
    required this.reach,
    required this.handleReach,
    required this.radiusHandle,
    required this.hit,
  });

  final ConstellationSectorDraft draft;
  final ConstellationSectorLayout? preview;
  final Offset centre;
  final double scale;

  /// Viewport radius of the first ring.
  final double inner;

  /// Viewport radius of the drawn shape.
  final double reach;

  /// Viewport distance of the edge and direction handles from the centre.
  final double handleReach;

  /// Viewport distance of the radius handle from the centre: on the first
  /// ring, unless the zoom brings that ring onto the centre handle.
  final double radiusHandle;

  /// Diameter of a handle's hit area.
  final double hit;

  Offset handle(_SectorGrip grip) => switch (grip) {
    _SectorGrip.radius => centre + _unit(draft.start) * radiusHandle,
    _SectorGrip.startEdge => centre + _unit(draft.start) * handleReach,
    _SectorGrip.endEdge => centre + _unit(draft.end) * handleReach,
    _SectorGrip.direction => centre + _unit(draft.direction) * handleReach,
    _SectorGrip.centre || _SectorGrip.body => centre,
  };

  /// The handles drawn now: a full circle has one seam handle, the end.
  Iterable<_SectorGrip> get handles => [
    for (final grip in _SectorGrip.values)
      if (grip != _SectorGrip.body &&
          !(grip == _SectorGrip.startEdge && draft.isFullCircle))
        grip,
  ];

  /// What a press at [local] grabs; null when it is off the sector. Where
  /// hit areas overlap (a nearly full circle, a far zoom) the handle nearest
  /// the press wins, then the one listed first; a press inside the drawn
  /// shape but on no handle grabs the whole sector.
  _SectorGrip? gripAt(Offset local) {
    _SectorGrip? nearest;
    var best = double.infinity;
    for (final grip in handles) {
      final distance = (local - handle(grip)).distance;
      if (distance <= hit / 2 && distance < best) {
        nearest = grip;
        best = distance;
      }
    }
    if (nearest != null) return nearest;
    final offset = local - centre;
    if (offset.distance > reach) return null;
    if (draft.isFullCircle) return _SectorGrip.body;
    final along =
        (math.atan2(offset.dy, offset.dx) - draft.start) % (2 * math.pi);
    return along <= draft.span ? _SectorGrip.body : null;
  }
}

/// A grip being dragged: the sector and the pointer when it was grabbed,
/// and how far the pointer has turned around the centre since.
final class _GripDrag {
  _GripDrag({
    required this.grip,
    required this.draft,
    required this.downScene,
  }) : _lastAngle = _angleOf(downScene, draft);

  final _SectorGrip grip;
  final ConstellationSectorDraft draft;
  final Offset downScene;
  double _lastAngle;
  double _turned = 0;

  static double _angleOf(Offset scene, ConstellationSectorDraft draft) {
    final offset = scene - draft.centre.offset;
    return math.atan2(offset.dy, offset.dx);
  }

  /// The sector with the pointer now at [scene].
  ConstellationSectorDraft update(Offset scene, double minSpacing) {
    final angle = _angleOf(scene, draft);
    // Summed step by step, so a turn past the back of the circle keeps
    // going instead of jumping.
    _turned += _turn(_lastAngle, angle);
    _lastAngle = angle;
    final centre = draft.centre.offset;
    return switch (grip) {
      _SectorGrip.radius => draft.copyWith(
        radius:
            (math.max(draft.radius, minSpacing) +
                    (scene - centre).distance -
                    (downScene - centre).distance)
                .clamp(minSpacing, _maxSectorRadius),
      ),
      _SectorGrip.endEdge => draft.withEdgeMoved(
        ConstellationSectorEdge.end,
        _turned,
      ),
      _SectorGrip.startEdge => draft.withEdgeMoved(
        ConstellationSectorEdge.start,
        _turned,
      ),
      _SectorGrip.direction => draft.copyWith(
        direction: draft.direction + _turned,
      ),
      _SectorGrip.centre || _SectorGrip.body => draft.copyWith(
        centre: _clampToEnvelope((centre + scene - downScene).lPoint),
      ),
    };
  }
}

/// Editing «Arrange in a sector» on the map, as in a graphics editor (#644):
/// drag the centre handle or the sector itself to move it anywhere, the dot
/// where the first ring meets the start edge to change the radius, the dots
/// at the two outer corners to move either edge (direction and width at
/// once, up to the whole circle) and the one in the middle of the outer arc
/// to turn it. Ghosts show where every node will go.
///
/// The handles are the composer's (`ConstellationComposerHandle`): drawn at a
/// fixed size whatever the zoom, a press inside one claims the gesture at
/// once. A press off the sector moves the map with one finger or the mouse;
/// two fingers pan and pinch and the wheel zooms anywhere.
class _SectorEditor extends StatefulWidget {
  const _SectorEditor({required this.cubit, required this.selection});

  final ConstellationCubit cubit;
  final ConstellationSelectionCubit selection;

  @override
  State<_SectorEditor> createState() => _SectorEditorState();
}

class _SectorEditorState extends State<_SectorEditor> {
  late final _camera = _Camera(widget.cubit.graphController);
  final _session = _Session();

  /// What the first pointer of the session landed on.
  _SectorGrip? _pressed;
  _GripDrag? _drag;

  double get _hit =>
      math.max(context.tt.buttonHeight, kMinInteractiveDimension);

  ({
    ConstellationSectorItems items,
    double minSpacing,
    ConstellationSectorLayout? preview,
    _SectorGeometry? geometry,
  })
  _frame(BuildContext context) {
    final cubit = widget.cubit;
    final state = widget.selection.state;
    final items = constellationSectorItems(cubit, state);
    final minSpacing = constellationSectorSpacing(
      context,
      cubit,
      items.targets.values,
    );
    final preview = constellationSectorPreview(
      selection: state,
      items: items,
      minSpacing: minSpacing,
    );
    final sector = state.sector;
    return (
      items: items,
      minSpacing: minSpacing,
      preview: preview,
      geometry: sector == null
          ? null
          : _SectorGeometry(
              controller: cubit.graphController,
              draft: sector,
              preview: preview,
              minSpacing: minSpacing,
              hit: _hit,
              gap: context.tt.rowGap,
            ),
    );
  }

  void _down(PointerEvent event) {
    final first = !_session.active;
    _session.down(event);
    if (first) {
      _pressed = _frame(context).geometry?.gripAt(event.localPosition);
      _drag = null;
    } else {
      // A second finger: the rest of the session moves the map.
      _drag = null;
    }
  }

  void _onStart(ScaleStartDetails details) {
    final sector = widget.selection.state.sector;
    final pressed = _pressed;
    if (_session.multi ||
        details.pointerCount > 1 ||
        pressed == null ||
        sector == null) {
      _drag = null;
      _camera.start(details);
      return;
    }
    _drag = _GripDrag(
      grip: pressed,
      draft: sector,
      downScene: widget.cubit.graphController.viewportLocalToScene(
        details.localFocalPoint,
      ),
    );
  }

  void _onUpdate(ScaleUpdateDetails details) {
    final drag = _drag;
    if (_session.multi || details.pointerCount > 1 || drag == null) {
      _drag = null;
      _camera.update(details);
      return;
    }
    final minSpacing = _frame(context).minSpacing;
    widget.selection.editSector(
      drag.update(
        widget.cubit.graphController.viewportLocalToScene(
          details.localFocalPoint,
        ),
        minSpacing,
      ),
    );
  }

  void _onEnd(ScaleEndDetails _) {
    _camera.end();
    _drag = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.cubit.graphController;
    return Listener(
      onPointerDown: _down,
      onPointerUp: _session.up,
      onPointerCancel: _session.up,
      onPointerPanZoomStart: _down,
      onPointerPanZoomEnd: _session.up,
      onPointerSignal: _camera.wheel,
      child: GestureDetector(
        key: const Key('constellation.selection.sector_editor'),
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onStart,
        onScaleUpdate: _onUpdate,
        onScaleEnd: _onEnd,
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, controller.cameraRevision]),
          builder: (context, _) {
            final frame = _frame(context);
            final geometry = frame.geometry;
            if (geometry == null) return const SizedBox.expand();
            return _SectorView(
              cubit: widget.cubit,
              geometry: geometry,
              items: frame.items,
            );
          },
        ),
      ),
    );
  }
}

/// The sector, its ghosts and its handles.
class _SectorView extends StatelessWidget {
  const _SectorView({
    required this.cubit,
    required this.geometry,
    required this.items,
  });

  final ConstellationCubit cubit;
  final _SectorGeometry geometry;
  final ConstellationSectorItems items;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final controller = cubit.graphController;
    final snapshot = controller.renderSnapshot;
    final preview = geometry.preview;
    final ghosts = <_Ghost>[];
    if (preview != null) {
      for (final MapEntry(key: graphId, value: target)
          in preview.targets.entries) {
        final node = snapshot.topology.nodesById[graphId];
        final now = snapshot.resolvePosition(graphId);
        if (node == null || now == null) continue;
        ghosts.add((
          from: controller.sceneToViewportLocal(Offset(now.x, now.y)),
          to: controller.sceneToViewportLocal(target.offset),
          radius:
              math.max(node.size.width, node.size.height) * geometry.scale / 2,
          outside: preview.outside.contains(graphId),
        ));
      }
    }
    Widget handle(
      _SectorGrip grip,
      String key,
      String label,
      MouseCursor cursor, {
      IconData? icon,
      double iconTurn = 0,
    }) {
      final at = geometry.handle(grip);
      final hit = geometry.hit;
      return Positioned(
        key: Key('constellation.sector.$key'),
        left: at.dx - hit / 2,
        top: at.dy - hit / 2,
        width: hit,
        height: hit,
        // Hover affordance only: presses reach the editor's own hit test.
        child: MouseRegion(
          cursor: cursor,
          child: IgnorePointer(
            child: Semantics(
              label: label,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.onPrimary,
                      width: TenturaSpacing.focusRing,
                    ),
                  ),
                  child: SizedBox.square(
                    dimension: tt.iconSize,
                    child: icon == null
                        ? null
                        : Transform.rotate(
                            angle: iconTurn,
                            child: Icon(
                              icon,
                              size: tt.iconSize - tt.tightGap,
                              color: scheme.onPrimary,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          key: const Key('constellation.sector.shape'),
          painter: _SectorPainter(
            geometry: geometry,
            ghosts: ghosts,
            color: scheme.primary,
            guide: scheme.outline,
            error: scheme.error,
            stroke: tt.tightGap / 2,
          ),
        ),
        handle(
          _SectorGrip.centre,
          'centre',
          l10n.constellationArrangeCentre,
          SystemMouseCursors.move,
          icon: Icons.open_with,
        ),
        handle(
          _SectorGrip.direction,
          'direction',
          l10n.constellationArrangeDirection,
          SystemMouseCursors.grab,
          icon: Icons.rotate_right,
        ),
        if (!geometry.draft.isFullCircle)
          handle(
            _SectorGrip.startEdge,
            'start',
            l10n.constellationArrangeStartEdge,
            SystemMouseCursors.grab,
          ),
        handle(
          _SectorGrip.endEdge,
          'end',
          l10n.constellationArrangeEndEdge,
          SystemMouseCursors.grab,
        ),
        // Arrows along the radius, so it reads as «drag in or out» and not as
        // another corner of the sector.
        handle(
          _SectorGrip.radius,
          'radius',
          l10n.constellationArrangeRadius,
          _radialResizeCursor(geometry.draft.start),
          icon: Icons.unfold_more,
          iconTurn: geometry.draft.start + math.pi / 2,
        ),
      ],
    );
  }
}

typedef _Ghost = ({Offset from, Offset to, double radius, bool outside});

class _SectorPainter extends CustomPainter {
  const _SectorPainter({
    required this.geometry,
    required this.ghosts,
    required this.color,
    required this.guide,
    required this.error,
    required this.stroke,
  });

  final _SectorGeometry geometry;
  final List<_Ghost> ghosts;
  final Color color;
  final Color guide;
  final Color error;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final draft = geometry.draft;
    final centre = geometry.centre;
    final full = draft.isFullCircle;
    final reach = geometry.reach;
    final shape = full
        ? (Path()..addOval(Rect.fromCircle(center: centre, radius: reach)))
        : (Path()
            ..moveTo(centre.dx, centre.dy)
            ..arcTo(
              Rect.fromCircle(center: centre, radius: reach),
              draft.start,
              draft.span,
              false,
            )
            ..close());
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas
      ..drawPath(shape, Paint()..color = color.withValues(alpha: 0.06))
      ..drawPath(shape, outline);
    // The outer handles keep their distance at any zoom; a thin line ties
    // each to the shape when they sit past it.
    if (geometry.handleReach > reach) {
      final tie = Paint()
        ..color = color
        ..strokeWidth = stroke / 2;
      for (final angle in [
        draft.direction,
        draft.end,
        if (!full) draft.start,
      ]) {
        canvas.drawLine(
          centre + _unit(angle) * reach,
          centre + _unit(angle) * geometry.handleReach,
          tie,
        );
      }
    }
    // The rings the nodes go on, faintly; the first one, which the radius
    // handle drags, in full.
    final rings = Paint()
      ..color = guide.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke / 2;
    for (final radius in geometry.preview?.rings ?? const <double>[]) {
      _arc(canvas, centre, radius * geometry.scale, draft, rings);
    }
    _arc(
      canvas,
      centre,
      geometry.inner,
      draft,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2,
    );
    final line = Paint()
      ..color = guide
      ..strokeWidth = stroke;
    for (final ghost in ghosts) {
      final tint = ghost.outside ? error : color;
      canvas
        ..drawLine(ghost.from, ghost.to, line)
        ..drawCircle(
          ghost.to,
          ghost.radius,
          Paint()..color = tint.withValues(alpha: 0.16),
        )
        ..drawCircle(
          ghost.to,
          ghost.radius,
          Paint()
            ..color = tint
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 2,
        );
    }
  }

  static void _arc(
    Canvas canvas,
    Offset centre,
    double radius,
    ConstellationSectorDraft draft,
    Paint paint,
  ) {
    final rect = Rect.fromCircle(center: centre, radius: radius);
    if (draft.isFullCircle) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawArc(rect, draft.start, draft.span, false, paint);
    }
  }

  @override
  bool shouldRepaint(_SectorPainter old) => true;
}

/// Bottom bar of the selection: the count, «Arrange in a sector» and
/// «Clear selection»; while editing a sector, its controls.
class ConstellationSelectionBar extends StatelessWidget {
  const ConstellationSelectionBar({required this.cubit, super.key});

  final ConstellationCubit cubit;

  /// One turn of the rotate buttons.
  static const rotateStep = math.pi / 12;

  void _beginSector(
    BuildContext context,
    ConstellationSelectionCubit selection,
  ) {
    final items = constellationSectorItems(cubit, selection.state);
    selection.beginSector(
      constellationSectorInitialDraft(
        cubit: cubit,
        items: items,
        minSpacing: constellationSectorSpacing(
          context,
          cubit,
          items.targets.values,
        ),
      ),
    );
  }

  ({ConstellationSectorItems items, ConstellationSectorLayout? preview})
  _preview(BuildContext context, ConstellationMultiSelection state) {
    final items = constellationSectorItems(cubit, state);
    return (
      items: items,
      preview: constellationSectorPreview(
        selection: state,
        items: items,
        minSpacing: constellationSectorSpacing(
          context,
          cubit,
          items.targets.values,
        ),
      ),
    );
  }

  void _apply(BuildContext context, ConstellationSelectionCubit selection) {
    final (:items, :preview) = _preview(context, selection.state);
    if (preview == null) {
      selection.cancelSector();
      return;
    }
    // Places off the field are allowed: the cubit puts those nodes at the
    // edge of the field, and the bar has said so.
    if (cubit.placeArrangement({
      for (final MapEntry(key: graphId, value: point)
          in preview.targets.entries)
        ?items.targets[graphId]: point.offset,
    })) {
      selection.cancelSector();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = maybeConstellationSelection(context);
    if (selection == null) return const SizedBox.shrink();
    // A change of account drops the field (a reload keeps it): the new
    // account starts with nothing selected.
    return BlocListener<ConstellationCubit, ConstellationState>(
      bloc: cubit,
      listenWhen: (previous, current) =>
          previous.field != null && current.field == null,
      listener: (_, _) => selection.clear(),
      child:
          BlocBuilder<ConstellationSelectionCubit, ConstellationMultiSelection>(
            bloc: selection,
            builder: (context, state) {
              if (!state.isActive || cubit.state.isComposing) {
                return const SizedBox.shrink();
              }
              final tt = context.tt;
              return Padding(
                padding: EdgeInsets.all(tt.rowGap),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: TenturaSpacing.listPaneWidth,
                    ),
                    child: Material(
                      key: const Key('constellation.selection.bar'),
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tt.cardRadius),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: tt.screenHPadding,
                          vertical: tt.tightGap,
                        ),
                        child: state.sector == null
                            ? _selectionRow(context, selection, state)
                            : _sectorControls(context, selection, state),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }

  Widget _selectionRow(
    BuildContext context,
    ConstellationSelectionCubit selection,
    ConstellationMultiSelection state,
  ) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final reason = state.count < 2
        ? l10n.constellationArrangeNeedsTwo
        : state.count > kConstellationSectorMaxItems
        ? l10n.constellationArrangeTooMany(kConstellationSectorMaxItems)
        : null;
    final arrange = Tooltip(
      message: reason ?? l10n.constellationArrangeSector,
      child: TextButton.icon(
        key: const Key('constellation.selection.arrange'),
        onPressed: reason == null
            ? () => _beginSector(context, selection)
            : null,
        icon: const Icon(Icons.radar),
        label: Text(
          l10n.constellationArrangeSector,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  state.isEmpty
                      ? l10n.constellationSelectionHint
                      : l10n.constellationSelectionCount(state.count),
                  key: const Key('constellation.selection.count'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            IconButton(
              key: const Key('constellation.selection.clear'),
              tooltip: l10n.constellationSelectionClear,
              onPressed: selection.clear,
              icon: const Icon(Icons.deselect),
            ),
            if (state.selecting)
              IconButton(
                key: const Key('constellation.selection.done'),
                tooltip: l10n.constellationSelectionDone,
                onPressed: () => selection.setSelecting(false),
                icon: const Icon(Icons.check),
              ),
          ],
        ),
        if (!state.isEmpty)
          Align(alignment: AlignmentDirectional.centerEnd, child: arrange),
      ],
    );
  }

  Widget _sectorControls(
    BuildContext context,
    ConstellationSelectionCubit selection,
    ConstellationMultiSelection state,
  ) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final sector = state.sector!;
    final degrees = (sector.span * 180 / math.pi).round();
    final (:items, :preview) = _preview(context, state);
    final offField = preview != null && preview.outside.isNotEmpty;
    final notes = [
      l10n.constellationArrangeEditHint,
      if (items.skipped > 0) l10n.constellationArrangeSkipped(items.skipped),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: context.tt.tightGap),
          child: Text(
            notes.join(' '),
            key: const Key('constellation.selection.sector_hint'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (offField)
          Padding(
            padding: EdgeInsets.only(top: context.tt.tightGap),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.constellationArrangeOffField,
                key: const Key('constellation.selection.sector_off_field'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        Row(
          children: [
            IconButton(
              key: const Key('constellation.selection.rotate_left'),
              tooltip: l10n.constellationArrangeRotateLeft,
              onPressed: () => selection.aimSector(
                direction: sector.direction - rotateStep,
              ),
              icon: const Icon(Icons.rotate_left),
            ),
            Expanded(
              child: Slider(
                key: const Key('constellation.selection.width'),
                value: sector.span,
                min: kConstellationSectorMinSpan,
                max: kConstellationSectorMaxSpan,
                divisions: 23,
                label: '$degrees°',
                semanticFormatterCallback: (_) =>
                    '${l10n.constellationArrangeWidth}: $degrees°',
                onChanged: (value) => selection.aimSector(span: value),
              ),
            ),
            IconButton(
              key: const Key('constellation.selection.rotate_right'),
              tooltip: l10n.constellationArrangeRotateRight,
              onPressed: () => selection.aimSector(
                direction: sector.direction + rotateStep,
              ),
              icon: const Icon(Icons.rotate_right),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('constellation.selection.sector_cancel'),
              onPressed: selection.cancelSector,
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            SizedBox(width: context.tt.rowGap),
            FilledButton(
              key: const Key('constellation.selection.sector_apply'),
              onPressed: preview == null
                  ? null
                  : () => _apply(context, selection),
              child: Text(l10n.constellationArrangeApply),
            ),
          ],
        ),
      ],
    );
  }
}
