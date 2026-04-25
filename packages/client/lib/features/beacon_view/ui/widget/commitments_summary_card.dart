import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import 'commitment_tokens.dart';

/// Compact summary above the commitment list (no pills, no metric grid).
class CommitmentsSummaryCard extends StatelessWidget {
  const CommitmentsSummaryCard({
    required this.activeCount,
    required this.usefulCount,
    required this.needsCoordinationCount,
    super.key,
  });

  final int activeCount;
  final int usefulCount;
  final int needsCoordinationCount;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tones = CommitmentToneColors.of(context);

    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    final showSecond = usefulCount > 0 || needsCoordinationCount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tones.cardBorder),
        boxShadow: kCommitmentCardShadows(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.beaconOverviewActiveCommitments(activeCount),
            style: titleStyle,
          ),
          if (showSecond) ...[
            const SizedBox(height: 6),
            _SummarySubline(
              l10n: l10n,
              usefulCount: usefulCount,
              needsCoordinationCount: needsCoordinationCount,
              good: tones.good,
              warning: tones.warning,
              neutral: tones.neutral,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummarySubline extends StatelessWidget {
  const _SummarySubline({
    required this.l10n,
    required this.usefulCount,
    required this.needsCoordinationCount,
    required this.good,
    required this.warning,
    required this.neutral,
  });

  final L10n l10n;
  final int usefulCount;
  final int needsCoordinationCount;
  final Color good;
  final Color warning;
  final Color neutral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      height: 1.35,
    );

    if (usefulCount > 0 && needsCoordinationCount > 0) {
      return Text.rich(
        TextSpan(
          style: base?.copyWith(color: neutral),
          children: [
            TextSpan(
              text: l10n.commitmentsTabSummaryUseful(usefulCount),
              style: base?.copyWith(color: good, fontWeight: FontWeight.w500),
            ),
            TextSpan(
              text: ' · ',
              style: base?.copyWith(color: neutral),
            ),
            TextSpan(
              text: l10n.commitmentsTabSummaryNeedCoordination(
                needsCoordinationCount,
              ),
              style: base?.copyWith(color: warning, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    if (usefulCount > 0) {
      return Text(
        l10n.commitmentsTabSummaryUseful(usefulCount),
        style: base?.copyWith(color: good, fontWeight: FontWeight.w500),
      );
    }
    return Text(
      l10n.commitmentsTabSummaryNeedCoordination(needsCoordinationCount),
      style: base?.copyWith(color: warning, fontWeight: FontWeight.w500),
    );
  }
}
