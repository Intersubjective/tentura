import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/capability_group.dart';
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
      // Show the tag icon when unselected; the Material checkmark replaces it
      // when selected so the selection state is unmistakable.
      avatar: selected ? null : Icon(tag.icon, size: 18),
      showCheckmark: true,
      selected: selected,
      onSelected: onSelected,
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
    final semanticChip = Semantics(
      button: true,
      selected: selected,
      label: '${tag.labelOf(l10n)}, ${_groupLabel(l10n, tag.group)}',
      child: chip,
    );
    return semanticChip;
  }

  static String _groupLabel(L10n l10n, CapabilityGroup group) =>
      switch (group) {
        CapabilityGroup.logistics => l10n.capabilityGroupLogistics,
        CapabilityGroup.communication => l10n.capabilityGroupCommunication,
        CapabilityGroup.knowledge => l10n.capabilityGroupKnowledge,
        CapabilityGroup.care => l10n.capabilityGroupCare,
        CapabilityGroup.resources => l10n.capabilityGroupResources,
        CapabilityGroup.technical => l10n.capabilityGroupTechnical,
        CapabilityGroup.special => l10n.capabilityGroupSpecial,
      };
}
