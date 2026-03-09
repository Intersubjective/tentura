import 'dart:async';
import 'package:nil/nil.dart';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/ui/bloc/screen_cubit.dart';

import '../../domain/entity/edge_details.dart';
import '../../domain/entity/node_details.dart';
import '../utils/animated_highlighted_edge_painter.dart';
import '../utils/initial_position_extractor.dart';
import '../utils/ease_in_out_reynolds.dart';
import '../bloc/graph_cubit.dart';
import 'graph_node_widget.dart';

class GraphBody extends StatefulWidget {
  const GraphBody({
    this.isLabeled = true,
    this.labelSize = const Size(100, 20),
    this.scaleRange = const Offset(0.1, 3),
    this.animationDuration = const Duration(seconds: 2),
    this.canvasSize = const GraphCanvasSize.fixed(Size(4096, 4096)),
    this.layoutAlgorithm = const FruchtermanReingoldAlgorithm(
      initialPositionExtractor: initialPositionExtractor,
      iterations: kIsWeb && !kIsWasm ? 300 : 500,
      optimalDistance: 100,
      showIterations: true,
      temperature: 500,
    ),
    super.key,
  });

  final bool isLabeled;
  final Size labelSize;
  final Offset scaleRange;
  final Duration animationDuration;
  final GraphCanvasSize canvasSize;
  final GraphLayoutAlgorithm layoutAlgorithm;

  @override
  GraphBodyState createState() => GraphBodyState();
}

class GraphBodyState extends State<GraphBody>
    with SingleTickerProviderStateMixin {
  late final _animationController = AnimationController(
    duration: widget.animationDuration,
    vsync: this,
  );

  late final _graphCubit = context.read<GraphCubit>();

  late final _screenCubit = context.read<ScreenCubit>();

  @override
  void initState() {
    super.initState();
    if (_graphCubit.state.isAnimated) {
      unawaited(_animationController.repeat());
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(_) => GraphView<NodeDetails, EdgeDetails<NodeDetails>>(
    controller: _graphCubit.graphController,
    canvasSize: widget.canvasSize,
    minScale: widget.scaleRange.dx,
    maxScale: widget.scaleRange.dy,
    layoutAlgorithm: widget.layoutAlgorithm,
    edgePainter: AnimatedHighlightedEdgePainter(
      animation: CurvedAnimation(
        parent: _animationController,
        curve: const EaseInOutReynolds(),
      ),
      highlightRadius: 0.15,
      highlightColor: Colors.indigo,
      isAnimated: _graphCubit.state.isAnimated,
    ),
    labelBuilder: widget.isLabeled
        ? BottomLabelBuilder(
            labelSize: widget.labelSize,
            builder: (_, node) => switch (node) {
              final UserNode node => Text(
                key: ValueKey(node),
                node.label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              _ => nil,
            },
          )
        : null,
    nodeBuilder: (_, node) => GraphNodeWidget(
      key: ValueKey(node),
      nodeDetails: node,
      withRating: node.id != _graphCubit.state.me.id,
      onTap: () => _graphCubit.setFocus(node),
      onDoubleTap: () => switch (node) {
        final UserNode n => _screenCubit.showProfile(n.id),
        final BeaconNode n => _screenCubit.showBeacon(n.id),
      },
    ),
  );
}
