import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/animated_highlighted_edge_painter.dart';
import 'package:tentura/features/graph/ui/utils/ease_in_out_reynolds.dart';
import 'package:tentura/features/graph/ui/utils/initial_position_extractor.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';

import '../bloc/invite_genealogy_graph_cubit.dart';

class InviteGenealogyGraphBody extends StatefulWidget {
  const InviteGenealogyGraphBody({super.key});

  @override
  State<InviteGenealogyGraphBody> createState() =>
      _InviteGenealogyGraphBodyState();
}

class _InviteGenealogyGraphBodyState extends State<InviteGenealogyGraphBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final InviteGenealogyGraphCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<InviteGenealogyGraphCubit>();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<InviteGenealogyGraphCubit, InviteGenealogyGraphState>(
      buildWhen: (previous, current) =>
          previous.isLoading != current.isLoading,
      builder: (context, graphState) {
        return Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: GraphView<NodeDetails, EdgeDetails<NodeDetails>>(
                  controller: _cubit.graphController,
                  canvasSize: const GraphCanvasSize.fixed(Size(4096, 4096)),
                  minScale: 0.1,
                  maxScale: 3,
                  layoutAlgorithm: const FruchtermanReingoldAlgorithm(
                    initialPositionExtractor: initialPositionExtractor,
                    iterations: 500,
                    optimalDistance: 100,
                    showIterations: true,
                    temperature: 500,
                  ),
                  edgePainter: AnimatedHighlightedEdgePainter(
                    animation: CurvedAnimation(
                      parent: _animationController,
                      curve: const EaseInOutReynolds(),
                    ),
                    highlightRadius: 0.15,
                    highlightColor: scheme.primary,
                    isAnimated: true,
                  ),
                  labelBuilder: BottomLabelBuilder(
                    labelSize: const Size(100, 20),
                    builder: (_, node) => switch (node) {
                      final GenealogyUserNode node => Text(
                        key: ValueKey(node),
                        node.label,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.labelSmall(scheme.onSurface),
                      ),
                      final GenealogyDeletedNode node => Text(
                        key: ValueKey(node),
                        node.label,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.labelSmall(scheme.onSurfaceVariant),
                      ),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                  nodeBuilder: (_, node) => GraphNodeWidget(
                    key: ValueKey(node),
                    nodeDetails: node,
                    withRating: false,
                    onTap: () {
                      if (node case GenealogyUserNode(:final user)) {
                        context.read<ScreenCubit>().showProfile(user.id);
                      }
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearPiActive.builder(context, graphState.isLoading),
            ),
          ],
        );
      },
    );
  }
}
