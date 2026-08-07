import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Shared trust-tone glyph + label row for receiver-facing evaluation surfaces.
class EvaluationReceivedTrustToneLine extends StatelessWidget {
  const EvaluationReceivedTrustToneLine({
    required this.trustTone,
    required this.l10n,
    super.key,
  });

  final EvaluationReceivedTrustTone trustTone;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final label = switch (trustTone) {
      EvaluationReceivedTrustTone.up => l10n.evaluationReceivedTrustUpLabel,
      EvaluationReceivedTrustTone.down => l10n.evaluationReceivedTrustDownLabel,
      EvaluationReceivedTrustTone.noChange => l10n.evaluationReceivedNeutralLabel,
      EvaluationReceivedTrustTone.noBasis => l10n.evaluationReceivedNoBasisLabel,
    };

    if (trustTone == EvaluationReceivedTrustTone.noBasis) {
      return Row(
        children: [
          EvaluationTrustToneGlyph(
            icon: Icons.help_outline,
            backgroundColor: tt.surface,
            iconColor: tt.textFaint,
          ),
          SizedBox(width: tt.iconTextGap),
          Expanded(
            child: Text(
              label,
              style: TenturaText.status(tt.textFaint),
            ),
          ),
        ],
      );
    }

    final tone = switch (trustTone) {
      EvaluationReceivedTrustTone.up => TenturaTone.good,
      EvaluationReceivedTrustTone.down => TenturaTone.danger,
      EvaluationReceivedTrustTone.noChange => TenturaTone.neutral,
      EvaluationReceivedTrustTone.noBasis => TenturaTone.neutral,
    };
    final icon = switch (trustTone) {
      EvaluationReceivedTrustTone.up => Icons.arrow_upward,
      EvaluationReceivedTrustTone.down => Icons.arrow_downward,
      EvaluationReceivedTrustTone.noChange => Icons.remove,
      EvaluationReceivedTrustTone.noBasis => Icons.help_outline,
    };
    final iconColor = tenturaToneColor(tt, tone);
    final backgroundColor = iconColor.withValues(alpha: 0.12);

    return Row(
      children: [
        EvaluationTrustToneGlyph(
          icon: icon,
          backgroundColor: backgroundColor,
          iconColor: iconColor,
        ),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: TenturaStatusText(
            label,
            tone: tone,
            maxLines: null,
          ),
        ),
      ],
    );
  }
}

class EvaluationTrustToneGlyph extends StatelessWidget {
  const EvaluationTrustToneGlyph({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    super.key,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final dimension = tt.iconSize;
    return SizedBox.square(
      dimension: dimension,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(dimension / 2),
        ),
        child: Icon(
          icon,
          size: dimension * 0.55,
          color: iconColor,
        ),
      ),
    );
  }
}
