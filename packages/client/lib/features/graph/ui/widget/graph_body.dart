import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../../domain/entity/edge_details.dart';
import '../../domain/entity/node_details.dart';
import '../utils/animated_highlighted_edge_painter.dart';
import '../utils/ease_in_out_reynolds.dart';
import '../utils/tentura_layout_algorithms.dart';
import '../bloc/graph_cubit.dart';
import 'graph_legend_mode.dart';
import 'graph_legend_panel.dart';
import 'graph_node_widget.dart';

class GraphBody extends StatefulWidget {
  const GraphBody({
    required this.legendExpanded,
    required this.onToggleLegend,
    this.isLabeled = true,
    this.labelSize = const Size(100, 20),
    this.scaleRange = const Offset(0.1, 3),
    this.animationDuration = const Duration(seconds: 2),
    this.canvasSize = const GraphCanvasSize.fixed(Size(4096, 4096)),
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;
  final bool isLabeled;
  final Size labelSize;
  final Offset scaleRange;
  final Duration animationDuration;
  final GraphCanvasSize canvasSize;

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

  GraphLegendMode get _legendMode {
    if (_graphCubit.genealogyMode) {
      return GraphLegendMode.genealogy;
    }
    if (_graphCubit.forwardsGraphBeaconId != null) {
      return GraphLegendMode.forwards;
    }
    return GraphLegendMode.trust;
  }

  GraphLayoutAlgorithm get _layoutAlgorithm {
    if (_graphCubit.genealogyMode) {
      // Genealogy edges run ancestor -> descendant, so the viewer is a leaf,
      // not a root. Leave [rootIds] empty and let the layout rank from the
      // in-degree-zero nodes (the topmost ancestors); seeding it with the ego
      // node reaches nothing and drops every ancestor into one flat row.
      return const LayeredDagLayoutAlgorithm(rootIds: {});
    }
    if (_graphCubit.forwardsGraphBeaconId != null) {
      return LayeredDagLayoutAlgorithm(
        rootIds: _graphCubit.forwardsRootIds,
      );
    }
    return RadialHopLayoutAlgorithm(
      rootId: _graphCubit.state.me.id,
    );
  }

  void _onNodeTap(NodeDetails node) {
    _graphCubit.handleNodeTap(node);
  }

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
  Widget build(BuildContext context) => BlocBuilder<GraphCubit, GraphState>(
    buildWhen: (previous, current) =>
        previous.isLoading != current.isLoading ||
        previous.focus != current.focus ||
        previous.positiveOnly != current.positiveOnly ||
        previous.hiddenNeighborCounts != current.hiddenNeighborCounts,
    builder: (context, graphState) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildGraphView(graphState),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearPiActive.builder(context, graphState.isLoading),
          ),
          if (widget.legendExpanded)
            Positioned(
              left: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                right: false,
                child: Padding(
                  padding: EdgeInsets.all(context.tt.rowGap),
                  child: GraphLegendPanel(
                    mode: _legendMode,
                    expanded: true,
                    onToggle: widget.onToggleLegend,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _buildGraphView(GraphState graphState) =>
      GraphView<NodeDetails, EdgeDetails<NodeDetails>>(
        controller: _graphCubit.graphController,
        canvasSize: widget.canvasSize,
        minScale: widget.scaleRange.dx,
        maxScale: widget.scaleRange.dy,
        layoutAlgorithm: _layoutAlgorithm,
        layoutTransitionDuration: const Duration(milliseconds: 350),
        edgePainter: AnimatedHighlightedEdgePainter(
          animation: CurvedAnimation(
            parent: _animationController,
            curve: const EaseInOutReynolds(),
          ),
          highlightRadius: 0.15,
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
                    style: TenturaText.labelSmall(
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  final GenealogyUserNode node => Text(
                    key: ValueKey(node),
                    node.label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.labelSmall(
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  final GenealogyDeletedNode node => Text(
                    key: ValueKey(node),
                    node.label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.labelSmall(
                      Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  _ => const SizedBox.shrink(),
                },
              )
            : null,
        nodeBuilder: (_, node) => GraphNodeWidget(
          key: TestIds.key(TestIds.graphNode(node.id)),
          nodeDetails: node,
          withRating:
              node is GenealogyUserNode ||
              graphNodeShowsMeritRankRating(
                nodeId: node.id,
                viewerId: _graphCubit.state.me.id,
              ),
          isSelf:
              node is GenealogyUserNode &&
              node.id == _graphCubit.state.egoNodeId,
          isOrigin: node.id == _graphCubit.originNodeId,
          isFocused:
              graphState.focus.isNotEmpty && node.id == graphState.focus,
          onTap: () => _onNodeTap(node),
        ),
      );
}
