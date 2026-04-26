import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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
    final tt = context.tt;
    final theme = Theme.of(context);

    final showSecond = usefulCount > 0 || needsCoordinationCount > 0;

    return TenturaTechCardStatic(
      showShadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.beaconOverviewActiveCommitments(activeCount),
            style: theme.textTheme.titleSmall!.copyWith(color: tt.text),
          ),
          if (showSecond) ...[
            const SizedBox(height: 6),
            _SummarySubline(
              l10n: l10n,
              usefulCount: usefulCount,
              needsCoordinationCount: needsCoordinationCount,
              good: tt.good,
              warning: tt.warn,
              neutral: tt.textMuted,
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
    final base = TenturaText.bodySmall(neutral);

    if (usefulCount > 0 && needsCoordinationCount > 0) {
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(
              text: l10n.commitmentsTabSummaryUseful(usefulCount),
              style: base.copyWith(color: good),
            ),
            TextSpan(
              text: ' · ',
              style: base,
            ),
            TextSpan(
              text: l10n.commitmentsTabSummaryNeedCoordination(
                needsCoordinationCount,
              ),
              style: base.copyWith(
                color: warning,
              ),
            ),
          ],
        ),
      );
    }
    if (usefulCount > 0) {
      return Text(
        l10n.commitmentsTabSummaryUseful(usefulCount),
        style: base.copyWith(color: good),
      );
    }
    return Text(
      l10n.commitmentsTabSummaryNeedCoordination(needsCoordinationCount),
      style: base.copyWith(color: warning),
    );
  }
}
