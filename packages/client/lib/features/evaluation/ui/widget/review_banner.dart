import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

/// Inline banner: draft phase (open beacon) or review window after closure.
class ReviewBanner extends StatelessWidget {
  const ReviewBanner({
    required this.onPrimary,
    required this.isDraftPhase,
    super.key,
  });

  final VoidCallback onPrimary;

  /// True while beacon is open (draft notes); false after closure (submit reviews).
  final bool isDraftPhase;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final title = isDraftPhase
        ? l10n.evaluationBannerTitleDraft
        : l10n.evaluationBannerTitle;
    final subtitle = isDraftPhase
        ? l10n.evaluationBannerSubtitleDraft
        : l10n.evaluationBannerSubtitle;
    final cta = isDraftPhase
        ? l10n.evaluationBannerDraftReview
        : l10n.evaluationBannerReview;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPrimary,
              child: Text(cta),
            ),
          ],
        ),
      ),
    );
  }
}
