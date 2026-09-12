import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/configuration.dart';
import 'package:force_directed_graphview/src/scene/scene_snapshot.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';

/// { @nodoc }
class EdgesView extends StatelessWidget {
  /// { @nodoc }
  const EdgesView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = InheritedConfiguration.controllerOf(context);
    final configuration = InheritedConfiguration.configurationOf(context);
    final scope = GraphSceneRenderScope.of(context);

    return RepaintBoundary(
      child: CustomPaint(
        painter: _EdgesPainter(
          snapshot: scope.snapshot,
          configuration: configuration,
          animation: switch (configuration.edgePainter) {
            AnimatedEdgePainter(:final animation) => animation,
            _ => null,
          },
          repaint: controller,
        ),
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.snapshot,
    required this.configuration,
    required this.animation,
    required Listenable repaint,
  }) : super(repaint: Listenable.merge([repaint, animation]));

  final GraphSceneSnapshot<NodeBase, EdgeBase> snapshot;
  final GraphViewConfiguration configuration;
  final Animation<double>? animation;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in snapshot.topology.edgesById.values) {
      final sourcePoint = snapshot.resolvePosition(edge.sourceId);
      final destinationPoint = snapshot.resolvePosition(edge.destinationId);
      if (sourcePoint == null || destinationPoint == null) {
        continue;
      }
      configuration.edgePainter.paint(
        canvas,
        edge.payload,
        Offset(sourcePoint.x, sourcePoint.y),
        Offset(destinationPoint.x, destinationPoint.y),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) =>
      snapshot != oldDelegate.snapshot ||
      configuration.edgePainter != oldDelegate.configuration.edgePainter;
}
