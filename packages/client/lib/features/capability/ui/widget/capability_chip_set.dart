import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// A grouped, selectable chip set for capability tags.
///
/// [selectedSlugs] is the current selection; [onChanged] fires on every toggle.
///
/// Groups are collapsible [ExpansionTile]s, folded by default unless the group
/// has a selected or pre-existing ([automaticSlugs]) tag. Collapsed headers show
/// small count badges for selections and pre-existing hints.
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.count,
    required this.preExisting,
  });

  final int count;
  final bool preExisting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = preExisting ? cs.secondaryContainer : cs.primaryContainer;
    final fg = preExisting ? cs.onSecondaryContainer : cs.onPrimaryContainer;
    final text = preExisting ? '★ $count' : '$count';
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
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
    final groupSlugs = tags.map((t) => t.slug).toSet();
    final selectedCount = selectedSlugs.intersection(groupSlugs).length;
    final autoCount = automaticSlugs.intersection(groupSlugs).length;
    final initiallyExpanded = selectedCount > 0 || autoCount > 0;

    return ExpansionTile(
      key: ValueKey<CapabilityGroup>(group),
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      initiallyExpanded: initiallyExpanded,
      title: Row(
        children: [
          Expanded(
            child: Text(
              groupLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (selectedCount > 0)
            _CountBadge(count: selectedCount, preExisting: false),
          if (autoCount > 0)
            _CountBadge(count: autoCount, preExisting: true),
        ],
      ),
      childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      children: [
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
                    ? theme.colorScheme.secondaryContainer
                        .withValues(alpha: 0.55)
                    : null,
                side: automaticSlugs.contains(tag.slug)
                    ? BorderSide(
                        color: theme.colorScheme.secondary
                            .withValues(alpha: 0.7),
                        width: 1.5,
                      )
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
