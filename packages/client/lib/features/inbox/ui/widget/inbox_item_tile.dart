import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/side_outline_cta_button.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_dot.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_reason_l10n.dart'
    show l10nInboxNewStuffReasons;
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import 'inbox_forward_provenance_panel.dart';

Widget _inboxOverflowMenuRow(IconData icon, String label) {
  return Row(
    children: [
      Icon(icon, size: 22),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

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

/// Beacon **context** for inbox metadata (first column); not tags.
String _beaconContextCategoryLabel(InboxItem item, L10n l10n) {
  final beacon = item.beacon;
  if (beacon == null) return l10n.inboxCategoryGeneral;
  final c = beacon.context.trim();
  return c.isEmpty ? l10n.inboxCategoryGeneral : c;
}

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

    final contextCategoryLabel = _beaconContextCategoryLabel(item, l10n);
    final hoursRemaining = beaconCardDeadlineRemainingMeta(l10n, beacon.endAt);
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
                        subline: Row(
                          children: [
                            AvatarRated(
                              profile: beacon.author,
                              size: 22,
                              withRating: false,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                beacon.author.title,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
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
                      const SizedBox(height: kSpacingSmall),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: scheme.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                      ),
                      const SizedBox(height: kSpacingSmall),
                      Wrap(
                        spacing: kSpacingMedium,
                        runSpacing: kSpacingSmall,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          BeaconCardMetaItem(
                            icon: Icons.topic_outlined,
                            child: Text(
                              contextCategoryLabel,
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
                              l10n.inboxCommitmentsCount(
                                beacon.commitmentCount,
                              ),
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
                                  fontWeight: hoursRemaining.urgent
                                      ? FontWeight.w600
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (beacon.images.isNotEmpty)
                            BeaconCardMetaItem(
                              icon: Icons.photo_library_outlined,
                              child: Text(
                                beacon.images.length > 99
                                    ? '99+'
                                    : '${beacon.images.length}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
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
              PopupMenuButton<String>(
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'open',
                    child: _inboxOverflowMenuRow(
                      Icons.open_in_new,
                      l10n.openBeacon,
                    ),
                  ),
                  if (onCommit != null)
                    PopupMenuItem(
                      value: 'commit',
                      child: _inboxOverflowMenuRow(
                        Icons.handshake,
                        l10n.labelCommit,
                      ),
                    ),
                  PopupMenuItem(
                    value: 'forward',
                    child: _inboxOverflowMenuRow(
                      Icons.send,
                      l10n.labelForward,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'view_forwards',
                    child: _inboxOverflowMenuRow(
                      Icons.forward_to_inbox,
                      l10n.labelForwards,
                    ),
                  ),
                  if (onWatch != null)
                    PopupMenuItem(
                      value: 'watch',
                      child: _inboxOverflowMenuRow(
                        Icons.visibility_outlined,
                        l10n.actionWatch,
                      ),
                    ),
                  if (onStopWatching != null)
                    PopupMenuItem(
                      value: 'stop_watch',
                      child: _inboxOverflowMenuRow(
                        Icons.visibility_off_outlined,
                        l10n.actionStopWatching,
                      ),
                    ),
                  if (onCantHelp != null)
                    PopupMenuItem(
                      value: 'cant_help',
                      child: _inboxOverflowMenuRow(
                        Icons.close,
                        l10n.actionCantHelp,
                      ),
                    ),
                  if (onMoveToInbox != null)
                    PopupMenuItem(
                      value: 'move_inbox',
                      child: _inboxOverflowMenuRow(
                        Icons.inbox_outlined,
                        l10n.actionMoveToInbox,
                      ),
                    ),
                ],
                onSelected: (v) async {
                  if (v == 'open') {
                    onOpenBeacon();
                    return;
                  }
                  if (v == 'commit') {
                    await onCommit?.call();
                    return;
                  }
                  if (v == 'forward') {
                    onTap();
                    return;
                  }
                  if (v == 'view_forwards') {
                    if (context.mounted) {
                      unawaited(
                        context.router.pushPath(
                          '$kPathBeaconForwards/${beacon.id}',
                        ),
                      );
                    }
                    return;
                  }
                  if (v == 'watch') onWatch?.call();
                  if (v == 'stop_watch') onStopWatching?.call();
                  if (v == 'cant_help') await onCantHelp?.call();
                  if (v == 'move_inbox') onMoveToInbox?.call();
                },
                child: Icon(
                  Icons.more_horiz,
                  color: scheme.onSurfaceVariant,
                ),
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
