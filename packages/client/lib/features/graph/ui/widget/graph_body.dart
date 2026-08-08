import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../../domain/entity/edge_details.dart';
import '../../domain/entity/graph_mode.dart';
import '../../domain/entity/node_details.dart';
import '../utils/animated_highlighted_edge_painter.dart';
import '../utils/ease_in_out_reynolds.dart';
import '../utils/tentura_layout_algorithms.dart';
import '../bloc/graph_cubit.dart';
import '../bloc/graph_person_context_cubit.dart';
import 'graph_legend_mode.dart';
import 'graph_legend_panel.dart';
import 'graph_node_widget.dart';
import 'graph_person_context_panel.dart';

class GraphBody extends StatefulWidget {
  const GraphBody({
    required this.legendExpanded,
    required this.onToggleLegend,
    this.personContextEnabled = false,
    this.isLabeled = true,
    this.labelSize = const Size(100, 20),
    this.scaleRange = const Offset(0.1, 3),
    this.animationDuration = const Duration(seconds: 2),
    this.canvasSize = const GraphCanvasSize.fixed(Size(4096, 4096)),
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;
  final bool personContextEnabled;
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

  GraphLegendMode get _legendMode => switch (_graphCubit.mode) {
    GraphMode.trust => GraphLegendMode.trust,
    GraphMode.forwards => GraphLegendMode.forwards,
    GraphMode.genealogy => GraphLegendMode.genealogy,
  };

  GraphLayoutAlgorithm get _layoutAlgorithm {
    switch (_graphCubit.mode) {
      case GraphMode.genealogy:
        return const LayeredDagLayoutAlgorithm(rootIds: {});
      case GraphMode.forwards:
        return LayeredDagLayoutAlgorithm(
          rootIds: _graphCubit.forwardsRootIds,
        );
      case GraphMode.trust:
        return RadialHopLayoutAlgorithm(
          rootId: _graphCubit.state.me.id,
        );
    }
  }

  void _onNodeTap(NodeDetails node) {
    _graphCubit.handleNodeTap(node);
    if (!widget.personContextEnabled || _graphCubit.mode != GraphMode.trust) {
      return;
    }
    if (node is UserNode && node.id != _graphCubit.state.me.id) {
      context.read<GraphPersonContextCubit>().selectProfile(
        node.user,
        intentional: true,
      );
    }
  }

  UserNode? _focusedUserNode(String focusId) {
    if (focusId.isEmpty || focusId == _graphCubit.state.me.id) {
      return null;
    }
    for (final node in _graphCubit.graphController.nodes) {
      if (node.id == focusId && node is UserNode) {
        return node;
      }
    }
    return null;
  }

  void _syncFocusToPersonContext(String focus) {
    if (!widget.personContextEnabled) {
      return;
    }
    final contextCubit = context.read<GraphPersonContextCubit>();
    final userNode = _focusedUserNode(focus);
    if (userNode == null) {
      contextCubit.clearSelection();
      return;
    }
    contextCubit.selectProfile(userNode.user, intentional: false);
  }

  bool _isPanelVisible(GraphPersonContextState contextState) {
    final profile = contextState.selectedProfile;
    if (profile == null) {
      return false;
    }
    return contextState.dismissedFocusId != profile.id;
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
  Widget build(BuildContext context) {
    if (!widget.personContextEnabled) {
      return _buildGraphConsumer(context, null);
    }
    return BlocBuilder<GraphPersonContextCubit, GraphPersonContextState>(
      buildWhen: (previous, current) =>
          previous.selectedProfile != current.selectedProfile ||
          previous.dismissedFocusId != current.dismissedFocusId ||
          previous.trustLoading != current.trustLoading ||
          previous.trustError != current.trustError,
      builder: (context, contextState) => BlocConsumer<GraphCubit, GraphState>(
        listenWhen: (previous, current) => previous.focus != current.focus,
        listener: (context, graphState) {
          _syncFocusToPersonContext(graphState.focus);
        },
        builder: (context, graphState) =>
            _buildGraphStack(context, graphState, contextState),
      ),
    );
  }

  Widget _buildGraphConsumer(
    BuildContext context,
    GraphPersonContextState? contextState,
  ) => BlocBuilder<GraphCubit, GraphState>(
    buildWhen: (previous, current) =>
        previous.isLoading != current.isLoading ||
        previous.focus != current.focus ||
        previous.focusPathDepth != current.focusPathDepth ||
        previous.positiveOnly != current.positiveOnly ||
        previous.hiddenNeighborCounts != current.hiddenNeighborCounts,
    builder: (context, graphState) =>
        _buildGraphStack(context, graphState, contextState),
  );

  Widget _buildGraphStack(
    BuildContext context,
    GraphState graphState,
    GraphPersonContextState? contextState,
  ) {
    final tt = context.tt;
    final panelVisible = contextState != null && _isPanelVisible(contextState);
    final legendAtTop =
        panelVisible && context.windowClass == WindowClass.compact;

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
            top: legendAtTop ? 0 : null,
            bottom: legendAtTop ? null : 0,
            child: SafeArea(
              top: legendAtTop,
              bottom: !legendAtTop,
              right: false,
              child: Padding(
                padding: EdgeInsets.all(tt.rowGap),
                child: _buildLegendPanel(
                  context,
                  legendAtTop: legendAtTop,
                  panelVisible: panelVisible,
                ),
              ),
            ),
          ),
        if (panelVisible)
          _buildPersonContextOverlay(context, graphState, contextState!),
      ],
    );
  }

  Widget _buildLegendPanel(
    BuildContext context, {
    required bool legendAtTop,
    required bool panelVisible,
  }) {
    final tt = context.tt;
    final legend = GraphLegendPanel(
      mode: _legendMode,
      expanded: true,
      onToggle: widget.onToggleLegend,
    );
    if (!panelVisible || context.windowClass != WindowClass.compact) {
      return legend;
    }
    final media = MediaQuery.of(context);
    final maxHeight =
        media.size.height *
            (1 - tt.graphPersonContextCompactMaxHeightFraction) -
        media.padding.top -
        media.padding.bottom -
        tt.rowGap * 4;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: legend),
    );
  }

  Widget _buildPersonContextOverlay(
    BuildContext context,
    GraphState graphState,
    GraphPersonContextState contextState,
  ) {
    final profile = contextState.selectedProfile!;
    final focusId = graphState.focus.isNotEmpty ? graphState.focus : profile.id;
    final focusedNode = _focusedUserNode(focusId);
    if (focusedNode == null) {
      return const SizedBox.shrink();
    }

    final tt = context.tt;
    final panel = GraphPersonContextPanel(
      profile: profile,
      focusedNode: focusedNode,
      graphState: graphState,
    );

    if (context.windowClass == WindowClass.compact) {
      return Positioned(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        bottom: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: tt.rowGap),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    tt.graphPersonContextCompactMaxHeightFraction,
              ),
              child: panel,
            ),
          ),
        ),
      );
    }

    return Positioned(
      top: tt.rowGap,
      right: tt.screenHPadding,
      bottom: tt.rowGap,
      width: tt.graphPersonContextWidth,
      child: SafeArea(
        left: false,
        child: panel,
      ),
    );
  }

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
          isFocused: graphState.focus.isNotEmpty && node.id == graphState.focus,
          onTap: () => _onNodeTap(node),
        ),
      );
}
