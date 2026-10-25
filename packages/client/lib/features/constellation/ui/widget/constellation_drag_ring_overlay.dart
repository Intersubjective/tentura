import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/constellation_nearest_ring.dart';
import '../bloc/constellation_cubit.dart';
import '../utils/constellation_graph_scene.dart';
import 'constellation_ring_caption.dart';

/// While a node is dragged, highlights the trust ring nearest to it around
/// the viewer and names it with a «{n} steps» caption.
class ConstellationDragRingOverlay extends StatelessWidget {
  const ConstellationDragRingOverlay({required this.cubit, super.key});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final controller = cubit.graphController;
    final scheme = Theme.of(context).colorScheme;
    final egoId = constellationGraphNodeIdForTarget(
      ConstellationAnchorTarget.person(cubit.viewerId),
    );
    return ValueListenableBuilder<Offset?>(
      valueListenable: cubit.dragCentre,
      builder: (context, dragged, _) {
        final egoPoint = controller.renderSnapshot.resolvePosition(egoId);
        if (dragged == null || egoPoint == null) {
          return const SizedBox.shrink();
        }
        final ring = constellationNearestRing(
          centre: (x: egoPoint.x, y: egoPoint.y),
          point: (x: dragged.dx, y: dragged.dy),
        );
        return ListenableBuilder(
          listenable: controller.cameraRevision,
          builder: (context, _) {
            final ego = controller.sceneToViewportLocal(
              Offset(egoPoint.x, egoPoint.y),
            );
            final radius = ring.radius * controller.cameraScale;
            final angle = math.atan2(
              dragged.dy - egoPoint.y,
              dragged.dx - egoPoint.x,
            );
            final label = ego + Offset.fromDirection(angle, radius);
            return IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _RingPainter(
                      centre: ego,
                      radius: radius,
                      color: scheme.primary,
                      stroke: TenturaSpacing.focusRing,
                    ),
                  ),
                  Positioned(
                    left: label.dx,
                    top: label.dy,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, -0.5),
                      child: ConstellationRingCaption(steps: ring.steps),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.centre,
    required this.radius,
    required this.color,
    required this.stroke,
  });

  final Offset centre;
  final double radius;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.centre != centre ||
      old.radius != radius ||
      old.color != color ||
      old.stroke != stroke;
}
