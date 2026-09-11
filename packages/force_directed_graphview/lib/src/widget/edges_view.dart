import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/configuration.dart';
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

    return RepaintBoundary(
      child: CustomPaint(
        painter: _EdgesPainter(
          controller: controller,
          configuration: configuration,
          animation: switch (configuration.edgePainter) {
            AnimatedEdgePainter(:final animation) => animation,
            _ => null,
          },
        ),
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.controller,
    required this.configuration,
    required this.animation,
  }) : super(repaint: Listenable.merge([controller, animation]));

  final GraphController controller;
  final GraphViewConfiguration configuration;
  final Animation<double>? animation;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.canLayout) {
      return;
    }

    final edges = controller.edges;

    for (final edge in edges) {
      final source = controller.getPositionOrNull(edge.source);
      final destination = controller.getPositionOrNull(edge.destination);
      if (source == null || destination == null) {
        continue;
      }
      configuration.edgePainter.paint(
        canvas,
        edge,
        source,
        destination,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
