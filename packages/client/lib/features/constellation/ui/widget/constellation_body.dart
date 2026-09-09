import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_mode.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_panel.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/constellation_cubit.dart';

class ConstellationBody extends StatelessWidget {
  const ConstellationBody({
    required this.legendExpanded,
    required this.onToggleLegend,
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;

  static const _canvasSize = GraphCanvasSize.fixed(Size(4096, 4096));

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.graphRevision != current.graphRevision ||
          previous.loadError != current.loadError,
      builder: (context, state) {
        final cubit = context.read<ConstellationCubit>();
        final tt = context.tt;

        if (state.status is StateIsLoading && state.field == null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              const Center(child: CircularProgressIndicator()),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearPiActive.builder(context, true),
              ),
            ],
          );
        }

        if (state.loadError != null && state.field == null) {
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: Text(
                state.loadError.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        final resolved = state.resolvedField;
        if (resolved == null || cubit.layoutEgoId.isEmpty) {
          return const SizedBox.shrink();
        }

        final layoutAlgorithm = ConstellationLayoutAlgorithm(
          egoId: cubit.layoutEgoId,
          paths: resolved.paths,
          keptPeerIds: resolved.keptPeerIds,
          maxHops: kConstellationLayoutMaxHops,
          visibleRequestsByAuthor: cubit.layoutVisibleRequestsByAuthor,
          egoOwnRequestIds: cubit.layoutEgoOwnRequestIds,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            GraphView<NodeDetails, EdgeDetails<NodeDetails>>(
              controller: cubit.graphController,
              canvasSize: _canvasSize,
              minScale: 0.1,
              maxScale: 3,
              layoutAlgorithm: layoutAlgorithm,
              layoutTransitionDuration: const Duration(milliseconds: 350),
              edgePainter: ConstellationEdgePainter(
                edgeKinds: cubit.edgeKinds,
                colorScheme: Theme.of(context).colorScheme,
              ),
              labelBuilder: BottomLabelBuilder(
                labelSize: const Size(100, 20),
                builder: (_, node) => switch (node) {
                  FieldPersonNode(:final person) => Text(
                    person.shownName,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.labelSmall(
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  FieldRequestNode(:final request) => Text(
                    request.title,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.labelSmall(
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
              nodeBuilder: (_, node) => switch (node) {
                FieldPersonNode(:final ring) => GraphNodeWidget(
                  nodeDetails: node,
                  hiddenNeighborCount: null,
                  isOrigin: ring == 0,
                ),
                FieldRequestNode() => GraphNodeWidget(
                  nodeDetails: node,
                  hiddenNeighborCount: null,
                ),
                _ => const SizedBox.shrink(),
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearPiActive.builder(
                context,
                state.status is StateIsLoading,
              ),
            ),
            if (legendExpanded)
              Positioned(
                left: 0,
                bottom: 0,
                child: SafeArea(
                  right: false,
                  child: Padding(
                    padding: EdgeInsets.all(tt.rowGap),
                    child: GraphLegendPanel(
                      mode: GraphLegendMode.constellation,
                      expanded: true,
                      onToggle: onToggleLegend,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class ConstellationEdgePainter
    implements EdgePainter<NodeDetails, EdgeDetails<NodeDetails>> {
  const ConstellationEdgePainter({
    required this.edgeKinds,
    required this.colorScheme,
  });

  final Map<String, ConstellationEdgeKind> edgeKinds;
  final ColorScheme colorScheme;

  static const _pathStroke = 2.0;
  static const _attachmentStroke = 1.5;
  static const _stubStroke = 1.5;
  static const _dashLength = 6.0;
  static const _dashGap = 4.0;

  @override
  void paint(
    Canvas canvas,
    EdgeDetails<NodeDetails> edge,
    Offset src,
    Offset dst,
  ) {
    final kind = edgeKinds['${edge.source.id}\0${edge.destination.id}'];
    if (kind == null) {
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    switch (kind) {
      case ConstellationEdgeKind.tier1Path:
        paint
          ..color = colorScheme.outline
          ..strokeWidth = _pathStroke;
        canvas.drawLine(src, dst, paint);
      case ConstellationEdgeKind.tier2Path:
        paint
          ..color = colorScheme.outlineVariant
          ..strokeWidth = _pathStroke;
        _drawDashedLine(canvas, src, dst, paint);
      case ConstellationEdgeKind.attachment:
        paint
          ..color = colorScheme.secondary
          ..strokeWidth = _attachmentStroke;
        final trimmed = _trimAttachmentLine(
          src: src,
          dst: dst,
          sourceRadius: edge.source.size / 2,
          destinationRadius: edge.destination.size / 2,
        );
        canvas.drawLine(trimmed.$1, trimmed.$2, paint);
      case ConstellationEdgeKind.ringStub:
        paint
          ..color = colorScheme.outlineVariant.withValues(alpha: 0.7)
          ..strokeWidth = _stubStroke;
        _drawDashedLine(canvas, src, dst, paint);
    }
  }

  (Offset, Offset) _trimAttachmentLine({
    required Offset src,
    required Offset dst,
    required double sourceRadius,
    required double destinationRadius,
  }) {
    final delta = dst - src;
    final length = delta.distance;
    if (length <= sourceRadius + destinationRadius) {
      return (src, dst);
    }
    final direction = delta / length;
    final start = src + direction * (sourceRadius + 2);
    final end = dst - direction * (destinationRadius + length * 0.15);
    return (start, end);
  }

  void _drawDashedLine(Canvas canvas, Offset src, Offset dst, Paint paint) {
    final delta = dst - src;
    final length = delta.distance;
    if (length <= 0) {
      return;
    }
    final direction = delta / length;
    var travelled = 0.0;
    while (travelled < length) {
      final dashEnd = math.min(travelled + _dashLength, length);
      canvas.drawLine(
        src + direction * travelled,
        src + direction * dashEnd,
        paint,
      );
      travelled += _dashLength + _dashGap;
    }
  }
}
