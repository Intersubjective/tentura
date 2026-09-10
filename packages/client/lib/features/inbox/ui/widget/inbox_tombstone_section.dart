import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/inbox_item.dart';
import 'inbox_tombstone_card.dart';

/// Resolved / tombstone rows from the last 24h (Needs-me tab body extraction).
///
/// UNIT 16 relocates this into the Activity feed scroll; UNIT 14's triage route
/// does not mount it.
class InboxTombstoneSection extends StatelessWidget {
  const InboxTombstoneSection({
    required this.tombstones,
    required this.onDismiss,
    super.key,
  });

  final List<InboxItem> tombstones;
  final void Function(String beaconId) onDismiss;

  @override
  Widget build(BuildContext context) {
    if (tombstones.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: tt.tightGap * 2,
            bottom: tt.rowGap,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.inboxTombstoneSectionTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: tt.rowGap),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(TenturaRadii.avatar),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tt.rowGap,
                    vertical: tt.tightGap * 2,
                  ),
                  child: Text(
                    l10n.inboxTombstoneLast24h,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < tombstones.length; i++) ...[
          if (i > 0) SizedBox(height: tt.rowGap),
          InboxTombstoneCard(
            key: ValueKey('tombstone-${tombstones[i].beaconId}'),
            item: tombstones[i],
            onOpen: () => context.router.push(
              BeaconViewRoute(
                id: tombstones[i].beaconId,
                entry: kBeaconEntryInbox,
              ),
            ),
            onDismiss: () => onDismiss(tombstones[i].beaconId),
          ),
        ],
        SizedBox(height: tt.sectionGap),
      ],
    );
  }
}

/// Sliver variant of [InboxTombstoneSection] for scroll views that interleave
/// tombstones with triage rows (pre–UNIT 16 layout).
List<Widget> buildInboxTombstoneSlivers({
  required BuildContext context,
  required List<InboxItem> tombstones,
  required void Function(String beaconId) onDismiss,
}) {
  if (tombstones.isEmpty) {
    return const [];
  }

  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final l10n = L10n.of(context)!;
  final tt = context.tt;

  return [
    SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(
          top: tt.tightGap * 2,
          bottom: tt.rowGap,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.inboxTombstoneSectionTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: tt.rowGap),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(TenturaRadii.avatar),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tt.rowGap,
                  vertical: tt.tightGap * 2,
                ),
                child: Text(
                  l10n.inboxTombstoneLast24h,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    SliverList.separated(
      itemCount: tombstones.length,
      separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
      itemBuilder: (_, i) {
        final item = tombstones[i];
        return InboxTombstoneCard(
          key: ValueKey('tombstone-${item.beaconId}'),
          item: item,
          onOpen: () => context.router.push(
            BeaconViewRoute(
              id: item.beaconId,
              entry: kBeaconEntryInbox,
            ),
          ),
          onDismiss: () => onDismiss(item.beaconId),
        );
      },
    ),
    SliverToBoxAdapter(child: SizedBox(height: tt.sectionGap)),
  ];
}
