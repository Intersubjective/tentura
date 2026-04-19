import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_author_subline.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_dot.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_reason_l10n.dart'
    show l10nInboxNewStuffReasons;
import 'package:tentura/ui/bloc/screen_cubit.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import 'inbox_card_action_row.dart';
import 'inbox_card_deadline_pill.dart';
import 'inbox_card_forwards_fold.dart';

class InboxItemTile extends StatelessWidget {
  const InboxItemTile({
    required this.item,
    required this.onOpenBeacon,
    required this.onTap,
    this.onWatch,
    this.onStopWatching,
    this.onCantHelp,
    this.onMoveToInbox,
    this.onCommit,
    this.showCtaRow = true,
    this.showProvenance = true,
    this.inboxHighlight = InboxRowHighlightKind.none,
    super.key,
  });

  final InboxItem item;
  final VoidCallback onOpenBeacon;
  final VoidCallback onTap;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;
  final Future<void> Function()? onCantHelp;
  final VoidCallback? onMoveToInbox;

  /// Commit to this beacon (same flow as beacon view); null hides the menu item.
  final Future<void> Function()? onCommit;

  /// When false (Watching / Rejected tabs), hide the bottom Forward / secondary
  /// button row; actions remain in the overflow menu.
  final bool showCtaRow;

  /// When false (Watching / Rejected tabs), hide the whole forwarder block
  /// (avatars, expand, quotes).
  final bool showProvenance;

  /// New vs updated since last Inbox visit (see [NewStuffCubit.inboxRowHighlight]).
  final InboxRowHighlightKind inboxHighlight;

  String? _secondaryLabel(L10n l10n) {
    if (onCantHelp != null) return l10n.inboxActionNotForMe;
    if (onStopWatching != null) return l10n.actionStopWatching;
    if (onMoveToInbox != null) return l10n.actionMoveToInbox;
    return null;
  }

  IconData? _secondaryIcon() {
    if (onCantHelp != null) return Icons.close;
    if (onStopWatching != null) return Icons.visibility_off_outlined;
    if (onMoveToInbox != null) return Icons.inbox_outlined;
    return null;
  }

  Future<void> _onSecondaryPressed() async {
    if (onCantHelp != null) {
      await onCantHelp?.call();
      return;
    }
    if (onStopWatching != null) {
      onStopWatching?.call();
      return;
    }
    onMoveToInbox?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final beacon = item.beacon;
    if (beacon == null) return const SizedBox.shrink();

    final secondaryLabel = _secondaryLabel(l10n);
    final secondaryIcon = _secondaryIcon();

    final showNewStuffDot = inboxHighlight != InboxRowHighlightKind.none;
    final hasProvenance = showProvenance && item.provenance.senders.isNotEmpty;

    const cardPadding = EdgeInsets.fromLTRB(12, 10, 12, 10);

    final category = beacon.context.trim().isEmpty
        ? l10n.inboxCategoryGeneral
        : beacon.context.trim();

    return BeaconCardShell(
      padding: cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  BeaconIdentityTile(beacon: beacon, size: 40),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 40,
                    child: Text(
                      category,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: GestureDetector(
                  onTap: onOpenBeacon,
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        beacon.title.isEmpty ? '—' : beacon.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: BeaconCardAuthorSubline(
                              author: beacon.author,
                              avatarSize: 20,
                            ),
                          ),
                          if (beacon.endAt != null) ...[
                            const SizedBox(width: 6),
                            InboxCardDeadlinePill(endAt: beacon.endAt),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              BeaconOverflowMenu(
                beacon: beacon,
                onOpenBeacon: onOpenBeacon,
                onCommit: onCommit != null
                    ? () async {
                        await onCommit?.call();
                      }
                    : null,
                onForward: onTap,
                onViewForwards: () => unawaited(
                  context.router.pushPath(
                    '$kPathBeaconForwards/${beacon.id}',
                  ),
                ),
                onWatch: onWatch,
                onStopWatching: onStopWatching,
                onCantHelp: onCantHelp,
                onMoveToInbox: onMoveToInbox,
                onComplaint: () =>
                    context.read<ScreenCubit>().showComplaint(beacon.id),
              ),
            ],
          ),
          if (hasProvenance) ...[
            const SizedBox(height: 6),
            InboxCardForwardsFold(provenance: item.provenance),
          ],
          const SizedBox(height: 8),
          if (item.status == InboxItemStatus.rejected &&
              item.rejectionMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.rejectionMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (showNewStuffDot)
            BlocBuilder<NewStuffCubit, NewStuffState>(
              buildWhen: (p, c) => p.inboxLastSeenMs != c.inboxLastSeenMs,
              builder: (context, _) {
                final seen = context
                    .read<NewStuffCubit>()
                    .state
                    .inboxLastSeenMs;
                final labels = l10nInboxNewStuffReasons(
                  L10n.of(context)!,
                  item.newStuffReasons(seen),
                );
                final at = DateTime.fromMillisecondsSinceEpoch(
                  item.newStuffActivityEpochMs,
                );
                final whenLine = l10n.myWorkUpdatedLine(
                  '${dateFormatYMD(at)} ${timeFormatHm(at)}',
                );
                final summary = labels.isEmpty
                    ? whenLine
                    : '$whenLine · ${labels.join(' · ')}';
                final style = theme.textTheme.labelSmall?.copyWith(
                  color: scheme.outline,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const NewStuffDot(
                        padding: EdgeInsets.only(right: 6, top: 2),
                      ),
                      Expanded(
                        child: Text(
                          summary,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (showCtaRow) ...[
            const SizedBox(height: 8),
            InboxCardActionRow(
              onCommit: onCommit,
              onForward: onTap,
              secondaryLabel: secondaryLabel,
              secondaryIcon: secondaryIcon,
              onSecondary: secondaryLabel != null ? _onSecondaryPressed : null,
            ),
          ],
        ],
      ),
    );
  }
}
