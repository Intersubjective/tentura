import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Compact single-line strip showing "Seen helping with: transport · pets · …".
class SeenHelpingWithStrip extends StatelessWidget {
  const SeenHelpingWithStrip({
    required this.projections,
    super.key,
  });

  final List<TagProjection> projections;

  @override
  Widget build(BuildContext context) {
    if (projections.isEmpty) return const SizedBox.shrink();
    final slugs = projections
        .take(3)
        .map((projection) => projection.tagSlug)
        .toList();
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Text(
      l10n.capabilityCueSeenHelpingWith(slugs.join(' · ')),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
