import 'package:flutter/material.dart';

import 'package:tentura/design_system/components/tentura_count_badge.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/contact_badge_legend.dart';

import '../../domain/entity/graph_edge_colors.dart';
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
    final directed = mode != GraphLegendMode.trust;

    Widget row(String label, Color color, {double strokeWidth = 2}) {
      return Padding(
        padding: EdgeInsets.only(bottom: tt.tightGap),
        child: _LegendRow(
          swatch: GraphLegendEdgeSwatch(
            color: color,
            directed: directed,
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
        row(l10n.graphLegendEdgeNegative, edgeColors.negative),
        Padding(
          padding: EdgeInsets.only(top: tt.tightGap),
          child: Text(
            l10n.graphLegendEdgeUndirected,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
      GraphLegendMode.forwards => [
        row(l10n.graphLegendEdgeEgo, edgeColors.ego, strokeWidth: 3),
        row(l10n.graphLegendEdgeForwardOther, edgeColors.neutral),
        Padding(
          padding: EdgeInsets.only(top: tt.tightGap),
          child: Text(
            l10n.graphLegendEdgeForwardDirected,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
      GraphLegendMode.genealogy => [
        row(l10n.graphLegendEdgeGenealogyEgo, edgeColors.ego, strokeWidth: 3),
        row(l10n.graphLegendEdgeGenealogyTarget, edgeColors.target, strokeWidth: 3),
        row(l10n.graphLegendEdgeGenealogyNeutral, edgeColors.neutral),
        Padding(
          padding: EdgeInsets.only(top: tt.tightGap),
          child: Text(
            l10n.graphLegendEdgeGenealogyDirected,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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
            const Icon(Icons.image_outlined),
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
    }

    return rows;
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
