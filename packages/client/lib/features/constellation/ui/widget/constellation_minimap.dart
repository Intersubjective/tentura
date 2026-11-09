import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_layout.dart';
import '../../domain/constellation_minimap.dart';
import '../../domain/layout/layout_geometry.dart';

const _personDotRadius = 2.0;
const _viewerDotRadius = 3.5;
const _personNodePrefix = 'fp:';
const _beaconNodePrefix = 'fr:';
const _minimapFrameStrokeWidth = 2.0;
const _tapSlop = 8.0;

bool _minimapNodeId(String id) =>
    id.startsWith(_personNodePrefix) || id.startsWith(_beaconNodePrefix);

/// Scene footprints of every Field person and Request/Post the minimap draws.
Iterable<LRect> constellationMinimapNodeBounds(
  GraphController<NodeDetails, EdgeDetails> controller, {
  Map<String, ConstellationFootprint>? layoutFootprints,
}) {
  final snapshot = controller.renderSnapshot;
  final out = <LRect>[];
  for (final entry in snapshot.topology.nodesById.entries) {
    final id = entry.key;
    if (!_minimapNodeId(id)) continue;
    final point = snapshot.resolveTargetPosition(id);
    if (point == null) continue;
    final sceneNode = entry.value;
    final placed = constellationPlacedNodeBounds(
      centre: (x: point.x, y: point.y),
      footprint: layoutFootprints?[id],
      size: (
        width: sceneNode.size.width,
        height: sceneNode.size.height,
      ),
    );
    out.add((
      left: placed.left,
      top: placed.top,
      right: placed.right,
      bottom: placed.bottom,
    ));
  }
  return out;
}

LRect? constellationMinimapViewportWorld(
  GraphController<NodeDetails, EdgeDetails> controller, {
  EdgeInsets viewportInsets = EdgeInsets.zero,
}) {
  final size = controller.viewportSize;
  if (size == null) return null;
  final topLeft = controller.viewportLocalToScene(
    Offset(viewportInsets.left, viewportInsets.top),
  );
  final bottomRight = controller.viewportLocalToScene(
    Offset(
      size.width - viewportInsets.right,
      size.height - viewportInsets.bottom,
    ),
  );
  return (
    left: topLeft.dx,
    top: topLeft.dy,
    right: bottomRight.dx,
    bottom: bottomRight.dy,
  );
}

/// A collapsible overview of the whole Field: everyone as a dot and a frame
/// for the part the camera shows. A tap moves the camera there, same zoom.
class ConstellationMinimap extends StatefulWidget {
  const ConstellationMinimap({
    required this.controller,
    required this.viewerGraphId,
    required this.expanded,
    this.viewportInsets = EdgeInsets.zero,
    super.key,
  });

  final GraphController<NodeDetails, EdgeDetails> controller;

  /// Graph id for the viewer's person node (`fp:<viewerId>`).
  final String viewerGraphId;

  /// Kept by the owner so the choice survives zooming to the close level.
  final ValueNotifier<bool> expanded;

  /// Same insets the Field camera uses when fitting or framing nodes.
  final EdgeInsets viewportInsets;

  @override
  State<ConstellationMinimap> createState() => _ConstellationMinimapState();
}

class _ConstellationMinimapState extends State<ConstellationMinimap> {
  late Listenable _changes;
  Object? _projectionSnapshot;
  ConstellationMinimapProjection? _projection;
  List<Offset> _people = const [];
  List<Offset> _beacons = const [];
  Offset? _viewer;
  Offset? _panLastLocal;
  double _panAccum = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(ConstellationMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.expanded != widget.expanded) {
      _bind();
    }
  }

  void _bind() {
    _projectionSnapshot = null;
    _changes = Listenable.merge([
      widget.expanded,
      widget.controller,
      widget.controller.cameraRevision,
    ]);
  }

  /// People change with the scene, not with the camera: the projection is
  /// rebuilt only when the scene snapshot is a new one.
  ConstellationMinimapProjection _projectionOfScene() {
    final controller = widget.controller;
    final snapshot = controller.renderSnapshot;
    final cached = _projection;
    if (cached != null && identical(snapshot, _projectionSnapshot)) {
      return cached;
    }
    final people = <Offset>[];
    final beacons = <Offset>[];
    Offset? viewer;
    for (final id in snapshot.topology.nodesById.keys) {
      final at = controller.getPositionOrNullForId(id);
      if (at == null) continue;
      if (id == widget.viewerGraphId) {
        viewer = at;
        continue;
      }
      if (id.startsWith(_personNodePrefix)) {
        people.add(at);
      } else if (id.startsWith(_beaconNodePrefix)) {
        beacons.add(at);
      }
    }
    _people = people;
    _beacons = beacons;
    _viewer = viewer;
    _projectionSnapshot = snapshot;
    return _projection = ConstellationMinimapProjection.fromPoints([
      for (final p in [...people, ...beacons, ?viewer]) (x: p.dx, y: p.dy),
    ]);
  }

  LRect? _viewportWorld() => constellationMinimapViewportWorld(
    widget.controller,
    viewportInsets: widget.viewportInsets,
  );

  Offset _viewportCentreWorld() {
    final controller = widget.controller;
    final size = controller.viewportSize!;
    final i = widget.viewportInsets;
    final centre = Offset(
      i.left + (size.width - i.horizontal) / 2,
      i.top + (size.height - i.vertical) / 2,
    );
    return controller.viewportLocalToScene(centre);
  }

  void _moveCameraTo(ConstellationMinimapProjection projection, Offset tap) {
    final world = projection.minimapToWorld((x: tap.dx, y: tap.dy));
    widget.controller.jumpToPosition(
      Offset(world.x, world.y),
      viewportInsets: widget.viewportInsets,
    );
  }

  bool _hitFrame(LRect frame, Offset local) =>
      local.dx >= frame.left &&
      local.dx <= frame.right &&
      local.dy >= frame.top &&
      local.dy <= frame.bottom;

  void _onPanStart(DragStartDetails details) {
    _panLastLocal = details.localPosition;
    _panAccum = 0;
    final projection = _projectionOfScene();
    final viewport = _viewportWorld();
    if (viewport == null) return;
    final frame = projection.frameOf(viewport);
    if (!_hitFrame(frame, details.localPosition)) {
      _moveCameraTo(projection, details.localPosition);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _panAccum += details.delta.distance;
    final last = _panLastLocal;
    if (last == null) {
      _panLastLocal = details.localPosition;
      return;
    }
    final delta = details.localPosition - last;
    _panLastLocal = details.localPosition;
    if (_panAccum < _tapSlop && delta.distanceSquared < 1) {
      return;
    }
    final projection = _projectionOfScene();
    final world = projection.minimapDeltaToWorld((x: delta.dx, y: delta.dy));
    final centre = _viewportCentreWorld();
    widget.controller.jumpToPosition(
      Offset(centre.dx + world.x, centre.dy + world.y),
      viewportInsets: widget.viewportInsets,
    );
  }

  void _onPanEnd(DragEndDetails details) {
    _panLastLocal = null;
    _panAccum = 0;
  }

  void _onTapUp(TapUpDetails details) {
    if (_panAccum >= _tapSlop) {
      return;
    }
    _moveCameraTo(_projectionOfScene(), details.localPosition);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        final expanded = widget.expanded.value;
        final projection = _projectionOfScene();
        final viewport = _viewportWorld();
        final frame = viewport == null ? null : projection.frameOf(viewport);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton.filledTonal(
              key: const Key('constellation.minimap.toggle'),
              tooltip: expanded
                  ? l10n.constellationMinimapHide
                  : l10n.constellationMinimapShow,
              onPressed: () => widget.expanded.value = !expanded,
              icon: Icon(expanded ? Icons.map : Icons.map_outlined),
            ),
            if (expanded)
              Padding(
                padding: EdgeInsets.only(top: context.tt.tightGap * 2),
                // A pointer-only shortcut: a semantics tap has no position,
                // and its tap action would merge into the map's own node and
                // claim every click on the map on the web (#640).
                child: GestureDetector(
                  key: const Key('constellation.minimap.surface'),
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onTapUp: _onTapUp,
                  child: SizedBox(
                    key: const Key('constellation.minimap'),
                    width: kConstellationMinimapSize,
                    height: kConstellationMinimapSize,
                    // A DecoratedBox border takes no layout room and paints
                    // beneath the content, so a person at the field's edge
                    // keeps their whole dot.
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: ClipRect(
                        child: _MinimapContent(
                          projection: projection,
                          people: _people,
                          beacons: _beacons,
                          viewer: _viewer,
                          frame: frame,
                          scheme: scheme,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MinimapContent extends StatelessWidget {
  const _MinimapContent({
    required this.projection,
    required this.people,
    required this.beacons,
    required this.viewer,
    required this.frame,
    required this.scheme,
  });

  final ConstellationMinimapProjection projection;
  final List<Offset> people;
  final List<Offset> beacons;
  final Offset? viewer;
  final LRect? frame;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final frame = this.frame;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _DotsPainter(
              projection: projection,
              people: [...people, ...beacons],
              viewer: viewer,
              personColor: scheme.primary,
              viewerColor: scheme.tertiary,
            ),
          ),
        ),
        if (frame != null)
          Positioned(
            left: frame.left,
            top: frame.top,
            width: frame.right - frame.left,
            height: frame.bottom - frame.top,
            child: DecoratedBox(
              key: const Key('constellation.minimap.frame'),
              decoration: BoxDecoration(
                border: Border.all(
                  color: scheme.primary,
                  width: _minimapFrameStrokeWidth,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter({
    required this.projection,
    required this.people,
    required this.viewer,
    required this.personColor,
    required this.viewerColor,
  });

  final ConstellationMinimapProjection projection;
  final List<Offset> people;
  final Offset? viewer;
  final Color personColor;
  final Color viewerColor;

  Offset _dot(Offset world) {
    final p = projection.worldToMinimap((x: world.dx, y: world.dy));
    return Offset(p.x, p.y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = personColor;
    for (final person in people) {
      canvas.drawCircle(_dot(person), _personDotRadius, paint);
    }
    final viewer = this.viewer;
    if (viewer != null) {
      paint.color = viewerColor;
      canvas.drawCircle(_dot(viewer), _viewerDotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      !identical(projection, old.projection) ||
      !identical(people, old.people) ||
      viewer != old.viewer ||
      personColor != old.personColor ||
      viewerColor != old.viewerColor;
}
