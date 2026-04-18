import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_author_subline.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_card_stats_row.dart';
import 'package:tentura/ui/widget/side_outline_cta_button.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_dot.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_reason_l10n.dart'
    show l10nInboxNewStuffReasons;
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import 'inbox_forward_provenance_panel.dart';

String _lifecycleLabel(L10n l10n, BeaconLifecycle lc) => switch (lc) {
  BeaconLifecycle.open => l10n.beaconLifecycleOpen,
  BeaconLifecycle.closed => l10n.beaconLifecycleClosed,
  BeaconLifecycle.deleted => l10n.beaconLifecycleDeleted,
  BeaconLifecycle.draft => l10n.beaconLifecycleDraft,
  BeaconLifecycle.pendingReview => l10n.beaconLifecyclePendingReview,
  BeaconLifecycle.closedReviewOpen => l10n.beaconLifecycleClosedReviewOpen,
  BeaconLifecycle.closedReviewComplete =>
    l10n.beaconLifecycleClosedReviewComplete,
};

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

    final hasProvenanceBody = item.provenance.senders.isNotEmpty;

    final beaconStatePills = <Widget>[
      if (beacon.lifecycle != BeaconLifecycle.open)
        BeaconCardPill(label: _lifecycleLabel(l10n, beacon.lifecycle)),
      if (beacon.coordinationStatus !=
              BeaconCoordinationStatus.noCommitmentsYet &&
          beacon.coordinationStatus !=
              BeaconCoordinationStatus.commitmentsWaitingForReview)
        BeaconCardPill(
          label: coordinationStatusLabel(l10n, beacon.coordinationStatus),
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundColor: scheme.onSurfaceVariant,
        ),
    ];

    final inboxRolePills = <Widget>[
      if (item.isForwardedByMe)
        BeaconCardPill(label: l10n.inboxForwardedByMe),
    ];

    final allPills = <Widget>[
      ...beaconStatePills,
      ...inboxRolePills,
    ];

    final showNewStuffDot = inboxHighlight != InboxRowHighlightKind.none;

    return BeaconCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onOpenBeacon,
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BeaconCardHeaderRow(
                        beacon: beacon,
                        titleMaxLines: 2,
                        subline: BeaconCardAuthorSubline(author: beacon.author),
                        menu: const SizedBox.shrink(),
                      ),
                      if (beacon.description.isNotEmpty) ...[
                        const SizedBox(height: kSpacingSmall),
                        Text(
                          beacon.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (allPills.isNotEmpty) ...[
                        const SizedBox(height: kSpacingSmall),
                        Wrap(
                          spacing: kSpacingSmall,
                          runSpacing: kSpacingSmall,
                          children: allPills,
                        ),
                      ],
                      BeaconCardStatsRow(beacon: beacon),
                      if (item.status == InboxItemStatus.rejected &&
                          item.rejectionMessage.isNotEmpty) ...[
                        const SizedBox(height: kSpacingSmall),
                        Text(
                          item.rejectionMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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
          if (showNewStuffDot)
            BlocBuilder<NewStuffCubit, NewStuffState>(
              buildWhen: (p, c) => p.inboxLastSeenMs != c.inboxLastSeenMs,
              builder: (context, _) {
                final seen = context.read<NewStuffCubit>().state.inboxLastSeenMs;
                final labels =
                    l10nInboxNewStuffReasons(L10n.of(context)!, item.newStuffReasons(seen));
                final at = DateTime.fromMillisecondsSinceEpoch(
                  item.newStuffActivityEpochMs,
                );
                final whenLine = l10n.myWorkUpdatedLine(
                  '${dateFormatYMD(at)} ${timeFormatHm(at)}',
                );
                final style = theme.textTheme.labelSmall?.copyWith(
                  color: scheme.outline,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: kSpacingSmall),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const NewStuffDot(
                            padding: EdgeInsets.only(right: 8, top: 2),
                          ),
                          Expanded(
                            child: Text(
                              whenLine,
                              style: style,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (labels.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 22, top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in labels)
                                Text(line, style: style),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          if (hasProvenanceBody && showProvenance) ...[
            const SizedBox(height: kSpacingSmall),
            InboxForwardProvenancePanel(
              provenance: item.provenance,
              latestNotePreview: item.latestNotePreview,
              recipient: GetIt.I<ProfileCubit>().state.profile,
            ),
          ],
          if (showCtaRow) ...[
            const SizedBox(height: kSpacingSmall),
            Row(
              children: [
                if (secondaryLabel != null) ...[
                  SideOutlineCtaButton(
                    label: secondaryLabel,
                    icon: onCantHelp != null
                        ? Icons.close
                        : onStopWatching != null
                            ? Icons.visibility_off_outlined
                            : Icons.inbox_outlined,
                    onPressed: _onSecondaryPressed,
                  ),
                  const SizedBox(width: kSpacingSmall),
                ],
                if (onCommit != null) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await onCommit?.call();
                      },
                      icon: const Icon(Icons.handshake),
                      label: Text(l10n.labelCommit),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: kSpacingSmall),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.send),
                    label: Text(l10n.labelForward),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
