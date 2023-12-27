import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/app/router.dart';

import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/widget/graph_node_widget.dart';
import 'package:tentura/features/graph/bloc/graph_cubit.dart';

class GraphBody extends StatefulWidget {
  const GraphBody({
    required this.controller,
    this.isLabeled = true,
    this.isAnimated = true,
    this.labelSize = const Size(100, 20),
    this.scaleRange = const Offset(0.1, 3),
    this.animationDuration = const Duration(seconds: 2),
    this.canvasSize = const GraphCanvasSize.fixed(Size(4096, 4096)),
    this.layoutAlgorithm = const FruchtermanReingoldAlgorithm(
      iterations: 1500,
      temperature: 500,
      optimalDistance: 100,
      showIterations: true,
    ),
    super.key,
  });

  final Size labelSize;
  final bool isLabeled;
  final bool isAnimated;
  final Offset scaleRange;
  final Duration animationDuration;
  final GraphCanvasSize canvasSize;
  final GraphLayoutAlgorithm layoutAlgorithm;
  final GraphController<NodeDetails, EdgeDetails<NodeDetails>> controller;

  @override
  GraphBodyState createState() => GraphBodyState();
}

class GraphBodyState extends State<GraphBody>
    with SingleTickerProviderStateMixin {
  late final _animationController = AnimationController(
    duration: widget.animationDuration,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    if (widget.isAnimated) _animationController.repeat();
  }

  @override
  void dispose() {
    if (widget.isAnimated) _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      GraphView<NodeDetails, EdgeDetails<NodeDetails>>(
        controller: context.read<GraphCubit>().graphController,
        canvasSize: widget.canvasSize,
        minScale: widget.scaleRange.dx,
        maxScale: widget.scaleRange.dy,
        layoutAlgorithm: widget.layoutAlgorithm,
        edgePainter: _AnimatedHighlightedEdgePainter(
          animation: CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOutCirc,
          ),
          highlightColor: Theme.of(context).canvasColor,
          highlightRadius: 0.15,
          isAnimated: widget.isAnimated,
        ),
        labelBuilder: widget.isLabeled
            ? BottomLabelBuilder(
                labelSize: widget.labelSize,
                builder: (context, node) => switch (node) {
                  final UserNode node => Text(
                      node.label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                    ),
                  final BeaconNode node => Text(
                      node.label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  _ => const Offstage(),
                },
              )
            : null,
        nodeBuilder: (context, node) => GraphNodeWidget(
          nodeDetails: node,
          onTap: () => context.read<GraphCubit>().setFocus(node),
          onDoubleTap: () => context.push(switch (node) {
            final UserNode node => Uri(
                path: pathProfileView,
                queryParameters: {
                  'id': node.id,
                },
              ),
            final BeaconNode node => Uri(
                path: pathBeaconView,
                queryParameters: {
                  'id': node.id,
                  'expanded': 'false',
                },
              ),
            final CommentNode node => Uri(
                path: pathBeaconView,
                queryParameters: {
                  'id': node.beaconId,
                  'expanded': 'true',
                },
              ),
          }
              .toString()),
        ),
      );
}

class _AnimatedHighlightedEdgePainter
    implements AnimatedEdgePainter<NodeDetails, EdgeDetails<NodeDetails>> {
  _AnimatedHighlightedEdgePainter({
    required this.animation,
    required this.highlightColor,
    required this.highlightRadius,
    this.isAnimated = true,
  });

  @override
  final Animation<double> animation;

  final bool isAnimated;
  final Color highlightColor;
  final double highlightRadius;

  late final _colorStops = <double>[0, highlightRadius, highlightRadius * 2];

  @override
  void paint(
    Canvas canvas,
    EdgeDetails<NodeDetails> edge,
    Offset src,
    Offset dst,
  ) =>
      isAnimated
          ? canvas.drawLine(
              src,
              dst,
              Paint()
                ..strokeWidth = edge.strokeWidth
                ..shader = ui.Gradient.linear(
                  src,
                  dst,
                  [edge.color, highlightColor, edge.color],
                  _colorStops,
                  TileMode.clamp,
                  Matrix4.translationValues(
                    (dst.dx - src.dx) * animation.value,
                    (dst.dy - src.dy) * animation.value,
                    0,
                  ).storage,
                ),
            )
          : canvas.drawLine(
              src,
              dst,
              Paint()
                ..color = edge.color
                ..strokeWidth = edge.strokeWidth,
            );
}
