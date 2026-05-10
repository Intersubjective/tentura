import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Whether `wire` should show a capability chip row (non-empty after trim).
bool capabilitySlugHasDisplay(String? wire) => wire?.trim().isNotEmpty ?? false;

/// One FilterChip per known slug (icon + label, same styling as CapabilityChipSet);
/// unknown slugs render as a plain [Chip] with the raw wire text.
class CapabilitySlugReadonlyChips extends StatelessWidget {
  const CapabilitySlugReadonlyChips({
    required this.slugs,
    super.key,
  });

  final List<String> slugs;

  @override
  Widget build(BuildContext context) {
    final trimmed =
        slugs.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final slug in trimmed) _slugChip(slug: slug, l10n: l10n, theme: theme),
      ],
    );
  }

  Widget _slugChip({
    required String slug,
    required L10n l10n,
    required ThemeData theme,
  }) {
    final tag = CapabilityTag.fromSlug(slug);
    if (tag != null) {
      return CapabilityTagFilterChip(
        tag: tag,
        l10n: l10n,
        theme: theme,
        selected: true,
        isAutomatic: false,
        onSelected: null,
      );
    }
    return _UnknownSlugChip(slug: slug, theme: theme);
  }
}

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

class _UnknownSlugChip extends StatelessWidget {
  const _UnknownSlugChip({
    required this.slug,
    required this.theme,
  });

  final String slug;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(slug),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      side: BorderSide(
        color: theme.colorScheme.outlineVariant,
      ),
    );
  }
}
