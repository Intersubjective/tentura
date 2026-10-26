import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_grid_clusters.dart';
import '../utils/constellation_presentation_frame.dart';

/// Labels and ego bundles share the same screen-space partition on every
/// camera/drag frame. Dragging a label reports the cluster and the drag in
/// screen points through [onClusterDragged]; this layer writes nothing itself.
class ConstellationOverviewLayer extends StatelessWidget {
  const ConstellationOverviewLayer({
    required this.frame,
    required this.viewerId,
    this.peopleTags,
    this.onClusterDragged,
    super.key,
  });

  final ConstellationPresentationFrame frame;
  final String viewerId;
  final PeopleTagsCase? peopleTags;

  /// A label was dragged and let go: the people it counts and how far (screen
  /// points) it was dragged.
  final void Function(List<String> personIds, Offset screenDelta)?
  onClusterDragged;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: peopleTags?.changes,
    builder: (context, _) {
      final tags = peopleTags?.tags ?? const [];
      final positions = {
        for (final entry in frame.bodies.entries)
          if (entry.key.startsWith('fp:') && entry.key != 'fp:$viewerId')
            entry.key.substring(3): (
              x: entry.value.center.dx,
              y: entry.value.center.dy,
            ),
      };
      final clusters = computeConstellationGridClusters(
        screenPositions: positions,
        ownTagIdsInOrder: [for (final tag in tags) tag.id],
        ownTagIdsByPerson: {
          for (final id in positions.keys)
            id: peopleTags?.tagsOfPerson(id) ?? const {},
        },
      );
      final tt = context.tt;
      final scheme = Theme.of(context).colorScheme;
      final l10n = L10n.of(context)!;
      final ego = frame.bodies['fp:$viewerId']?.center;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (ego != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BundlePainter(
                    ego: ego,
                    clusters: clusters,
                    color: tt.graphEdgePath,
                    widthPerPerson: tt.tightGap / kConstellationGridCellSize,
                  ),
                ),
              ),
            ),
          for (final cluster in clusters)
            Positioned(
              left: cluster.centre.x,
              top: cluster.centre.y,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: _DraggableClusterLabel(
                  onDragged: (delta) =>
                      onClusterDragged?.call(cluster.personIds, delta),
                  child: Text(
                    switch (cluster.dominantTagId) {
                      final id? =>
                        '${tags.firstWhere((tag) => tag.id == id).name} · ${cluster.personIds.length}',
                      null => l10n.constellationClusterPeople(
                        cluster.personIds.length,
                      ),
                    },
                    style: TenturaText.labelSmall(scheme.onSurface),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Adds up one pan on [child] and reports the whole drag when it ends.
class _DraggableClusterLabel extends StatefulWidget {
  const _DraggableClusterLabel({required this.onDragged, required this.child});

  final ValueChanged<Offset> onDragged;
  final Widget child;

  @override
  State<_DraggableClusterLabel> createState() => _DraggableClusterLabelState();
}

class _DraggableClusterLabelState extends State<_DraggableClusterLabel> {
  Offset _delta = Offset.zero;

  @override
  Widget build(BuildContext context) => GestureDetector(
    // Keep the cluster's pan recognizer in the hit path while allowing taps
    // to reach person dots beneath the label.
    behavior: HitTestBehavior.translucent,
    // The distance before the pan is recognised counts as dragged too.
    dragStartBehavior: DragStartBehavior.down,
    onPanStart: (_) => _delta = Offset.zero,
    onPanUpdate: (details) => _delta += details.delta,
    onPanEnd: (_) => widget.onDragged(_delta),
    child: IgnorePointer(child: widget.child),
  );
}

class _BundlePainter extends CustomPainter {
  const _BundlePainter({
    required this.ego,
    required this.clusters,
    required this.color,
    required this.widthPerPerson,
  });

  final Offset ego;
  final List<ConstellationGridCluster> clusters;
  final Color color;
  final double widthPerPerson;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final cluster in clusters) {
      paint.strokeWidth = widthPerPerson * cluster.personIds.length;
      canvas.drawLine(ego, Offset(cluster.centre.x, cluster.centre.y), paint);
    }
  }

  @override
  bool shouldRepaint(_BundlePainter oldDelegate) =>
      ego != oldDelegate.ego ||
      clusters != oldDelegate.clusters ||
      color != oldDelegate.color ||
      widthPerPerson != oldDelegate.widthPerPerson;
}
