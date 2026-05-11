import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Whether `wire` should show a capability chip row (non-empty after trim).
bool capabilitySlugHasDisplay(String? wire) => wire?.trim().isNotEmpty ?? false;

/// FilterChip for one CapabilityTag, matching CapabilityChipSet per-tag styling.
class CapabilityTagFilterChip extends StatelessWidget {
  const CapabilityTagFilterChip({
    required this.tag,
    required this.l10n,
    required this.theme,
    required this.selected,
    required this.isAutomatic,
    required this.onSelected,
    super.key,
  });

  final CapabilityTag tag;
  final L10n l10n;
  final ThemeData theme;
  final bool selected;
  final bool isAutomatic;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final chip = FilterChip(
      label: Text(tag.labelOf(l10n)),
      avatar: Icon(tag.icon, size: 18),
      showCheckmark: false,
      selected: selected,
      onSelected: onSelected ?? (_) {},
      selectedColor: isAutomatic && selected
          ? theme.colorScheme.secondaryContainer
          : null,
      backgroundColor: isAutomatic
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.55)
          : null,
      side: isAutomatic
          ? BorderSide(
              color: theme.colorScheme.secondary.withValues(alpha: 0.7),
              width: 1.5,
            )
          : null,
    );
    if (onSelected == null) {
      return IgnorePointer(child: chip);
    }
    return chip;
  }
}
