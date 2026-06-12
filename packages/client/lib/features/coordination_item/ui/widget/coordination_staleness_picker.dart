import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Staleness window options for ask / promise / blocker creation.
class CoordinationStalenessPicker extends StatelessWidget {
  const CoordinationStalenessPicker({
    required this.l10n,
    required this.selectedDays,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final L10n l10n;
  final int selectedDays;
  final ValueChanged<int> onSelected;
  final bool enabled;

  static const optionDays = [1, 3, 7, 14, 0];

  static int seedFromDraft(int? staleAfterDays) =>
      staleAfterDays ?? CoordinationItem.defaultStaleDays;

  static String labelForDays(L10n l10n, int days) => switch (days) {
        1 => l10n.coordinationStaleness1Day,
        3 => l10n.coordinationStaleness3Days,
        7 => l10n.coordinationStaleness1Week,
        14 => l10n.coordinationStaleness2Weeks,
        0 => l10n.coordinationStalenessNoDeadline,
        _ => l10n.coordinationStaleness3Days,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.coordinationStalenessLabel,
          style: textTheme.labelMedium,
        ),
        SizedBox(height: kSpacingSmall),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in optionDays)
              ChoiceChip(
                label: Text(labelForDays(l10n, days)),
                selected: selectedDays == days,
                onSelected: enabled
                    ? (_) => onSelected(days)
                    : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}
