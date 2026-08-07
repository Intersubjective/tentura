import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/entity/edge_details.dart';
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GraphCubit, GraphState>(
      buildWhen: (previous, current) =>
          previous.isLoading != current.isLoading ||
          previous.focus != current.focus ||
          previous.hiddenNeighborCounts != current.hiddenNeighborCounts,
      builder: (context, graphState) {
        final cubit = context.read<GraphCubit>();
        final controller = cubit.graphController;
        _attachController(controller);

        final l10n = L10n.of(context)!;
        final tt = context.tt;

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
        final canExpand = focused != null &&
            !graphState.isLoading &&
            controller.canLayout &&
            !controller.isLayoutSettling &&
            cubit.canPageMore(focused.id);

        final contextActions = <Widget>[];
        if (focused != null) {
          if (canExpand) {
            contextActions.add(
              IconButton(
                key: TestIds.key(TestIds.graphExpand),
                tooltip: l10n.inboxProvenanceExpand,
                onPressed: () => cubit.expandNode(focused),
                icon: const Icon(Icons.hub_outlined),
                constraints: BoxConstraints(
                  minWidth: tt.buttonHeight,
                  minHeight: tt.buttonHeight,
                ),
              ),
            );
          }
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
              IconButton(
                key: TestIds.key(TestIds.graphOpenDetails),
                tooltip: openDetails.tooltip,
                onPressed: () => _openNodeDetails(focused),
                icon: Icon(openDetails.icon),
                constraints: BoxConstraints(
                  minWidth: tt.buttonHeight,
                  minHeight: tt.buttonHeight,
                ),
              ),
            );
          }
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...contextActions,
            IconButton(
              key: TestIds.key(TestIds.graphResetToEgo),
              tooltip: l10n.graphResetToEgo,
              onPressed: () => cubit.jumpToEgo(resetScale: true),
              icon: const Icon(Icons.home_outlined),
              constraints: BoxConstraints(
                minWidth: tt.buttonHeight,
                minHeight: tt.buttonHeight,
              ),
            ),
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
