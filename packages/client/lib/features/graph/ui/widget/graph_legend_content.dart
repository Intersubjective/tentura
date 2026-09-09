import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/components/tentura_count_badge.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/contact_badge_legend.dart';

import '../../domain/entity/graph_edge_colors.dart';
import '../bloc/graph_cubit.dart';
import 'graph_legend_edge_swatch.dart';
import 'graph_legend_mode.dart';

/// Mode-aware legend body for trust / forwards / genealogy graphs.
class GraphLegendContent extends StatelessWidget {
  const GraphLegendContent({
    required this.mode,
    super.key,
  });

  final GraphLegendMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final edgeColors = GraphEdgeColors.fromTokens(tt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const ContactBadgeLegend(),
        if (mode == GraphLegendMode.forwards) ...[
          SizedBox(height: tt.sectionGap),
          Text(
            l10n.graphLegendForwardEligible,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        SizedBox(height: tt.sectionGap),
        Text(
          l10n.graphLegendEdgesTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        SizedBox(height: tt.rowGap),
        ..._edgeRows(context, edgeColors),
        SizedBox(height: tt.sectionGap),
        Text(
          l10n.graphLegendOtherTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        SizedBox(height: tt.rowGap),
        ..._otherRows(context, scheme),
      ],
    );
  }

  List<Widget> _edgeRows(BuildContext context, GraphEdgeColors edgeColors) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    Widget row(String label, Color color, {double strokeWidth = 2}) {
      return Padding(
        padding: EdgeInsets.only(bottom: tt.tightGap),
        child: _LegendRow(
          swatch: GraphLegendEdgeSwatch(
            color: color,
            strokeWidth: strokeWidth,
          ),
          label: label,
        ),
      );
    }

    return switch (mode) {
      GraphLegendMode.trust => [
        row(l10n.graphLegendEdgeEgo, edgeColors.ego, strokeWidth: 3),
        row(l10n.graphLegendEdgeOther, edgeColors.neutral),
        _NegativeEdgeToggleRow(
          label: l10n.graphLegendEdgeNegative,
          color: edgeColors.negative,
        ),
        row(l10n.graphLegendEdgeMutual, edgeColors.neutral),
      ],
      GraphLegendMode.forwards => [
        row(l10n.graphLegendEdgeEgo, edgeColors.ego, strokeWidth: 3),
        row(l10n.graphLegendEdgeForwardOther, edgeColors.neutral),
      ],
      GraphLegendMode.genealogy => [
        row(l10n.graphLegendEdgeGenealogyEgo, edgeColors.ego, strokeWidth: 3),
        row(
          l10n.graphLegendEdgeGenealogyTarget,
          edgeColors.target,
          strokeWidth: 3,
        ),
        row(l10n.graphLegendEdgeGenealogyNeutral, edgeColors.neutral),
      ],
      GraphLegendMode.constellation => [
        row(l10n.graphLegendConstellationDirectConnection, scheme.outline),
        _ConstellationDashedEdgeRow(
          label: l10n.graphLegendConstellationIndirectConnection,
          color: scheme.outlineVariant,
        ),
        _ConstellationAttachmentEdgeRow(
          label: l10n.graphLegendConstellationRequestLink,
          color: scheme.secondary,
        ),
        _ConstellationDashedEdgeRow(
          label: l10n.graphLegendConstellationWiderNetworkReach,
          color: scheme.outlineVariant,
        ),
      ],
    };
  }

  List<Widget> _otherRows(BuildContext context, ColorScheme scheme) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    Widget row(Widget swatch, String label) => Padding(
      padding: EdgeInsets.only(bottom: tt.tightGap),
      child: _LegendRow(swatch: swatch, label: label),
    );

    final rows = <Widget>[
      row(
        _SelfHaloSwatch(color: scheme.primary),
        l10n.graphLegendSelf,
      ),
    ];

    switch (mode) {
      case GraphLegendMode.trust:
        rows.addAll([
          row(
            TenturaCountBadge(count: 3, backgroundColor: scheme.primary),
            l10n.graphLegendHiddenNeighbors,
          ),
          row(
            TenturaIdentityTileFrame(
              size: tt.avatarSize * 0.75,
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    Icons.campaign_outlined,
                    size: tt.avatarSize * 0.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            l10n.graphLegendRequestNode,
          ),
          row(
            _RatingArcSwatch(color: scheme.primary),
            l10n.graphLegendRatingArcs,
          ),
        ]);
      case GraphLegendMode.forwards:
        rows.add(
          row(
            _HelpOffererRingSwatch(color: scheme.tertiary),
            l10n.graphLegendHelpOfferer,
          ),
        );
      case GraphLegendMode.genealogy:
        rows.addAll([
          row(
            TenturaCountBadge(count: 3, backgroundColor: scheme.primary),
            l10n.graphLegendHiddenChildren,
          ),
          row(
            CircleAvatar(
              radius: tt.avatarSize / 2,
              child: Icon(
                Icons.person_off_outlined,
                size: tt.avatarSize * 0.45,
              ),
            ),
            l10n.graphLegendDeletedInvitee,
          ),
        ]);
      case GraphLegendMode.constellation:
        rows.addAll([
          row(
            TenturaIdentityTileFrame(
              size: tt.avatarSize * 0.75,
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    Icons.campaign_outlined,
                    size: tt.avatarSize * 0.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            l10n.graphLegendRequestNode,
          ),
        ]);
    }

    return rows;
  }
}

class _NegativeEdgeToggleRow extends StatelessWidget {
  const _NegativeEdgeToggleRow({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return BlocSelector<GraphCubit, GraphState, bool>(
      selector: (state) => state.positiveOnly,
      builder: (context, positiveOnly) {
        final cubit = context.read<GraphCubit>();
        final layerVisible = !positiveOnly;
        void toggle() => cubit.togglePositiveOnly();

        return Padding(
          padding: EdgeInsets.only(bottom: tt.tightGap),
          child: Semantics(
            label: l10n.graphLegendToggleNegative,
            toggled: layerVisible,
            child: InkWell(
              onTap: toggle,
              borderRadius: BorderRadius.circular(tt.cardRadius),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: tt.tightGap / 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: tt.avatarSize,
                      child: Center(
                        child: GraphLegendEdgeSwatch(
                          color: layerVisible
                              ? color
                              : Color.alphaBlend(
                                  scheme.surfaceContainerHigh.withValues(
                                    alpha: 0.65,
                                  ),
                                  color,
                                ),
                        ),
                      ),
                    ),
                    SizedBox(width: tt.avatarTextGap),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: layerVisible ? null : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Switch(
                      value: layerVisible,
                      onChanged: (_) => toggle(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.swatch,
    required this.label,
  });

  final Widget swatch;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Semantics(
      label: label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: tt.avatarSize,
            child: Center(child: swatch),
          ),
          SizedBox(width: tt.avatarTextGap),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelfHaloSwatch extends StatelessWidget {
  const _SelfHaloSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = context.tt.avatarSize;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: CircleAvatar(
          radius: size / 2 - 3,
          child: const Icon(Icons.person_outline, size: 18),
        ),
      ),
    );
  }
}

class _HelpOffererRingSwatch extends StatelessWidget {
  const _HelpOffererRingSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = context.tt.avatarSize;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: CircleAvatar(
              radius: size / 2 - 4,
              child: const Icon(Icons.person_outline, size: 18),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingArcSwatch extends StatelessWidget {
  const _RatingArcSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = context.tt.avatarSize;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RatingArcSwatchPainter(color: color),
        child: Center(
          child: CircleAvatar(
            radius: size / 2 - 6,
            child: const Icon(Icons.person_outline, size: 16),
          ),
        ),
      ),
    );
  }
}

class _RatingArcSwatchPainter extends CustomPainter {
  const _RatingArcSwatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -0.8,
      1.2,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.6,
      0.9,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RatingArcSwatchPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ConstellationDashedEdgeRow extends StatelessWidget {
  const _ConstellationDashedEdgeRow({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(bottom: tt.tightGap),
      child: _LegendRow(
        swatch: CustomPaint(
          size: Size(tt.avatarSize, tt.iconSize),
          painter: _ConstellationDashedSwatchPainter(color: color),
        ),
        label: label,
      ),
    );
  }
}

class _ConstellationDashedSwatchPainter extends CustomPainter {
  const _ConstellationDashedSwatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationDashedSwatchPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ConstellationAttachmentEdgeRow extends StatelessWidget {
  const _ConstellationAttachmentEdgeRow({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(bottom: tt.tightGap),
      child: _LegendRow(
        swatch: CustomPaint(
          size: Size(tt.avatarSize * 0.6, tt.iconSize),
          painter: _ConstellationAttachmentSwatchPainter(color: color),
        ),
        label: label,
      ),
    );
  }
}

class _ConstellationAttachmentSwatchPainter extends CustomPainter {
  const _ConstellationAttachmentSwatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final start = Offset(size.width * 0.15, size.height / 2);
    final end = Offset(size.width * 0.85, size.height / 2);
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(
    covariant _ConstellationAttachmentSwatchPainter oldDelegate,
  ) => oldDelegate.color != color;
}
