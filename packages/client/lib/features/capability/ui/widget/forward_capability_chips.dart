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
            return RawChip(
              label: Text(
                tag?.labelOf(l10n) ?? slug,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              avatar: tag != null
                  ? Icon(
                      tag.icon,
                      size: 14,
                      color: theme.colorScheme.onSecondaryContainer,
                    )
                  : null,
              backgroundColor: theme.colorScheme.secondaryContainer,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }(),
      ],
    );
  }
}
