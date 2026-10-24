import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_badge.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_node_ring_layer.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_presence_halo_layer.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_status_marker.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/contact_badge_legend.dart';

import '../../domain/entity/graph_edge_colors.dart';
import '../bloc/graph_cubit.dart';
import '../utils/graph_edge_style.dart';
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
        // Field avatars carry no contact badge; they show trust rings (#643).
        if (mode == GraphLegendMode.constellation)
          const _ConstellationTrustLegend()
        else
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

    Widget row(
      String label,
      GraphEdgeKind kind, {
      bool arrowAtStart = false,
      bool arrowAtEnd = false,
    }) {
      return Padding(
        padding: EdgeInsets.only(bottom: tt.tightGap),
        child: _LegendRow(
          swatch: GraphLegendEdgeSwatch(
            style: graphEdgeStyle(kind, edgeColors),
            arrowAtStart: arrowAtStart,
            arrowAtEnd: arrowAtEnd,
          ),
          label: label,
        ),
      );
    }

    return switch (mode) {
      GraphLegendMode.trust => [
        row(l10n.graphLegendEdgeEgo, GraphEdgeKind.ego),
        row(l10n.graphLegendEdgeOther, GraphEdgeKind.other),
        _NegativeEdgeToggleRow(
          label: l10n.graphLegendEdgeNegative,
          style: graphEdgeStyle(GraphEdgeKind.negative, edgeColors),
        ),
        row(
          l10n.graphLegendEdgeMutual,
          GraphEdgeKind.other,
          arrowAtStart: true,
          arrowAtEnd: true,
        ),
        row(l10n.graphLegendEdgeOneWay, GraphEdgeKind.other, arrowAtEnd: true),
        Padding(
          padding: EdgeInsets.only(bottom: tt.tightGap),
          child: Text(
            l10n.graphLegendEdgeArrowsHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
      GraphLegendMode.forwards => [
        row(l10n.graphLegendEdgeEgo, GraphEdgeKind.ego),
        row(l10n.graphLegendEdgeForwardOther, GraphEdgeKind.other),
      ],
      GraphLegendMode.genealogy => [
        row(l10n.graphLegendEdgeGenealogyEgo, GraphEdgeKind.genealogyEgo),
        row(l10n.graphLegendEdgeGenealogyTarget, GraphEdgeKind.genealogyTarget),
        row(
          l10n.graphLegendEdgeGenealogyNeutral,
          GraphEdgeKind.genealogyNeutral,
        ),
      ],
      GraphLegendMode.constellation => () {
        final tier1Style = constellationEdgeStyle(
          ConstellationEdgeKind.tier1Path,
          tt,
          scheme,
        );
        final tier2Style = constellationEdgeStyle(
          ConstellationEdgeKind.tier2Path,
          tt,
          scheme,
        );
        final attachmentStyle = constellationEdgeStyle(
          ConstellationEdgeKind.attachment,
          tt,
          scheme,
        );
        final ringStubStyle = constellationEdgeStyle(
          ConstellationEdgeKind.ringStub,
          tt,
          scheme,
        );
        final grewFromStyle = constellationEdgeStyle(
          ConstellationEdgeKind.grewFrom,
          tt,
          scheme,
        );
        return [
          _ConstellationEdgeRow(
            label: l10n.graphLegendConstellationDirectConnection,
            hint: l10n.graphLegendConstellationDirectConnectionHint,
            style: tier1Style,
          ),
          _ConstellationEdgeRow(
            label: l10n.graphLegendConstellationIndirectConnection,
            hint: l10n.graphLegendConstellationIndirectConnectionHint,
            style: tier2Style,
          ),
          _ConstellationEdgeRow(
            label: l10n.graphLegendConstellationRequestLink,
            hint: l10n.graphLegendConstellationRequestLinkHint,
            style: attachmentStyle,
          ),
          _ConstellationEdgeRow(
            label: l10n.graphLegendConstellationWiderNetworkReach,
            hint: l10n.graphLegendConstellationWiderNetworkReachHint,
            style: ringStubStyle,
          ),
          _ConstellationEdgeRow(
            label: l10n.beaconGrewFromPost,
            style: grewFromStyle,
          ),
          _ConstellationEdgeRow(
            key: const ValueKey('constellation.legend.edge.mutualTrust'),
            label: l10n.graphLegendConstellationMutualTrust,
            hint: l10n.graphLegendConstellationMutualTrustHint,
            style: constellationEdgeStyle(
              ConstellationEdgeKind.mutualTrust,
              tt,
              scheme,
            ),
          ),
        ];
      }(),
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
          Padding(
            padding: EdgeInsets.only(bottom: tt.tightGap),
            child: _LegendRow(
              key: const ValueKey('constellation.legend.presence.online'),
              swatch: const ConstellationPresenceHaloSwatch(),
              label: l10n.constellationPresenceOnline,
              hint: l10n.constellationPresenceOnlineHint,
            ),
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
            const ConstellationRequestStatusMarker(
              rawStatus: 0,
              isPinned: false,
              showPin: false,
            ),
            l10n.graphLegendConstellationRequestStatusOpen,
          ),
          row(
            const ConstellationRequestStatusMarker(
              rawStatus: 7,
              isPinned: false,
              showPin: false,
            ),
            l10n.graphLegendConstellationRequestStatusNeedsMoreHelp,
          ),
          row(
            const ConstellationRequestStatusMarker(
              rawStatus: 8,
              isPinned: false,
              showPin: false,
            ),
            l10n.graphLegendConstellationRequestStatusEnoughHelp,
          ),
          row(
            const ConstellationRequestStatusMarker(
              rawStatus: 5,
              isPinned: false,
              showPin: false,
            ),
            l10n.graphLegendConstellationRequestStatusWrappingUp,
          ),
          row(
            const ConstellationRequestStatusMarker(
              rawStatus: 4,
              isPinned: false,
              showPin: false,
            ),
            l10n.graphLegendConstellationRequestStatusClosed,
          ),
          row(
            const ConstellationRequestStatusMarker(
              rawStatus: null,
              isPinned: true,
              showStatus: false,
            ),
            l10n.graphLegendConstellationPinMarker,
          ),
        ]);
    }

    return rows;
  }
}

/// The field's trust rings on people (#643): one row per state, each with a
/// one-sentence hint on hover and on tap.
class _ConstellationTrustLegend extends StatelessWidget {
  const _ConstellationTrustLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.constellationTrustLegendTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        SizedBox(height: tt.rowGap),
        for (final badge in ConstellationTrustBadge.values)
          Padding(
            padding: EdgeInsets.only(bottom: tt.tightGap),
            child: _LegendRow(
              key: ValueKey('constellation.legend.trust.${badge.name}'),
              swatch: ConstellationTrustBadgeSwatch(badge: badge),
              label: constellationTrustBadgeLabel(l10n, badge),
              hint: constellationTrustBadgeHint(l10n, badge),
            ),
          ),
      ],
    );
  }
}

class _NegativeEdgeToggleRow extends StatelessWidget {
  const _NegativeEdgeToggleRow({required this.label, required this.style});

  final String label;
  final GraphEdgeStyle style;

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
            container: true,
            label: l10n.graphLegendToggleNegative,
            toggled: layerVisible,
            excludeSemantics: true,
            onTap: toggle,
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
                          style: style,
                          color: layerVisible
                              ? style.color
                              : Color.alphaBlend(
                                  scheme.surfaceContainerHigh.withValues(
                                    alpha: 0.65,
                                  ),
                                  style.color,
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
                    Switch(value: layerVisible, onChanged: (_) => toggle()),
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

class _LegendRow extends StatefulWidget {
  const _LegendRow({
    required this.swatch,
    required this.label,
    this.hint,
    super.key,
  });

  final Widget swatch;
  final String label;

  /// One plain sentence on what the row means (#261). Shown on hover and on
  /// tap — never on long-press only — and read out as the row's hint.
  final String? hint;

  @override
  State<_LegendRow> createState() => _LegendRowState();
}

class _LegendRowState extends State<_LegendRow> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final label = widget.label;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: tt.avatarSize,
          child: Center(child: widget.swatch),
        ),
        SizedBox(width: tt.avatarTextGap),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        if (widget.hint != null) ...[
          SizedBox(width: tt.iconTextGap),
          ExcludeSemantics(
            child: Icon(
              Icons.info_outline,
              size: tt.iconSize * 0.85,
              color: tt.textMuted,
            ),
          ),
        ],
      ],
    );
    final hintText = widget.hint;
    // The row is read once, by its label (#678): the visible text and the
    // swatch's own label are excluded.
    if (hintText == null) {
      return Semantics(
        container: true,
        label: label,
        excludeSemantics: true,
        child: row,
      );
    }
    // A focusable button whose hint is the explanation; activating it shows
    // the same tooltip a tap does (#678).
    return Tooltip(
      key: _tooltipKey,
      message: hintText,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: _legendHintShowDuration,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        label: label,
        hint: hintText,
        excludeSemantics: true,
        onTap: () {
          _tooltipKey.currentState?.ensureTooltipVisible();
        },
        child: row,
      ),
    );
  }
}

/// Long enough to read one sentence after a tap.
const _legendHintShowDuration = Duration(seconds: 6);

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

class _ConstellationEdgeRow extends StatelessWidget {
  const _ConstellationEdgeRow({
    required this.label,
    required this.style,
    this.hint,
    super.key,
  });

  final String label;
  final ConstellationEdgeStyle style;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(bottom: tt.tightGap),
      child: _LegendRow(
        swatch: GraphLegendConstellationEdgeSwatch(style: style),
        label: label,
        hint: hint,
      ),
    );
  }
}
