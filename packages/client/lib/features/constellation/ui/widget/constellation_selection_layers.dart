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
/// nodes, the Shift-drag box and, while aiming, the sector preview.
class ConstellationSelectionLayers extends StatelessWidget {
  const ConstellationSelectionLayers({required this.cubit, super.key});

  final ConstellationCubit cubit;

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
            _BoxSelect(cubit: cubit, selection: selection)
          else
            _SectorAim(cubit: cubit, selection: selection),
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

  Offset? _focal;
  double _scale = 1;
  int _pointers = 0;

  /// The InteractiveViewer wheel rate.
  static const _wheelRate = 200.0;

  void start(ScaleStartDetails details) {
    _focal = details.localFocalPoint;
    _scale = 1;
    _pointers = details.pointerCount;
  }

  void update(ScaleUpdateDetails details) {
    final focal = _focal;
    // A finger joining or leaving re-bases the gesture instead of jumping.
    if (focal == null || details.pointerCount != _pointers) {
      _focal = details.localFocalPoint;
      _scale = details.scale;
      _pointers = details.pointerCount;
      return;
    }
    if (_scale > 0 && details.scale > 0 && details.scale != _scale) {
      zoomAround(details.localFocalPoint, details.scale / _scale);
    }
    panBy(details.localFocalPoint - focal);
    _focal = details.localFocalPoint;
    _scale = details.scale;
  }

  void end() => _focal = null;

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

/// Rubber-band (box) selection (#642), the main way to pick several nodes.
///
/// It takes a pointer that goes down on empty map while the select tool is
/// on, or anywhere off a node while Shift is held; everything else (a tap or
/// a drag on a node, a plain drag with the tool off) reaches the map as
/// before. One finger or the mouse draws the box; a second finger turns the
/// gesture into a pan and pinch of the map, and the wheel zooms.
///
/// On release: with Shift the nodes in the box are added, with Ctrl/Cmd they
/// are toggled; otherwise a mouse box replaces the selection and a touch box
/// adds to it (a touch screen has no modifier to add with).
class _BoxSelect extends StatefulWidget {
  const _BoxSelect({required this.cubit, required this.selection});

  final ConstellationCubit cubit;
  final ConstellationSelectionCubit selection;

  @override
  State<_BoxSelect> createState() => _BoxSelectState();
}

class _BoxSelectState extends State<_BoxSelect> {
  late final _camera = _Camera(widget.cubit.graphController);
  final _pointers = <int>{};
  PointerDeviceKind? _kind;
  Offset? _start;
  Offset? _end;
  bool _moving = false;

  bool _accepts(Offset local) {
    // The rest of a gesture this layer started stays with it.
    if (_pointers.isNotEmpty) return true;
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
    return !_onNode(widget.cubit, local);
  }

  void _down(PointerEvent event) {
    _pointers.add(event.pointer);
    _kind ??= event.kind;
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) _kind = null;
  }

  void _clearBox() {
    if (_start == null && _end == null) return;
    setState(() {
      _start = null;
      _end = null;
    });
  }

  void _onStart(ScaleStartDetails details) {
    _moving = details.pointerCount > 1;
    if (_moving) {
      _camera.start(details);
      return;
    }
    setState(() {
      _start = details.localFocalPoint;
      _end = details.localFocalPoint;
    });
  }

  void _onUpdate(ScaleUpdateDetails details) {
    if (!_moving && details.pointerCount > 1) {
      // A second finger: this is a pan or pinch, not a box.
      _moving = true;
      _clearBox();
      _camera.start(
        ScaleStartDetails(
          localFocalPoint: details.localFocalPoint,
          pointerCount: details.pointerCount,
        ),
      );
      return;
    }
    if (_moving) {
      _camera.update(details);
      return;
    }
    setState(() => _end = details.localFocalPoint);
  }

  void _onEnd(ScaleEndDetails _) {
    _camera.end();
    final start = _start;
    final end = _end;
    final kind = _kind;
    _clearBox();
    if (_moving || start == null || end == null) {
      _moving = false;
      return;
    }
    final rect = Rect.fromPoints(start, end);
    if (rect.longestSide < kTouchSlop) return;
    final keyboard = HardwareKeyboard.instance;
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
        onPointerUp: _up,
        onPointerCancel: _up,
        onPointerPanZoomStart: _down,
        onPointerPanZoomEnd: _up,
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

/// The scene point the field is arranged around: the viewer.
Offset get _sceneCentre => constellationCanvasCentrePoint().offset;

/// Where the selected people would go for the sector being aimed, from
/// where they are drawn now; null when fewer than two are on the map.
ConstellationSectorLayout? constellationSectorPreview({
  required ConstellationCubit cubit,
  required ConstellationMultiSelection selection,
  required double minSpacing,
}) {
  final sector = selection.sector;
  if (sector == null) return null;
  final members = constellationSelectedPeopleOnMap(cubit, selection);
  if (members.length < 2) return null;
  return arrangeConstellationSector(
    centre: _sceneCentre.lPoint,
    members: members,
    direction: sector.direction,
    span: sector.span,
    minSpacing: minSpacing,
    minRadius: kConstellationRingUnitPixels,
    maxAxisOffset:
        kConstellationCoordinateMaxUnits * kConstellationRingUnitPixels,
  );
}

/// The selected people drawn on the map now, with their scene centres.
List<ConstellationSectorMember> constellationSelectedPeopleOnMap(
  ConstellationCubit cubit,
  ConstellationMultiSelection selection,
) {
  final snapshot = cubit.graphController.renderSnapshot;
  return [
    for (final id in selection.personIds)
      if (snapshot.resolvePosition(
            constellationGraphNodeIdForTarget(
              ConstellationAnchorTarget.person(id),
            ),
          )
          case final point?)
        (id: id, position: (x: point.x, y: point.y)),
  ];
}

/// The direction the sector first points: towards the selected people.
double constellationSectorInitialDirection(
  ConstellationCubit cubit,
  ConstellationMultiSelection selection,
) => constellationSectorCentroidDirection(
  centre: _sceneCentre.lPoint,
  points: [
    for (final member in constellationSelectedPeopleOnMap(cubit, selection))
      member.position,
  ],
);

/// Neighbours on the arc keep a person's marker and name apart.
double constellationSectorMinSpacing(BuildContext context) =>
    context.tt.graphLabelMaxWidthPerson + context.tt.rowGap;

/// While aiming: one finger (or the mouse) dragged or tapped anywhere on the
/// map points the sector from the viewer towards the pointer, over a preview
/// of where people will go; two fingers still pan and pinch, the wheel zooms.
class _SectorAim extends StatefulWidget {
  const _SectorAim({required this.cubit, required this.selection});

  final ConstellationCubit cubit;
  final ConstellationSelectionCubit selection;

  @override
  State<_SectorAim> createState() => _SectorAimState();
}

class _SectorAimState extends State<_SectorAim> {
  late final _camera = _Camera(widget.cubit.graphController);
  bool _moving = false;

  void _aimAt(Offset local) {
    final centre = widget.cubit.graphController.sceneToViewportLocal(
      _sceneCentre,
    );
    final delta = local - centre;
    if (delta.distanceSquared < 1) return;
    widget.selection.aimSector(direction: math.atan2(delta.dy, delta.dx));
  }

  void _onStart(ScaleStartDetails details) {
    _moving = details.pointerCount > 1;
    if (_moving) {
      _camera.start(details);
    } else {
      _aimAt(details.localFocalPoint);
    }
  }

  void _onUpdate(ScaleUpdateDetails details) {
    if (!_moving && details.pointerCount > 1) {
      _moving = true;
      _camera.start(
        ScaleStartDetails(
          localFocalPoint: details.localFocalPoint,
          pointerCount: details.pointerCount,
        ),
      );
      return;
    }
    if (_moving) {
      _camera.update(details);
    } else {
      _aimAt(details.localFocalPoint);
    }
  }

  void _onEnd(ScaleEndDetails _) {
    _camera.end();
    _moving = false;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = widget.cubit;
    final selection = widget.selection;
    final controller = cubit.graphController;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final minSpacing = constellationSectorMinSpacing(context);
    return Listener(
      onPointerSignal: _camera.wheel,
      child: GestureDetector(
        key: const Key('constellation.selection.sector_aim'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _aimAt(details.localPosition),
        onScaleStart: _onStart,
        onScaleUpdate: _onUpdate,
        onScaleEnd: _onEnd,
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, controller.cameraRevision]),
          builder: (context, _) {
            final preview = constellationSectorPreview(
              cubit: cubit,
              selection: selection.state,
              minSpacing: minSpacing,
            );
            if (preview == null) return const SizedBox.expand();
            final snapshot = controller.renderSnapshot;
            final scale = controller.cameraScale;
            final ghosts = <(Offset, Offset, double)>[];
            var reach = 0.0;
            final centre = controller.sceneToViewportLocal(_sceneCentre);
            for (final MapEntry(key: id, value: target)
                in preview.targets.entries) {
              final graphId = constellationGraphNodeIdForTarget(
                ConstellationAnchorTarget.person(id),
              );
              final node = snapshot.topology.nodesById[graphId];
              final now = snapshot.resolvePosition(graphId);
              if (node == null || now == null) continue;
              final radius = node.size.width * scale / 2;
              final to = controller.sceneToViewportLocal(target.offset);
              ghosts.add((
                controller.sceneToViewportLocal(Offset(now.x, now.y)),
                to,
                radius,
              ));
              reach = math.max(reach, (to - centre).distance + radius);
            }
            return CustomPaint(
              size: Size.infinite,
              painter: _SectorPainter(
                centre: centre,
                reach: reach + tt.rowGap,
                start: preview.start,
                sweep: preview.sweep,
                ghosts: ghosts,
                color: scheme.primary,
                trail: scheme.outline,
                stroke: tt.tightGap / 2,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectorPainter extends CustomPainter {
  const _SectorPainter({
    required this.centre,
    required this.reach,
    required this.start,
    required this.sweep,
    required this.ghosts,
    required this.color,
    required this.trail,
    required this.stroke,
  });

  final Offset centre;
  final double reach;
  final double start;
  final double sweep;
  final List<(Offset, Offset, double)> ghosts;
  final Color color;
  final Color trail;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: centre, radius: reach);
    final wedge = Path()
      ..moveTo(centre.dx, centre.dy)
      ..arcTo(rect, start, sweep, false)
      ..close();
    canvas
      ..drawPath(wedge, Paint()..color = color.withValues(alpha: 0.08))
      ..drawPath(
        wedge,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    final line = Paint()
      ..color = trail
      ..strokeWidth = stroke;
    final fill = Paint()..color = color.withValues(alpha: 0.16);
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 2;
    for (final (from, to, radius) in ghosts) {
      canvas
        ..drawLine(from, to, line)
        ..drawCircle(to, radius, fill)
        ..drawCircle(to, radius, ring);
    }
  }

  @override
  bool shouldRepaint(_SectorPainter old) => true;
}

/// Bottom bar of the selection: the count, «Arrange in a sector» and
/// «Clear selection»; while aiming, the sector controls.
class ConstellationSelectionBar extends StatelessWidget {
  const ConstellationSelectionBar({required this.cubit, super.key});

  final ConstellationCubit cubit;

  /// One turn of the rotate buttons.
  static const rotateStep = math.pi / 12;

  void _beginSector(ConstellationSelectionCubit selection) =>
      selection.beginSector(
        direction: constellationSectorInitialDirection(cubit, selection.state),
      );

  void _apply(BuildContext context, ConstellationSelectionCubit selection) {
    final preview = constellationSectorPreview(
      cubit: cubit,
      selection: selection.state,
      minSpacing: constellationSectorMinSpacing(context),
    );
    if (preview == null) {
      selection.cancelSector();
      return;
    }
    if (cubit.placePeople({
      for (final MapEntry(key: id, value: point) in preview.targets.entries)
        id: point.offset,
    })) {
      selection.cancelSector();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = maybeConstellationSelection(context);
    if (selection == null) return const SizedBox.shrink();
    return BlocBuilder<
      ConstellationSelectionCubit,
      ConstellationMultiSelection
    >(
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
    );
  }

  Widget _selectionRow(
    BuildContext context,
    ConstellationSelectionCubit selection,
    ConstellationMultiSelection state,
  ) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final people = state.personIds.length;
    final reason = people < 2
        ? l10n.constellationArrangeNeedsPeople
        : people > kConstellationSectorMaxPeople
        ? l10n.constellationArrangeTooMany(kConstellationSectorMaxPeople)
        : null;
    final arrange = Tooltip(
      message: reason ?? l10n.constellationArrangeSector,
      child: TextButton.icon(
        key: const Key('constellation.selection.arrange'),
        onPressed: reason == null ? () => _beginSector(selection) : null,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: context.tt.tightGap),
          child: Text(
            l10n.constellationArrangeAimHint,
            style: theme.textTheme.bodyMedium,
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
                divisions: 11,
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
              onPressed: () => _apply(context, selection),
              child: Text(l10n.constellationArrangeApply),
            ),
          ],
        ),
      ],
    );
  }
}
