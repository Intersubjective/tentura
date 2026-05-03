import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// A grouped, selectable chip set for capability tags.
///
/// [selectedSlugs] is the current selection; [onChanged] fires on every toggle.
class CapabilityChipSet extends StatelessWidget {
  const CapabilityChipSet({
    required this.selectedSlugs,
    required this.onChanged,
    this.automaticSlugs = const {},
    super.key,
  });

  final Set<String> selectedSlugs;

  /// Slugs that were added automatically (via forward/commit/close-ack).
  /// These chips are shown in a secondary color to distinguish them from
  /// manually-added ones.
  final Set<String> automaticSlugs;

  final void Function(Set<String> slugs) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final group in CapabilityGroup.values)
          _GroupSection(
            group: group,
            groupLabel: _groupLabel(l10n, group),
            tags: CapabilityTag.values
                .where((t) => t.group == group)
                .toList(),
            selectedSlugs: selectedSlugs,
            automaticSlugs: automaticSlugs,
            onToggle: (slug, selected) {
              final next = Set<String>.from(selectedSlugs);
              selected ? next.add(slug) : next.remove(slug);
              onChanged(next);
            },
            theme: theme,
            l10n: l10n,
          ),
      ],
    );
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

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.groupLabel,
    required this.tags,
    required this.selectedSlugs,
    required this.automaticSlugs,
    required this.onToggle,
    required this.theme,
    required this.l10n,
  });

  final CapabilityGroup group;
  final String groupLabel;
  final List<CapabilityTag> tags;
  final Set<String> selectedSlugs;
  final Set<String> automaticSlugs;
  final void Function(String slug, bool selected) onToggle;
  final ThemeData theme;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            groupLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final tag in tags)
              FilterChip(
                label: Text(tag.labelOf(l10n)),
                avatar: Icon(tag.icon, size: 18),
                showCheckmark: false,
                selected: selectedSlugs.contains(tag.slug),
                onSelected: (v) => onToggle(tag.slug, v),
                selectedColor: automaticSlugs.contains(tag.slug)
                    ? theme.colorScheme.secondaryContainer
                    : null,
                backgroundColor: automaticSlugs.contains(tag.slug)
                    ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.4)
                    : null,
              ),
          ],
        ),
      ],
    );
  }

}
