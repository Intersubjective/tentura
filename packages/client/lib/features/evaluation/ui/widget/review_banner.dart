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

  /// True while beacon is open (draft review CTA only); false after closure (banner + submit).
  final bool isDraftPhase;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    if (isDraftPhase) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(l10n.evaluationBannerDraftReview),
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.evaluationBannerTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.evaluationBannerSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPrimary,
              child: Text(l10n.evaluationBannerReview),
            ),
          ],
        ),
      ),
    );
  }
}
