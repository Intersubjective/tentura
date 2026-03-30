import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/forward_state.dart';

class ForwardFilterBar extends StatelessWidget {
  const ForwardFilterBar({
    required this.activeFilter,
    required this.onFilterSelected,
    super.key,
  });

  final ForwardFilter activeFilter;
  final ValueChanged<ForwardFilter> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: kPaddingH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text(l10n.forwardFilterAll),
                  selected: activeFilter == ForwardFilter.all,
                  onSelected: (_) => onFilterSelected(ForwardFilter.all),
                ),
                const SizedBox(width: kSpacingSmall),
                FilterChip(
                  label: Text(l10n.forwardFilterBestNext),
                  selected: activeFilter == ForwardFilter.bestNext,
                  onSelected: (_) => onFilterSelected(ForwardFilter.bestNext),
                ),
                const SizedBox(width: kSpacingSmall),
                FilterChip(
                  label: Text(l10n.forwardFilterUnseen),
                  selected: activeFilter == ForwardFilter.unseen,
                  onSelected: (_) => onFilterSelected(ForwardFilter.unseen),
                ),
                const SizedBox(width: kSpacingSmall),
                FilterChip(
                  label: Text(l10n.forwardFilterInvolved),
                  selected: activeFilter == ForwardFilter.alreadyInvolved,
                  onSelected: (_) =>
                      onFilterSelected(ForwardFilter.alreadyInvolved),
                ),
              ],
            ),
          ),
          const SizedBox(height: kSpacingSmall),
          Text(
            l10n.forwardSortedByMr,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
