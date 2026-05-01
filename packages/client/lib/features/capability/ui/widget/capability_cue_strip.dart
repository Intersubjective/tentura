import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

/// Compact single-line strip showing "My labels: transport · pets · ...".
class CapabilityCueStrip extends StatelessWidget {
  const CapabilityCueStrip({
    required this.slugs,
    super.key,
  });

  final List<String> slugs;

  @override
  Widget build(BuildContext context) {
    if (slugs.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Text(
      l10n.capabilityCueMyLabels(slugs.join(' · ')),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
