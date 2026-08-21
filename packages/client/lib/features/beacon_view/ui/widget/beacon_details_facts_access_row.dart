import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Shared HUD access row for Details and Pinned facts sheets.
class BeaconDetailsFactsAccessRow extends StatelessWidget {
  const BeaconDetailsFactsAccessRow({
    required this.showDetails,
    required this.factsCount,
    required this.factsNewCount,
    required this.onOpenDetails,
    required this.onOpenFacts,
    this.canAddFacts = false,
    super.key,
  });

  final bool showDetails;
  final int factsCount;
  final int factsNewCount;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onOpenFacts;
  final bool canAddFacts;

  @override
  Widget build(BuildContext context) {
    final showFacts =
        (factsCount > 0 || canAddFacts) && onOpenFacts != null;
    if (!showDetails && !showFacts) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final both = showDetails && showFacts;
        final compact = constraints.maxWidth < 600;
        final showIcons = !both || !compact;

        Widget cell({
          required String testId,
          required String label,
          required IconData icon,
          required VoidCallback? onTap,
          int? count,
          int newCount = 0,
        }) {
          return Semantics(
            button: true,
            label: label,
            child: InkWell(
              key: ValueKey(testId),
              onTap: onTap,
              borderRadius: BorderRadius.circular(tt.cardRadius),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: tt.borderSubtle),
                  borderRadius: BorderRadius.circular(tt.cardRadius),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: tt.buttonHeight),
                  child: Row(
                    children: [
                      if (showIcons) ...[
                        Icon(
                          icon,
                          size: tt.iconSize,
                          color: scheme.onSurfaceVariant,
                        ),
                        SizedBox(width: tt.iconTextGap),
                      ],
                      Expanded(
                        child: Text(
                          label,
                          style: TenturaText.bodySmall(
                            scheme.onSurface,
                          ).copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (count != null) ...[
                        SizedBox(width: tt.tightGap),
                        Text(
                          '$count',
                          style: TenturaText.bodySmall(
                            scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (newCount > 0) ...[
                        SizedBox(width: tt.tightGap),
                        Text(
                          l10n.beaconYouNewCount(newCount),
                          style: TenturaText.bodySmall(tt.info).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      Icon(
                        Icons.chevron_right,
                        size: tt.iconSize,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final details = cell(
          testId: TestIds.beaconDetailsOpen,
          label: l10n.beaconDetailsSection,
          icon: Icons.info_outline,
          onTap: onOpenDetails,
        );
        final facts = cell(
          testId: TestIds.beaconFactsOpen,
          label: l10n.beaconFactsRowLabel,
          icon: Icons.article_outlined,
          onTap: onOpenFacts,
          count: factsCount > 0 ? factsCount : null,
          newCount: factsNewCount,
        );

        if (!both) {
          return showDetails ? details : facts;
        }

        return Row(
          children: [
            Expanded(child: details),
            SizedBox(width: tt.rowGap),
            Expanded(child: facts),
          ],
        );
      },
    );
  }
}
