import 'dart:async';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
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
    this.isLabeled = true,
    this.labelSize = const Size(100, 20),
    this.scaleRange = const Offset(0.1, 3),
    this.animationDuration = const Duration(seconds: 2),
    this.canvasSize = const GraphCanvasSize.fixed(Size(4096, 4096)),
    super.key,
  });

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

  late final _screenCubit = context.read<ScreenCubit>();

  bool _legendExpanded = false;

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
      return LayeredDagLayoutAlgorithm(
        rootIds: {_graphCubit.state.egoNodeId},
      );
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

  void _toggleLegend() => setState(() => _legendExpanded = !_legendExpanded);

  void _onNodeTap(NodeDetails node) {
    if (_graphCubit.canExpandNode(node.id)) {
      unawaited(_graphCubit.expandNode(node));
    } else {
      _graphCubit.selectNode(node);
    }
  }

  void _openNodeDetails(NodeDetails node) {
    switch (node) {
      case final UserNode n:
        _screenCubit.showProfile(n.id);
      case final GenealogyUserNode n:
        _screenCubit.showProfile(n.user.id);
      case final BeaconNode n:
        _screenCubit.showBeacon(n.id);
      case GenealogyDeletedNode():
        break;
    }
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
        previous.positiveOnly != current.positiveOnly,
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
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              left: false,
              bottom: false,
              child: _GraphNavigationControls(
                legendExpanded: _legendExpanded,
                onToggleLegend: _toggleLegend,
              ),
            ),
          ),
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
                  expanded: _legendExpanded,
                  onToggle: _toggleLegend,
                ),
              ),
            ),
          ),
          BlocSelector<GraphCubit, GraphState, String>(
            selector: (state) => state.focus,
            builder: (context, focusId) {
              if (focusId.isEmpty) {
                return const SizedBox.shrink();
              }
              NodeDetails? focusedNode;
              for (final node in _graphCubit.graphController.nodes) {
                if (node.id == focusId) {
                  focusedNode = node;
                  break;
                }
              }
              if (focusedNode == null) {
                return const SizedBox.shrink();
              }
              final node = focusedNode;
              return _GraphNodeActionPanel(
                node: node,
                showExpand: _graphCubit.forwardsGraphBeaconId == null,
                onExpand: () => _graphCubit.expandNode(node),
                onOpenDetails: () => _openNodeDetails(node),
              );
            },
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

class _GraphNavigationControls extends StatelessWidget {
  const _GraphNavigationControls({
    required this.legendExpanded,
    required this.onToggleLegend,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<GraphCubit>();

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 2,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.tightGap / 2,
          vertical: tt.tightGap / 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BlocBuilder<GraphCubit, GraphState>(
              builder: (context, _) => IconButton(
                key: TestIds.key(TestIds.graphBack),
                tooltip: l10n.graphBack,
                onPressed: cubit.canPopFocus ? cubit.popFocus : null,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            IconButton(
              key: TestIds.key(TestIds.graphResetToEgo),
              tooltip: l10n.graphResetToEgo,
              onPressed: cubit.resetToEgo,
              icon: const Icon(Icons.home_outlined),
            ),
            IconButton(
              tooltip: l10n.graphFitPath,
              onPressed: () {
                if (cubit.graphController.canLayout) {
                  cubit.fitCurrentPath();
                }
              },
              icon: const Icon(Icons.fit_screen_outlined),
            ),
            IconButton(
              tooltip: legendExpanded
                  ? l10n.graphLegendClose
                  : l10n.graphLegendOpen,
              onPressed: onToggleLegend,
              icon: Icon(
                legendExpanded ? Icons.map : Icons.map_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphNodeActionPanel extends StatelessWidget {
  const _GraphNodeActionPanel({
    required this.node,
    required this.showExpand,
    required this.onExpand,
    required this.onOpenDetails,
  });

  final NodeDetails node;
  final bool showExpand;
  final VoidCallback onExpand;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final canOpenDetails = switch (node) {
      UserNode() || GenealogyUserNode() || BeaconNode() => true,
      GenealogyDeletedNode() => false,
    };

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            elevation: 2,
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(tt.cardRadius),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.iconTextGap,
                vertical: tt.rowGap / 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showExpand)
                    TextButton(
                      key: TestIds.key(TestIds.graphExpand),
                      onPressed: onExpand,
                      child: Text(l10n.inboxProvenanceExpand),
                    ),
                  if (canOpenDetails)
                    TextButton(
                      onPressed: onOpenDetails,
                      child: Text(l10n.profile),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
