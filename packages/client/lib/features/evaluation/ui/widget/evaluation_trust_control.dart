import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_trust_selection.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Contribution-grounded two-step trust picker (fully controlled).
class EvaluationTrustControl extends StatelessWidget {
  const EvaluationTrustControl({
    required this.selection,
    required this.onChanged,
    required this.participantName,
    this.categoryError,
    this.intensityError,
    super.key,
  });

  final EvaluationTrustSelection selection;
  final ValueChanged<EvaluationTrustSelection> onChanged;
  final String participantName;
  final String? categoryError;
  final String? intensityError;

  static const intensityRowKey = Key('evaluation_trust_intensity_row');
  static const intensityColumnKey = Key('evaluation_trust_intensity_column');

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final showIntensity = selection.isDecreaseDirection ||
        selection.isIncreaseDirection;
    final showPreview = selection.isComplete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.evaluationTrustQuestion(participantName),
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tt.rowGap),
        _TrustOptionTile(
          key: TestIds.key(
            TestIds.evaluationTrustOption(EvaluationTrustSelection.zero.name),
          ),
          label: l10n.evaluationTrustNoChangeContribution,
          icon: Icons.remove,
          selected: selection == EvaluationTrustSelection.zero,
          onTap: () => onChanged(EvaluationTrustSelection.zero),
        ),
        _TrustOptionTile(
          key: TestIds.key(
            TestIds.evaluationTrustOption(
              EvaluationTrustSelection.decreasePending.name,
            ),
          ),
          label: l10n.evaluationTrustDecreasedContribution,
          icon: Icons.trending_down,
          iconColor: tt.danger,
          selected: selection.isDecreaseDirection,
          onTap: () => onChanged(EvaluationTrustSelection.decreasePending),
        ),
        _TrustOptionTile(
          key: TestIds.key(
            TestIds.evaluationTrustOption(
              EvaluationTrustSelection.increasePending.name,
            ),
          ),
          label: l10n.evaluationTrustIncreasedContribution,
          icon: Icons.trending_up,
          iconColor: tt.good,
          selected: selection.isIncreaseDirection,
          onTap: () => onChanged(EvaluationTrustSelection.increasePending),
        ),
        if (categoryError != null) ...[
          SizedBox(height: tt.tightGap),
          Semantics(
            liveRegion: true,
            child: Text(
              categoryError!,
              style: theme.textTheme.bodySmall?.copyWith(color: tt.danger),
            ),
          ),
        ],
        if (showIntensity) ...[
          SizedBox(height: tt.sectionGap),
          Text(
            l10n.evaluationTrustIntensityHeading,
            style: theme.textTheme.labelLarge,
          ),
          SizedBox(height: tt.iconTextGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = MediaQuery.sizeOf(context).width;
              final maxW = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : viewportWidth;
              final wide = maxW >= 480;
              final isDecrease = selection.isDecreaseDirection;
              final little = isDecrease
                  ? EvaluationTrustSelection.neg1
                  : EvaluationTrustSelection.pos1;
              final lot = isDecrease
                  ? EvaluationTrustSelection.neg2
                  : EvaluationTrustSelection.pos2;
              final littleRequiresReason = isDecrease;
              final lotRequiresReason = true;

              final littleTile = _IntensityOption(
                key: TestIds.key(TestIds.evaluationTrustIntensityLittle),
                label: l10n.evaluationTrustIntensityLittle,
                requiresReason: littleRequiresReason,
                reasonRequiredLabel: l10n.evaluationTrustIntensityReasonRequired,
                selected: selection == little,
                onTap: () => onChanged(little),
              );
              final lotTile = _IntensityOption(
                key: TestIds.key(TestIds.evaluationTrustIntensityLot),
                label: l10n.evaluationTrustIntensityLot,
                requiresReason: lotRequiresReason,
                reasonRequiredLabel: l10n.evaluationTrustIntensityReasonRequired,
                selected: selection == lot,
                onTap: () => onChanged(lot),
              );

              if (wide) {
                return Row(
                  key: intensityRowKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: littleTile),
                    SizedBox(width: tt.iconTextGap),
                    Expanded(child: lotTile),
                  ],
                );
              }
              return Column(
                key: intensityColumnKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  littleTile,
                  SizedBox(height: tt.tightGap),
                  lotTile,
                ],
              );
            },
          ),
          if (intensityError != null) ...[
            SizedBox(height: tt.tightGap),
            Semantics(
              liveRegion: true,
              child: Text(
                intensityError!,
                style: theme.textTheme.bodySmall?.copyWith(color: tt.danger),
              ),
            ),
          ],
        ],
        if (showPreview) ...[
          SizedBox(height: tt.sectionGap),
          Text(
            _previewText(l10n, selection, participantName),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String _previewText(
    L10n l10n,
    EvaluationTrustSelection value,
    String name,
  ) =>
      switch (value) {
        EvaluationTrustSelection.zero =>
          l10n.evaluationTrustPreviewZero(name),
        EvaluationTrustSelection.neg1 =>
          l10n.evaluationTrustPreviewNeg1(name),
        EvaluationTrustSelection.neg2 =>
          l10n.evaluationTrustPreviewNeg2(name),
        EvaluationTrustSelection.pos1 =>
          l10n.evaluationTrustPreviewPos1(name),
        EvaluationTrustSelection.pos2 =>
          l10n.evaluationTrustPreviewPos2(name),
        _ => '',
      };
}

class _TrustOptionTile extends StatelessWidget {
  const _TrustOptionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.iconColor,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color? iconColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: selected ? cs.secondaryContainer.withValues(alpha: 0.35) : null,
      borderRadius: BorderRadius.circular(context.tt.cardRadius),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? cs.onSurfaceVariant),
        title: Text(label),
        trailing: selected
            ? Icon(Icons.check_circle, color: cs.primary, size: 22)
            : Icon(Icons.circle_outlined, color: cs.outline, size: 22),
        onTap: onTap,
      ),
    );
  }
}

class _IntensityOption extends StatelessWidget {
  const _IntensityOption({
    required this.label,
    required this.requiresReason,
    required this.reasonRequiredLabel,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool requiresReason;
  final String reasonRequiredLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayLabel = requiresReason ? '$label ($reasonRequiredLabel)' : label;
    return Material(
      color: selected ? cs.secondaryContainer.withValues(alpha: 0.35) : null,
      borderRadius: BorderRadius.circular(context.tt.cardRadius),
      child: ListTile(
        title: Text(displayLabel),
        trailing: selected
            ? Icon(Icons.check_circle, color: cs.primary, size: 22)
            : Icon(Icons.circle_outlined, color: cs.outline, size: 22),
        onTap: onTap,
        dense: false,
      ),
    );
  }
}
