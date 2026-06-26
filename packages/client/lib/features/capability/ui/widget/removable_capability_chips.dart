import 'package:flutter/material.dart';

import 'package:tentura/features/capability/ui/widget/capability_requirement_tags.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Removable capability chips for editable requirement selections.
///
/// Renders nothing when [slugs] is empty or contains no known tags.
class RemovableCapabilityChips extends StatelessWidget {
  const RemovableCapabilityChips({
    required this.slugs,
    required this.onRemove,
    super.key,
  });

  final Set<String> slugs;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final tags = resolveCapabilityRequirementTags(slugs);
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSecondaryContainer;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: fg);

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final tag in tags)
          InputChip(
            label: Text(tag.labelOf(l10n), style: labelStyle),
            avatar: Icon(tag.icon, size: 18, color: fg),
            onDeleted: () => onRemove(tag.slug),
            backgroundColor: theme.colorScheme.secondaryContainer,
            deleteIconColor: fg,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
