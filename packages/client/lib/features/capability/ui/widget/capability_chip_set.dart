import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_selection_count_badge.dart';
import 'package:tentura/features/capability/ui/widget/capability_tag_chip.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
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
    this.availableSlugs,
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

  /// When supplied, only these server-authorized slugs are shown. A null
  /// value keeps the complete catalog for existing callers.
  final Set<String>? availableSlugs;

  final void Function(Set<String> slugs) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final searching = query.trim().isNotEmpty;

    final sections = <Widget>[];
    for (final group in CapabilityGroup.values) {
      final tags = _matchingTags(group, l10n);
      if (tags.isEmpty) continue;
      sections.add(
        _GroupSection(
          group: group,
          groupLabel: group.labelOf(l10n),
          groupDescription: group.descriptionOf(l10n),
          tags: tags,
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
      );
    }

    return AccordionExpansionGroup(
      accordionMode: !searching,
      child: Theme(
        // One interaction theme for the whole set — avoids ThemeData.copyWith
        // per group on every rebuild (was amplifying browse-open jank).
        data: theme.copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          splashColor: Colors.transparent,
          colorScheme: theme.colorScheme.copyWith(
            surfaceTint: Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: sections,
        ),
      ),
    );
  }

  List<CapabilityTag> _matchingTags(CapabilityGroup group, L10n l10n) {
    final normalized = query.trim().toLowerCase();
    final groupMatches =
        normalized.isEmpty ||
        group.labelOf(l10n).toLowerCase().contains(normalized) ||
        group.descriptionOf(l10n).toLowerCase().contains(normalized);
    return CapabilityTag.values.where((tag) {
      if (tag.group != group) return false;
      if (availableSlugs != null && !availableSlugs!.contains(tag.slug)) {
        return false;
      }
      return groupMatches ||
          tag.labelOf(l10n).toLowerCase().contains(normalized);
    }).toList();
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

    return AccordionExpansionTile(
      id: group.name,
      initiallyExpanded: initiallyExpanded,
      // Collapsed groups must not keep chip Wrap in the tree — with the
      // default maintainState:true, opening browse built all FilterChips
      // at once and froze the UI for a noticeable beat (no network involved).
      maintainState: false,
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
          // Widest plausible badges (`★ 9`) reserve space so selection
          // counters never shift the title or chip wrap below.
          CapabilityReservedCountSlot(
            visible: selectedCount > 0,
            count: selectedCount,
          ),
          CapabilityReservedCountSlot(
            visible: autoCount > 0,
            count: autoCount,
            preExisting: true,
          ),
        ],
      ),
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: context.tt.tightGap,
            right: context.tt.tightGap,
            bottom: context.tt.rowGap,
          ),
          // Full width: ExpansionTile centres its children column, which
          // would centre a shrink-wrapped Wrap and float short rows (#436).
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: context.tt.tightGap,
              runSpacing: context.tt.tightGap,
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
        ),
      ],
    );
  }
}
