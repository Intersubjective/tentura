import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

class BeaconForwardHeader extends StatelessWidget {
  const BeaconForwardHeader({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  String _lifecycleLabel(L10n l10n) => switch (beacon.lifecycle) {
        BeaconLifecycle.open => l10n.beaconLifecycleOpen,
        BeaconLifecycle.closed => l10n.beaconLifecycleClosed,
        BeaconLifecycle.deleted => l10n.beaconLifecycleDeleted,
        BeaconLifecycle.draft => l10n.beaconLifecycleDraft,
        BeaconLifecycle.pendingReview => l10n.beaconLifecyclePendingReview,
        BeaconLifecycle.closedReviewOpen =>
          l10n.beaconLifecycleClosedReviewOpen,
        BeaconLifecycle.closedReviewComplete =>
          l10n.beaconLifecycleClosedReviewComplete,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    if (beacon.id.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: kPaddingH,
      child: Padding(
        padding: kPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              beacon.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: kSpacingSmall),
            Row(
              children: [
                AvatarRated(
                  profile: beacon.author,
                  size: 24,
                ),
                const SizedBox(width: kSpacingSmall),
                Expanded(
                  child: Text(
                    beacon.author.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    _lifecycleLabel(l10n),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  side: BorderSide.none,
                ),
              ],
            ),
            if (beacon.startAt != null || beacon.endAt != null) ...[
              const SizedBox(height: kSpacingSmall),
              Row(
                children: [
                  Icon(
                    TenturaIcons.calendar,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: kSpacingSmall),
                  Expanded(
                    child: Text(
                      '${dateFormatYMD(beacon.startAt)}'
                      ' – ${dateFormatYMD(beacon.endAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (beacon.context.isNotEmpty) ...[
              const SizedBox(height: kSpacingSmall),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text(beacon.context),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
