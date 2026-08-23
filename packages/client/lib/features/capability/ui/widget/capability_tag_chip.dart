import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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
    final swatch = context.capabilityColors.swatchFor(tag.group);
    // Selected: saturated on-container fill so selection reads clearly against
    // the pastel unselected state (same swatch, inverted roles).
    final selectedFg = swatch.container;
    final selectedBg = swatch.onContainer;
    final idleFg = swatch.onContainer;
    final idleBg = isAutomatic
        ? swatch.container.withValues(alpha: 0.55)
        : swatch.container.withValues(alpha: 0.4);
    final chip = FilterChip(
      key: TestIds.key(TestIds.capabilityChip(tag.slug)),
      label: Text(tag.labelOf(l10n)),
      // Keep the category glyph in both states — Material's checkmark would
      // replace the avatar and hurt scannability. Selection is conveyed by
      // saturated fill, weight, and Semantics.selected (not color alone).
      avatar: Icon(
        tag.icon,
        size: 18,
        color: selected ? selectedFg : idleFg,
      ),
      showCheckmark: false,
      selected: selected,
      onSelected: onSelected,
      labelStyle: TextStyle(
        color: selected ? selectedFg : idleFg,
        fontWeight: FontWeight.w600,
      ),
      selectedColor: selectedBg,
      backgroundColor: idleBg,
      side: BorderSide(
        color: selected
            ? selectedBg
            : isAutomatic
            ? idleFg.withValues(alpha: 0.7)
            : swatch.container,
        // Keep width constant so Wrap layout does not shift on toggle.
        width: 1.5,
      ),
    );
    final semanticChip = Semantics(
      identifier: TestIds.capabilityChip(tag.slug),
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

/// Circular icon-only chip for selected capabilities in compact summary rows.
class CapabilityTagIconChip extends StatelessWidget {
  const CapabilityTagIconChip({
    required this.tag,
    required this.l10n,
    required this.onTap,
    super.key,
  });

  final CapabilityTag tag;
  final L10n l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final size = tt.metadataAvatarSize;
    final swatch = context.capabilityColors.swatchFor(tag.group);
    final fg = swatch.container;
    final bg = swatch.onContainer;
    final iconSize = size * 0.52;

    return Semantics(
      identifier: TestIds.capabilitySummaryChip(tag.slug),
      button: true,
      selected: true,
      label: tag.labelOf(l10n),
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: size,
            child: Icon(tag.icon, size: iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
