import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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
    final onSelected = this.onSelected;
    final swatch = context.capabilityColors.swatchFor(tag.group);
    // Selected: the app's primary accent, so selection looks the same in every
    // group and matches the rest of the app (#436); idle chips keep the pastel
    // group tint.
    final selectedFg = theme.colorScheme.onPrimary;
    final selectedBg = theme.colorScheme.primary;
    final idleFg = swatch.onContainer;
    final idleBg = isAutomatic
        ? swatch.container.withValues(alpha: 0.55)
        : swatch.container.withValues(alpha: 0.4);
    final chip = FilterChip(
      key: TestIds.key(TestIds.capabilityChip(tag.slug)),
      // A trailing check marks selection by shape, not only by the accent
      // fill (UI review, ontology picker); the category glyph stays as avatar
      // because Material's checkmark would replace it.
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(tag.labelOf(l10n))),
          if (selected) ...[
            SizedBox(width: context.tt.tightGap * 2),
            Icon(Icons.check, size: 16, color: selectedFg),
          ],
        ],
      ),
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
    // One node for the chip: its own (nested) button node is excluded so the
    // labelled node is also the one that can be tapped and focused (#360).
    final semanticChip = Semantics(
      identifier: TestIds.capabilityChip(tag.slug),
      button: true,
      enabled: onSelected != null,
      focusable: onSelected != null,
      selected: selected,
      label: '${tag.labelOf(l10n)}, ${tag.group.labelOf(l10n)}',
      onTap: onSelected == null ? null : () => onSelected(!selected),
      excludeSemantics: true,
      child: chip,
    );
    return semanticChip;
  }
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
