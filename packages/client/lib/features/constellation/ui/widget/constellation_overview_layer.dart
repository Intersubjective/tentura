import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';

import '../../domain/constellation_grid_clusters.dart';
import '../utils/constellation_presentation_frame.dart';

/// Ego-to-cell edge bundles on the overview map. Bundles share the same
/// screen-space 72 pt grid as [computeConstellationGridClusters]; this layer
/// paints them only.
class ConstellationOverviewLayer extends StatelessWidget {
  const ConstellationOverviewLayer({
    required this.frame,
    required this.viewerId,
    this.peopleTags,
    super.key,
  });

  final ConstellationPresentationFrame frame;
  final String viewerId;
  final PeopleTagsCase? peopleTags;

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
      final ego = frame.bodies['fp:$viewerId']?.center;
      if (ego == null) {
        return const SizedBox.shrink();
      }
      return IgnorePointer(
        child: CustomPaint(
          painter: _BundlePainter(
            ego: ego,
            clusters: clusters,
            color: tt.graphEdgePath,
            widthPerPerson: tt.tightGap / kConstellationGridCellSize,
          ),
        ),
      );
    },
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
