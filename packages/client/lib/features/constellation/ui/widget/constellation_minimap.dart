import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_minimap.dart';
import '../../domain/layout/layout_geometry.dart';

const _personDotRadius = 2.0;
const _viewerDotRadius = 3.5;
const _viewerNodeId = 'fp:ego';
const _personNodePrefix = 'fp:';

/// A collapsible overview of the whole Field: everyone as a dot and a frame
/// for the part the camera shows. A tap moves the camera there, same zoom.
class ConstellationMinimap extends StatefulWidget {
  const ConstellationMinimap({
    required this.controller,
    required this.expanded,
    super.key,
  });

  final GraphController<NodeDetails, EdgeDetails> controller;

  /// Kept by the owner so the choice survives zooming to the close level.
  final ValueNotifier<bool> expanded;

  @override
  State<ConstellationMinimap> createState() => _ConstellationMinimapState();
}

class _ConstellationMinimapState extends State<ConstellationMinimap> {
  late Listenable _changes;
  Object? _projectionSnapshot;
  ConstellationMinimapProjection? _projection;
  List<Offset> _people = const [];
  Offset? _viewer;

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
    Offset? viewer;
    for (final id in snapshot.topology.nodesById.keys) {
      if (!id.startsWith(_personNodePrefix)) continue;
      final at = controller.getPositionOrNullForId(id);
      if (at == null) continue;
      if (id == _viewerNodeId) {
        viewer = at;
      } else {
        people.add(at);
      }
    }
    _people = people;
    _viewer = viewer;
    _projectionSnapshot = snapshot;
    return _projection = ConstellationMinimapProjection.fromPoints([
      for (final p in [...people, ?viewer]) (x: p.dx, y: p.dy),
    ]);
  }

  LRect? _viewportWorld() {
    final controller = widget.controller;
    final size = controller.viewportSize;
    if (size == null) return null;
    final topLeft = controller.viewportLocalToScene(Offset.zero);
    final bottomRight = controller.viewportLocalToScene(
      Offset(size.width, size.height),
    );
    return (
      left: topLeft.dx,
      top: topLeft.dy,
      right: bottomRight.dx,
      bottom: bottomRight.dy,
    );
  }

  void _moveCameraTo(ConstellationMinimapProjection projection, Offset tap) {
    final world = projection.minimapToWorld((x: tap.dx, y: tap.dy));
    widget.controller.jumpToPosition(Offset(world.x, world.y));
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
                  excludeFromSemantics: true,
                  onTapUp: (details) =>
                      _moveCameraTo(projection, details.localPosition),
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
                          viewer: _viewer,
                          frame: frame,
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
    required this.viewer,
    required this.frame,
  });

  final ConstellationMinimapProjection projection;
  final List<Offset> people;
  final Offset? viewer;
  final LRect? frame;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frame = this.frame;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _DotsPainter(
              projection: projection,
              people: people,
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
            child: IgnorePointer(
              child: DecoratedBox(
                key: const Key('constellation.minimap.frame'),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.secondary),
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
