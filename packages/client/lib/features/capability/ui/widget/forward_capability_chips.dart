import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Read-only compact chips for capability tags assigned by a forwarder.
/// Renders nothing when [slugs] is empty.
class ForwardCapabilityChips extends StatelessWidget {
  const ForwardCapabilityChips({required this.slugs, super.key});

  final List<String> slugs;

  @override
  Widget build(BuildContext context) {
    if (slugs.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final slug in slugs)
          () {
            final tag = CapabilityTag.fromSlug(slug);
            final fg = theme.colorScheme.onSecondaryContainer;
            final label = tag?.labelOf(l10n) ?? slug;
            final labelStyle = theme.textTheme.labelSmall?.copyWith(color: fg);
            return RawChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tag != null) ...[
                    Icon(tag.icon, size: 14, color: fg),
                    const SizedBox(width: 4),
                  ],
                  Text(label, style: labelStyle),
                ],
              ),
              backgroundColor: theme.colorScheme.secondaryContainer,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }(),
      ],
    );
  }
}
