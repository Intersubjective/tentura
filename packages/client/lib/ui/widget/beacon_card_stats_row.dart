import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

String _beaconCategoryLabel(Beacon beacon, L10n l10n) {
  final c = beacon.context.trim();
  return c.isEmpty ? l10n.inboxCategoryGeneral : c;
}

/// Divider + metadata strip (topic, commitments, time remaining).
class BeaconCardStatsRow extends StatelessWidget {
  const BeaconCardStatsRow({
    required this.beacon,
    this.showDivider = true,
    super.key,
  });

  final Beacon beacon;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categoryLabel = _beaconCategoryLabel(beacon, l10n);
    final hoursRemaining = beaconCardDeadlineRemainingMeta(l10n, beacon.endAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: kSpacingSmall),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        if (showDivider) const SizedBox(height: kSpacingSmall),
        Wrap(
          spacing: kSpacingMedium,
          runSpacing: kSpacingSmall,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BeaconCardMetaItem(
              icon: Icons.topic_outlined,
              child: Text(
                categoryLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            BeaconCardMetaItem(
              icon: Icons.groups_outlined,
              child: Text(
                l10n.beaconCardCommitmentCount(beacon.commitmentCount),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hoursRemaining != null)
              BeaconCardMetaItem(
                icon: Icons.timer_outlined,
                child: Text(
                  hoursRemaining.text,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hoursRemaining.urgent
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontWeight:
                        hoursRemaining.urgent ? FontWeight.w600 : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
