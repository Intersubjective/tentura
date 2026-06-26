import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_tag_chip.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';

/// A grouped, selectable chip set for capability tags.
///
/// [selectedSlugs] is the current selection; [onChanged] fires on every toggle.
///
/// Groups are collapsible accordion sections, folded by default unless the group
/// has a selected or pre-existing ([automaticSlugs]) tag. Collapsed headers show
/// small count badges for selections and pre-existing hints.
class CapabilityChipSet extends StatelessWidget {
  const CapabilityChipSet({
    required this.selectedSlugs,
    required this.onChanged,
    this.automaticSlugs = const {},
    this.maxSelection,
    this.query = '',
    super.key,
  });

  final Set<String> selectedSlugs;

  /// When non-null, unselected tags cannot be toggled on once selection length reaches this.
  final int? maxSelection;
  final String query;

  /// Slugs that were added automatically (via forward/offer-help/close-ack).
  /// These chips are shown in a secondary color to distinguish them from
  /// manually-added ones.
  final Set<String> automaticSlugs;

  final void Function(Set<String> slugs) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final searching = query.trim().isNotEmpty;

    return AccordionExpansionGroup(
      accordionMode: !searching,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final group in CapabilityGroup.values)
            if (_matchingTags(group, l10n).isNotEmpty)
              _GroupSection(
                group: group,
                groupLabel: _groupLabel(l10n, group),
                groupDescription: _groupDescription(l10n, group),
                tags: _matchingTags(group, l10n),
                forceExpanded: searching,
                selectedSlugs: selectedSlugs,
                automaticSlugs: automaticSlugs,
                maxSelection: maxSelection,
                onToggle: (slug, selected) {
                  final next = Set<String>.from(selectedSlugs);
                  selected ? next.add(slug) : next.remove(slug);
                  onChanged(next);
                },
                theme: theme,
                l10n: l10n,
              ),
        ],
      ),
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

  List<CapabilityTag> _matchingTags(CapabilityGroup group, L10n l10n) {
    final normalized = query.trim().toLowerCase();
    final groupMatches =
        normalized.isEmpty ||
        _groupLabel(l10n, group).toLowerCase().contains(normalized) ||
        _groupDescription(l10n, group).toLowerCase().contains(normalized);
    return CapabilityTag.values.where((tag) {
      if (tag.group != group) return false;
      return groupMatches ||
          tag.labelOf(l10n).toLowerCase().contains(normalized);
    }).toList();
  }

  static String _groupDescription(L10n l10n, CapabilityGroup group) =>
      switch (group) {
        CapabilityGroup.logistics => l10n.capabilityGroupLogisticsDescription,
        CapabilityGroup.communication =>
          l10n.capabilityGroupCommunicationDescription,
        CapabilityGroup.knowledge => l10n.capabilityGroupKnowledgeDescription,
        CapabilityGroup.care => l10n.capabilityGroupCareDescription,
        CapabilityGroup.resources => l10n.capabilityGroupResourcesDescription,
        CapabilityGroup.technical => l10n.capabilityGroupTechnicalDescription,
        CapabilityGroup.special => l10n.capabilityGroupSpecialDescription,
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
    required this.groupDescription,
    required this.tags,
    required this.forceExpanded,
    required this.selectedSlugs,
    required this.automaticSlugs,
    required this.onToggle,
    required this.theme,
    required this.l10n,
    this.maxSelection,
  });

  final CapabilityGroup group;
  final String groupLabel;
  final String groupDescription;
  final List<CapabilityTag> tags;
  final bool forceExpanded;
  final Set<String> selectedSlugs;
  final Set<String> automaticSlugs;
  final int? maxSelection;
  final void Function(String slug, bool selected) onToggle;
  final ThemeData theme;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final groupSlugs = tags.map((t) => t.slug).toSet();
    final selectedCount = selectedSlugs.intersection(groupSlugs).length;
    final autoCount = automaticSlugs.intersection(groupSlugs).length;
    final initiallyExpanded =
        forceExpanded || selectedCount > 0 || autoCount > 0;
    final selectionLimit = maxSelection;
    final atSelectionLimit =
        selectionLimit != null && selectedSlugs.length >= selectionLimit;

    final cs = theme.colorScheme;
    final categoryInteractionTheme = theme.copyWith(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      splashColor: Colors.transparent,
      colorScheme: cs.copyWith(surfaceTint: Colors.transparent),
    );

    return Theme(
      data: categoryInteractionTheme,
      child: AccordionExpansionTile(
        id: group.name,
        initiallyExpanded: initiallyExpanded,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    groupDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedCount > 0)
              _CountBadge(count: selectedCount, preExisting: false),
            if (autoCount > 0) _CountBadge(count: autoCount, preExisting: true),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in tags)
                  CapabilityTagFilterChip(
                    tag: tag,
                    l10n: l10n,
                    theme: theme,
                    selected: selectedSlugs.contains(tag.slug),
                    isAutomatic: automaticSlugs.contains(tag.slug),
                    onSelected:
                        atSelectionLimit && !selectedSlugs.contains(tag.slug)
                        ? null
                        : (v) => onToggle(tag.slug, v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
