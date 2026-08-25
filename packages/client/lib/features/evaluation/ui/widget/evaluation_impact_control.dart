import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_value_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// The five user-facing choices for the effect of a contribution.
///
/// `noBasis` is deliberately not part of this control. It is a separate
/// participant-card action and must never be mistaken for an evaluation.
class EvaluationImpactControl extends StatelessWidget {
  const EvaluationImpactControl({
    required this.value,
    required this.onChanged,
    super.key,
  }) : assert(
         value == null || value != EvaluationValue.noBasis,
         'EvaluationImpactControl does not accept noBasis',
       );

  final EvaluationValue? value;
  final ValueChanged<EvaluationValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tt = context.tt;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tt.cardRadius),
        side: BorderSide(color: tt.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, impact) in evaluationImpactValues().indexed)
            _EvaluationImpactRow(
              impact: impact,
              label: presentEvaluationValue(impact, l10n).label,
              selected: value == impact,
              onTap: () => onChanged(impact),
              order: index,
              showDivider: index < evaluationImpactValues().length - 1,
            ),
        ],
      ),
    );
  }
}

class _EvaluationImpactRow extends StatelessWidget {
  const _EvaluationImpactRow({
    required this.impact,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.order,
    required this.showDivider,
  });

  final EvaluationValue impact;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int order;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tt = context.tt;
    final selectedColor = colorScheme.primary;
    final foreground = selected ? selectedColor : colorScheme.onSurface;

    final row = FocusTraversalOrder(
      order: NumericFocusOrder(order.toDouble()),
      child: Semantics(
        key: TestIds.key(TestIds.evaluationImpact(impact.name)),
        container: true,
        label: label,
        button: true,
        enabled: true,
        focusable: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          hoverColor: colorScheme.primary.withValues(alpha: 0.08),
          focusColor: colorScheme.primary.withValues(alpha: 0.12),
          splashColor: colorScheme.primary.withValues(alpha: 0.16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ImpactEmoji(
                    emoji: presentEvaluationValue(
                      impact,
                      L10n.of(context)!,
                    ).emoji,
                    size: tt.iconSize,
                    colored: selected,
                  ),
                  SizedBox(width: tt.iconTextGap),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: foreground,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? selectedColor
                        : colorScheme.onSurfaceVariant,
                    size: tt.iconSize,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!showDivider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [row, const TenturaHairlineDivider()],
    );
  }
}

/// Recolorable impact emoji: grayscale until the row is selected.
class _ImpactEmoji extends StatelessWidget {
  const _ImpactEmoji({
    required this.emoji,
    required this.size,
    required this.colored,
  });

  final String emoji;
  final double size;
  final bool colored;

  /// Luminance-preserving grayscale matrix (BT.709).
  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final glyph = Text(
      emoji,
      style: TextStyle(fontSize: size, height: 1),
    );
    if (colored) return glyph;
    return ColorFiltered(colorFilter: _grayscale, child: glyph);
  }
}
