import 'package:flutter/material.dart';

import 'package:tentura/ui/widgets/app_choice_chip_style.dart';

/// Shared [ChoiceChip] styling for [BeaconIconPickerScreen] category filters.
class BeaconIconFilterChip extends StatelessWidget {
  const BeaconIconFilterChip({
    required this.chipStyle,
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final AppChoiceChipStyle chipStyle;
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChoiceChip(
      showCheckmark: false,
      color: chipStyle.background,
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: chipStyle.labelForeground,
      ),
      checkmarkColor: chipStyle.checkmarkColor,
      side: chipStyle.outline,
      selected: selected,
      label: Text(label),
      onSelected: onSelected,
    );
  }
}
