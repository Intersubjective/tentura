import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/entity/edge_details.dart';
import '../../domain/entity/graph_mode.dart';
import '../../domain/entity/node_details.dart';
import '../bloc/graph_cubit.dart';

/// Graph navigation and focus actions for [TenturaTopBar.actions].
class GraphAppBarActions extends StatefulWidget {
  const GraphAppBarActions({
    required this.legendExpanded,
    required this.onToggleLegend,
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;

  @override
  State<GraphAppBarActions> createState() => _GraphAppBarActionsState();
}

class _GraphAppBarActionsState extends State<GraphAppBarActions> {
  GraphController<NodeDetails, EdgeDetails<NodeDetails>>? _controller;

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
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

  void _attachController(
    GraphController<NodeDetails, EdgeDetails<NodeDetails>> controller,
  ) {
    if (_controller == controller) {
      return;
    }
    _controller?.removeListener(_onControllerChanged);
    _controller = controller;
    controller.addListener(_onControllerChanged);
  }

  void _openNodeDetails(NodeDetails node) {
    final screenCubit = context.read<ScreenCubit>();
    switch (node) {
      case final UserNode n:
        screenCubit.showProfile(n.id);
      case final GenealogyUserNode n:
        screenCubit.showProfile(n.user.id);
      case final BeaconNode n:
        screenCubit.showBeacon(n.id);
      case GenealogyDeletedNode():
        break;
    }
  }

  IconButton _navIconButton({
    required Key key,
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
    required double minSize,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      constraints: BoxConstraints(
        minWidth: minSize,
        minHeight: minSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GraphCubit, GraphState>(
      buildWhen: (previous, current) =>
          previous.isLoading != current.isLoading ||
          previous.focus != current.focus ||
          previous.focusPathDepth != current.focusPathDepth ||
          previous.hiddenNeighborCounts != current.hiddenNeighborCounts,
      builder: (context, graphState) {
        final cubit = context.read<GraphCubit>();
        final controller = cubit.graphController;
        _attachController(controller);

        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final mode = cubit.mode;

        NodeDetails? focusedNode;
        final focusId = graphState.focus;
        if (focusId.isNotEmpty) {
          for (final node in controller.nodes) {
            if (node.id == focusId) {
              focusedNode = node;
              break;
            }
          }
        }

        final focused = focusedNode;
        final canFit = controller.canLayout && !controller.isLayoutSettling;

        final contextActions = <Widget>[];
        if (focused != null && mode != GraphMode.trust) {
          final openDetails = switch (focused) {
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
              _navIconButton(
                key: TestIds.key(TestIds.graphOpenDetails),
                tooltip: openDetails.tooltip,
                onPressed: () => _openNodeDetails(focused),
                icon: openDetails.icon,
                minSize: tt.buttonHeight,
              ),
            );
          }
        }

        final navActions = <Widget>[];
        switch (mode) {
          case GraphMode.trust:
          case GraphMode.genealogy:
            navActions.add(
              _navIconButton(
                key: TestIds.key(TestIds.graphBack),
                tooltip: l10n.graphBack,
                onPressed: graphState.focusPathDepth > 1
                    ? cubit.popFocus
                    : null,
                icon: Icons.arrow_back,
                minSize: tt.buttonHeight,
              ),
            );
            navActions.add(
              _navIconButton(
                key: TestIds.key(TestIds.graphFit),
                tooltip: l10n.graphFitPath,
                onPressed: canFit ? cubit.fitCurrentPath : null,
                icon: Icons.fit_screen_outlined,
                minSize: tt.buttonHeight,
              ),
            );
            navActions.add(
              _navIconButton(
                key: TestIds.key(TestIds.graphResetToEgo),
                tooltip: mode == GraphMode.genealogy
                    ? l10n.graphResetGenealogyOrigin
                    : l10n.graphResetToEgo,
                onPressed: cubit.resetToEgo,
                icon: Icons.home_outlined,
                minSize: tt.buttonHeight,
              ),
            );
          case GraphMode.forwards:
            navActions.add(
              _navIconButton(
                key: TestIds.key(TestIds.graphCenterView),
                tooltip: l10n.graphCenterView,
                onPressed: canFit
                    ? () => cubit.jumpToEgo(resetScale: true)
                    : null,
                icon: Icons.center_focus_strong_outlined,
                minSize: tt.buttonHeight,
              ),
            );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...contextActions,
            ...navActions,
            IconButton(
              tooltip: widget.legendExpanded
                  ? l10n.graphLegendClose
                  : l10n.graphLegendOpen,
              onPressed: widget.onToggleLegend,
              icon: Icon(
                widget.legendExpanded ? Icons.map : Icons.map_outlined,
              ),
              constraints: BoxConstraints(
                minWidth: tt.buttonHeight,
                minHeight: tt.buttonHeight,
              ),
            ),
          ],
        );
      },
    );
  }
}
