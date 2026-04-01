import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

/// Inline banner after closure when review is open for this user.
class ReviewBanner extends StatelessWidget {
  const ReviewBanner({
    required this.onReview,
    required this.onLater,
    super.key,
  });

  final VoidCallback onReview;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
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
            Row(
              children: [
                FilledButton(
                  onPressed: onReview,
                  child: Text(l10n.evaluationBannerReview),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onLater,
                  child: Text(l10n.evaluationBannerLater),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
