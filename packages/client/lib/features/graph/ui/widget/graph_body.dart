import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  void _toggleLegend() => setState(() => _legendExpanded = !_legendExpanded);

  void _onNodeTap(NodeDetails node) {
    _graphCubit.handleNodeTap(node);
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
        previous.positiveOnly != current.positiveOnly ||
        previous.hiddenNeighborCounts != current.hiddenNeighborCounts,
    builder: (context, graphState) {
      NodeDetails? focusedNode;
      final focusId = graphState.focus;
      if (focusId.isNotEmpty) {
        for (final node in _graphCubit.graphController.nodes) {
          if (node.id == focusId) {
            focusedNode = node;
            break;
          }
        }
      }
      final focused = focusedNode;
      final controller = _graphCubit.graphController;

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
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _GraphToolbarHost(
                graphState: graphState,
                controller: controller,
                graphCubit: _graphCubit,
                focusedNode: focused,
                legendExpanded: _legendExpanded,
                onToggleLegend: _toggleLegend,
                onExpandNode: _graphCubit.expandNode,
                onOpenDetails: focused == null
                    ? null
                    : () => _openNodeDetails(focused),
              ),
            ),
          ),
          if (_legendExpanded)
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
                    onToggle: _toggleLegend,
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

/// Listens to [GraphController] layout settling without rebuilding during build.
class _GraphToolbarHost extends StatefulWidget {
  const _GraphToolbarHost({
    required this.graphState,
    required this.controller,
    required this.graphCubit,
    required this.focusedNode,
    required this.legendExpanded,
    required this.onToggleLegend,
    required this.onExpandNode,
    required this.onOpenDetails,
  });

  final GraphState graphState;
  final GraphController<NodeDetails, EdgeDetails<NodeDetails>> controller;
  final GraphCubit graphCubit;
  final NodeDetails? focusedNode;
  final bool legendExpanded;
  final VoidCallback onToggleLegend;
  final Future<void> Function(NodeDetails node) onExpandNode;
  final VoidCallback? onOpenDetails;

  @override
  State<_GraphToolbarHost> createState() => _GraphToolbarHostState();
}

class _GraphToolbarHostState extends State<_GraphToolbarHost> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _GraphToolbarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusedNode;
    final canExpand = focused != null &&
        !widget.graphState.isLoading &&
        widget.controller.canLayout &&
        !widget.controller.isLayoutSettling &&
        widget.graphCubit.canPageMore(focused.id);
    return _GraphToolbar(
      legendExpanded: widget.legendExpanded,
      onToggleLegend: widget.onToggleLegend,
      focusedNode: focused,
      showExpand: canExpand,
      onExpand: canExpand ? () => widget.onExpandNode(focused) : null,
      onOpenDetails: widget.onOpenDetails,
    );
  }
}

/// Single top-right toolbar: focus actions (when set) + graph navigation.
class _GraphToolbar extends StatelessWidget {
  const _GraphToolbar({
    required this.legendExpanded,
    required this.onToggleLegend,
    required this.focusedNode,
    required this.showExpand,
    required this.onExpand,
    required this.onOpenDetails,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;
  final NodeDetails? focusedNode;
  final bool showExpand;
  final VoidCallback? onExpand;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<GraphCubit>();
    final node = focusedNode;

    final contextActions = <Widget>[];
    if (node != null && onOpenDetails != null) {
      if (showExpand && onExpand != null) {
        contextActions.add(
          IconButton(
            key: TestIds.key(TestIds.graphExpand),
            tooltip: l10n.inboxProvenanceExpand,
            onPressed: onExpand,
            icon: const Icon(Icons.hub_outlined),
          ),
        );
      }
      final openDetails = switch (node) {
        UserNode() || GenealogyUserNode() => (
          tooltip: l10n.profile,
          icon: Icons.person_outline,
        ),
        BeaconNode() => (
          tooltip: l10n.openBeacon,
          icon: Icons.flag_outlined,
        ),
        GenealogyDeletedNode() => null,
      };
      if (openDetails != null) {
        contextActions.add(
          IconButton(
            key: TestIds.key(TestIds.graphOpenDetails),
            tooltip: openDetails.tooltip,
            onPressed: onOpenDetails,
            icon: Icon(openDetails.icon),
          ),
        );
      }
    }

    final showDivider = contextActions.isNotEmpty;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.all(tt.rowGap),
        child: Material(
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
                ...contextActions,
                if (showDivider)
                  SizedBox(
                    height: tt.buttonHeight,
                    child: VerticalDivider(
                      width: tt.tightGap,
                      thickness: 1,
                      color: scheme.outlineVariant,
                    ),
                  ),
                IconButton(
                  key: TestIds.key(TestIds.graphResetToEgo),
                  tooltip: l10n.graphResetToEgo,
                  onPressed: () => cubit.jumpToEgo(resetScale: true),
                  icon: const Icon(Icons.home_outlined),
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
        ),
      ),
    );
  }
}
