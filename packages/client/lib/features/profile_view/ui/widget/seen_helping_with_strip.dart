import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Compact single-line strip showing "Seen helping with: Transport · Pets · …".
class SeenHelpingWithStrip extends StatelessWidget {
  const SeenHelpingWithStrip({
    required this.projections,
    super.key,
  });

  final List<TagProjection> projections;

  @override
  Widget build(BuildContext context) {
    if (projections.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final labels = projections
        .take(3)
        .map((projection) => _displayLabel(l10n, projection.tagSlug))
        .toList();
    final theme = Theme.of(context);
    return Text(
      l10n.capabilityCueSeenHelpingWith(labels.join(' · ')),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  static String _displayLabel(L10n l10n, String slug) =>
      CapabilityTag.fromSlug(slug.trim())?.labelOf(l10n) ?? slug.trim();
}
