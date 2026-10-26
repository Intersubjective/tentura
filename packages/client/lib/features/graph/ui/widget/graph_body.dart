import 'dart:async';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
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
import 'adaptive_context_overlay.dart';
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
    this.labelSize = GraphCubit.defaultNodeLabelSize,
    this.scaleRange = const Offset(0.1, 3),
    this.animationDuration = const Duration(seconds: 2),
    this.canvasSize = const GraphCanvasSize.fixed(Size(4096, 4096)),
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;
  final bool personContextEnabled;
  final bool isLabeled;

  /// Keep in sync with [GraphCubit.nodeLabelSize], which camera fits use.
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
    GraphMode.constellation => GraphLegendMode.constellation,
  };

  /// [context] is the builder's, so a window resize across 840 px re-lays the
  /// invite tree out: horizontal on expanded windows, vertical below (#464).
  SceneLayoutAlgorithm _layoutAlgorithm(BuildContext context) {
    switch (_graphCubit.mode) {
      case GraphMode.genealogy:
        return LayeredDagLayoutAlgorithm(
          rootIds: const {},
          horizontal: context.windowClass == WindowClass.expanded,
        );
      case GraphMode.forwards:
        return LayeredDagLayoutAlgorithm(
          rootIds: _graphCubit.forwardsRootIds,
        );
      case GraphMode.trust:
        return RadialHopLayoutAlgorithm(
          rootId: _graphCubit.state.me.id,
        );
      case GraphMode.constellation:
        throw UnsupportedError(
          'Constellation uses ConstellationBody, not GraphBody',
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

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          _buildGraphView(context, graphState),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearPiActive.builder(context, graphState.isLoading),
          ),
          if (_graphCubit.mode == GraphMode.trust)
            ListenableBuilder(
              listenable: _graphCubit.graphController,
              builder: (context, _) => _isTrustGraphEmpty(graphState)
                  ? _buildTrustEmptyState(context)
                  : const SizedBox.shrink(),
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
                    viewportHeight: constraints.maxHeight,
                  ),
                ),
              ),
            ),
          if (panelVisible)
            _buildPersonContextOverlay(context, graphState, contextState),
        ],
      ),
    );
  }

  /// Loaded Trust graph holding only the viewer's own node (#615). A failed
  /// first load leaves the canvas without the Me node, so it never shows.
  bool _isTrustGraphEmpty(GraphState graphState) {
    if (graphState.isLoading) {
      return false;
    }
    final controller = _graphCubit.graphController;
    final meId = graphState.me.id;
    return controller.edges.isEmpty &&
        controller.nodes.any((node) => node.id == meId);
  }

  /// One line under the centred Me node; the canvas stays pannable.
  Widget _buildTrustEmptyState(BuildContext context) {
    final tt = context.tt;
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.4),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
            child: Text(
              L10n.of(context)!.graphTrustEmpty,
              textAlign: TextAlign.center,
              style: TenturaText.body(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendPanel(
    BuildContext context, {
    required bool legendAtTop,
    required bool panelVisible,
    required double viewportHeight,
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
        viewportHeight -
        media.size.height * tt.graphPersonContextCompactMaxHeightFraction -
        media.padding.top -
        media.padding.bottom -
        tt.rowGap * 4;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight.clamp(0.0, double.infinity),
      ),
      child: legend,
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

    return AdaptiveContextOverlay(
      child: GraphPersonContextPanel(
        profile: profile,
        focusedNode: focusedNode,
        hiddenNeighborCount:
            graphState.hiddenNeighborCounts[focusedNode.id] ?? 0,
        isLoading: graphState.isLoading,
        canPageMore: context.read<GraphCubit>().canPageMore(focusedNode.id),
        onExpand: () => context.read<GraphCubit>().expandNode(focusedNode),
      ),
    );
  }

  /// "Olga → you, trust, mutual" for the selected node's direct link to the
  /// viewer — the same facts the arrowheads and stroke show on the canvas.
  String? _viewerConnectionSemantics(NodeDetails node) {
    final link = _graphCubit.viewerLink(node.id);
    if (link == null) {
      return null;
    }
    final l10n = L10n.of(context)!;
    final name = GraphNodeWidget.semanticLabel(l10n, node);
    final you = l10n.graphEdgeSemanticsYou;
    final toViewer = link.toViewer;
    final fromViewer = link.fromViewer;
    final isMutual = toViewer != null && fromViewer != null;
    String kind(double weight) => weight < 0
        ? l10n.graphEdgeSemanticsNegative
        : l10n.graphEdgeSemanticsTrust;
    final direction = isMutual
        ? l10n.graphEdgeSemanticsMutual
        : l10n.graphEdgeSemanticsOneWay;
    if (isMutual && (toViewer < 0) == (fromViewer < 0)) {
      return l10n.graphEdgeSemanticsLink(name, you, kind(toViewer), direction);
    }
    return [
      if (toViewer != null)
        l10n.graphEdgeSemanticsLink(name, you, kind(toViewer), direction),
      if (fromViewer != null)
        l10n.graphEdgeSemanticsLink(you, name, kind(fromViewer), direction),
    ].join('; ');
  }

  /// The viewer's own live-user node (the cubit's "Me" ego projection).
  bool _isViewerNode(NodeDetails node) =>
      node is UserNode && node.id == _graphCubit.state.me.id;

  Widget _buildGraphView(
    BuildContext context,
    GraphState graphState,
  ) => GraphView<NodeDetails, EdgeDetails>(
    controller: _graphCubit.graphController,
    canvasSize: widget.canvasSize,
    minScale: widget.scaleRange.dx,
    maxScale: widget.scaleRange.dy,
    layoutAlgorithm: _layoutAlgorithm(context),
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
            // The name under a marker is visual only: the node button
            // already announces it, so a screen reader read every
            // person twice (#601).
            builder: (_, node) => ExcludeSemantics(
              child: switch (node) {
                final UserNode node => Text(
                  key: ValueKey(node),
                  _isViewerNode(node) ? L10n.of(context)!.labelMe : node.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.labelSmall(
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                final GenealogyUserNode node => Text(
                  key: ValueKey(node),
                  node.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.labelSmall(
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                final GenealogyDeletedNode node => Text(
                  key: ValueKey(node),
                  node.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.labelSmall(
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
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
          node is GenealogyUserNode && node.id == _graphCubit.state.egoNodeId,
      isViewer: _isViewerNode(node),
      isOrigin: node.id == _graphCubit.originNodeId,
      isFocused: graphState.focus.isNotEmpty && node.id == graphState.focus,
      hiddenNeighborCount: graphState.hiddenNeighborCounts[node.id],
      connectionSemantics: node.id == graphState.focus
          ? _viewerConnectionSemantics(node)
          : null,
      onTap: () => _onNodeTap(node),
    ),
  );
}
