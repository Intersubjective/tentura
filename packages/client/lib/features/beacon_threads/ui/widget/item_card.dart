import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/widget/relative_timestamp_ticker.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_message_preview_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

import 'package:tentura/features/coordination_item/ui/widget/coordination_item_overflow_menu.dart';

enum _ItemHeaderTier { high, medium, low }

const _bodyPreviewThreshold = 60;

_ItemHeaderTier _itemHeaderTier(CoordinationItem item) {
  if (item.isCancelled || item.isSuperseded) return _ItemHeaderTier.low;
  if (item.isResolved) return _ItemHeaderTier.high;
  if (item.kind == CoordinationItemKind.blocker && item.isOpen) {
    return _ItemHeaderTier.high;
  }
  if (item.kind == CoordinationItemKind.ask && item.isOpen) {
    return _ItemHeaderTier.high;
  }
  if (item.kind == CoordinationItemKind.promise && item.isOpen) {
    return _ItemHeaderTier.high;
  }
  if (item.kind == CoordinationItemKind.ask && item.isAccepted) {
    return _ItemHeaderTier.medium;
  }
  if (item.kind == CoordinationItemKind.promise && item.isAccepted) {
    return _ItemHeaderTier.medium;
  }
  if (item.kind == CoordinationItemKind.plan) return _ItemHeaderTier.medium;
  return _ItemHeaderTier.low;
}

String? _formatStaleRemaining(CoordinationItem item) {
  if (!item.isActive) return null;
  final staleAt = item.staleAt;
  if (staleAt == null || item.isStale) return null;
  final diff = staleAt.difference(DateTime.now());
  if (diff.isNegative) return null;
  if (diff.inDays >= 1) {
    return '${diff.inDays}d ${diff.inHours.remainder(24)}h';
  }
  if (diff.inHours >= 1) {
    return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  }
  return '${diff.inMinutes}m';
}

String? _formatStaleOverdue(CoordinationItem item, L10n l10n) {
  final overdue = item.staleOverdueDuration();
  if (overdue == null) return null;
  if (overdue.inDays >= 1) {
    return l10n.itemStaleDays(overdue.inDays);
  }
  if (overdue.inHours >= 1) {
    return l10n.itemStaleHours(overdue.inHours);
  }
  return l10n.itemStaleMinutes(item.staleOverdueLabelAmount()!);
}

class ItemCard extends StatefulWidget {
  const ItemCard({
    required this.thread,
    required this.viewerProfile,
    this.participants = const [],
    this.resolvedUnreadCount,
    this.creatorParticipant,
    this.targetParticipant,
    this.responsibleParticipant,
    this.isSelected = false,
    this.onOpenThread,
    this.onResolve,
    this.onCancel,
    this.onAccept,
    this.onReject,
    this.onEdit,
    this.onRemind,
    super.key,
  });

  final RequestThread thread;
  final Profile viewerProfile;
  final List<BeaconParticipant> participants;
  final int? resolvedUnreadCount;

  /// Source/target participants for the header avatar trail ([coordinationItemCardAvatarTrail]).
  final BeaconParticipant? creatorParticipant;
  final BeaconParticipant? targetParticipant;

  /// Person who would receive a remind push — may differ from [targetParticipant].
  final BeaconParticipant? responsibleParticipant;

  /// Selected-row indicator — only set while an expanded split shows this thread.
  final bool isSelected;

  /// Primary card tap — opens the thread.
  final void Function(RequestThread thread)? onOpenThread;
  final VoidCallback? onResolve;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onEdit;
  final VoidCallback? onRemind;

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  bool _expanded = false;

  int get _displayUnreadCount =>
      widget.resolvedUnreadCount ?? widget.thread.unreadCount;

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final item = thread.item;
    final isGeneral = item == null;
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return RelativeTimestampTicker(
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: widget.isSelected
            ? RoundedRectangleBorder(
                side: BorderSide(color: tt.attentionHighlight, width: 2),
                borderRadius: BorderRadius.circular(tt.cardRadius),
              )
            : null,
        child: InkWell(
          onTap: widget.onOpenThread == null
              ? (thread.isDraft ? widget.onEdit : null)
              : () => widget.onOpenThread!(thread),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              tt.cardPadding.left,
              tt.rowGap,
              tt.cardPadding.right,
              tt.rowGap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isGeneral)
                  _buildGeneralHeader(context, l10n, textTheme, colorScheme, tt)
                else
                  _buildSemanticHeader(
                    context,
                    item,
                    l10n,
                    textTheme,
                    colorScheme,
                    tt,
                  ),
                if (thread.isDraft) ...[
                  SizedBox(height: tt.tightGap),
                  Text(
                    l10n.threadDraftBadge,
                    style: TenturaText.bodySmall(tt.warn),
                  ),
                ],
                if (!isGeneral && item.title.trim().isNotEmpty) ...[
                  SizedBox(height: tt.tightGap),
                  Text(
                    item.title.trim(),
                    style: textTheme.titleSmall,
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                  ),
                ],
                if (!isGeneral) ...[
                  ..._buildSemanticBody(item, l10n, textTheme, tt),
                ],
                ..._buildLastMessageRow(context, thread, l10n, textTheme, tt),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralHeader(
    BuildContext context,
    L10n l10n,
    TextTheme textTheme,
    ColorScheme colorScheme,
    TenturaTokens tt,
  ) {
    final thread = widget.thread;
    final unread = _displayUnreadCount;
    return Row(
      children: [
        Icon(Icons.forum_outlined, color: tt.info, size: tt.iconSize),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: Text(
            l10n.threadGeneralTitle,
            style: textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (thread.messageCount > 0) ...[
          SizedBox(width: tt.iconTextGap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: tt.tightGap * 2),
              TenturaCountBadge(
                count: thread.messageCount,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ],
        if (unread > 0) ...[
          SizedBox(width: tt.iconTextGap),
          TenturaCountBadge(count: unread, backgroundColor: tt.info),
        ],
      ],
    );
  }

  Widget _buildSemanticHeader(
    BuildContext context,
    CoordinationItem item,
    L10n l10n,
    TextTheme textTheme,
    ColorScheme colorScheme,
    TenturaTokens tt,
  ) {
    final statusColor = coordinationItemColor(tt, item.kind, item.status);
    final kindLabel = switch (item.kind) {
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
      CoordinationItemKind.plan => item.isPlanStep
          ? l10n.coordinationPlanStepCardLabel
          : l10n.coordinationPlanCardLabel,
    };
    final menuEntries = coordinationItemCardMenuEntries(
      l10n: l10n,
      item: item,
      viewerId: widget.viewerProfile.id,
      responsibleParticipant: widget.responsibleParticipant,
      includeEdit: widget.onEdit != null,
      includeRemind: widget.onRemind != null,
      canResolve: widget.onResolve != null,
      canCancel: widget.onCancel != null,
      canAccept: widget.onAccept != null,
      canReject: widget.onReject != null || widget.onCancel != null,
    );
    final showMenu = menuEntries.isNotEmpty;
    final headerTier = _itemHeaderTier(item);
    final eventIcon = coordinationCompoundStatusIcon(
      kind: item.kind,
      status: item.status,
      isPlanStep: item.isPlanStep,
      tt: tt,
    );
    final avatarTrail = coordinationItemCardAvatarTrailWithViewer(
      source: widget.creatorParticipant,
      target: widget.targetParticipant,
    );
    final hasAvatarTrail = item.kind.hasDirectedParties &&
        (widget.creatorParticipant != null ||
            widget.targetParticipant != null);
    final staleCountdown = _formatStaleRemaining(item);
    final staleOverdueLabel = _formatStaleOverdue(item, l10n);
    final unread = _displayUnreadCount;

    return Row(
      children: [
        eventIcon,
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  kindLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: headerTier == _ItemHeaderTier.high
                        ? FontWeight.w600
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (staleOverdueLabel != null)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: tt.iconTextGap),
                      Icon(
                        Icons.notification_important_outlined,
                        size: 14,
                        color: tt.warn,
                      ),
                      SizedBox(width: tt.tightGap * 2),
                      Flexible(
                        child: Text(
                          staleOverdueLabel,
                          style: textTheme.labelSmall?.copyWith(
                            color: tt.warn,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else if (staleCountdown != null)
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(left: tt.iconTextGap),
                    child: Text(
                      staleCountdown,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.thread.messageCount > 0) ...[
          SizedBox(width: tt.iconTextGap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: tt.tightGap * 2),
              TenturaCountBadge(
                count: widget.thread.messageCount,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ],
        if (unread > 0 &&
            item.isActive &&
            item.kind != CoordinationItemKind.plan) ...[
          SizedBox(width: tt.iconTextGap),
          TenturaCountBadge(count: unread, backgroundColor: tt.info),
        ],
        if (hasAvatarTrail) avatarTrail,
        if (hasAvatarTrail && showMenu) SizedBox(width: tt.rowGap),
        if (showMenu)
          CoordinationItemCardOverflowMenu(
            item: item,
            menuEntries: menuEntries,
            onSelected: (action) => switch (action) {
              CoordinationItemCardMenuAction.edit => widget.onEdit?.call(),
              CoordinationItemCardMenuAction.remind => widget.onRemind?.call(),
              CoordinationItemCardMenuAction.accept => widget.onAccept?.call(),
              CoordinationItemCardMenuAction.resolve =>
                widget.onResolve?.call(),
              CoordinationItemCardMenuAction.cancel => widget.onCancel?.call(),
              CoordinationItemCardMenuAction.reject =>
                (widget.onReject ?? widget.onCancel)?.call(),
            },
          ),
      ],
    );
  }

  List<Widget> _buildSemanticBody(
    CoordinationItem item,
    L10n l10n,
    TextTheme textTheme,
    TenturaTokens tt,
  ) {
    final contentPreview = item.contentPreview;
    final showBodyToggle = contentPreview.length > _bodyPreviewThreshold;
    if (contentPreview.isEmpty) return const [];

    return [
      SizedBox(height: tt.tightGap),
      Text(
        contentPreview,
        style: textTheme.bodyMedium,
        maxLines: _expanded ? null : 1,
        overflow: _expanded ? null : TextOverflow.ellipsis,
      ),
      if (showBodyToggle) ...[
        SizedBox(height: tt.tightGap),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: tt.rowGap),
              minimumSize: Size(tt.buttonHeight, tt.buttonHeight * 0.82),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? l10n.itemShowLess : l10n.itemShowMore),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildLastMessageRow(
    BuildContext context,
    RequestThread thread,
    L10n l10n,
    TextTheme textTheme,
    TenturaTokens tt,
  ) {
    final preview = thread.lastMessagePreview;
    final at = thread.lastMessageAt;
    if (preview == null && at == null) return const [];

    final previewText = preview == null
        ? ''
        : threadMessagePreviewText(
            preview: preview,
            l10n: l10n,
            participants: widget.participants,
            viewerProfile: widget.viewerProfile,
          );
    final authorPrefix = threadMessageAuthorPrefix(
      authorId: thread.lastMessageAuthorId,
      l10n: l10n,
      participants: widget.participants,
      viewerProfile: widget.viewerProfile,
    );
    final relativeLabel = at == null
        ? null
        : compactRelativeTimeAgo(
            when: at,
            now: DateTime.now(),
            l10n: l10n,
          );

    if (previewText.isEmpty && relativeLabel == null) return const [];

    return [
      SizedBox(height: tt.iconTextGap),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '${authorPrefix ?? ''}$previewText',
              style: textTheme.bodySmall?.copyWith(color: tt.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (relativeLabel != null) ...[
            SizedBox(width: tt.iconTextGap),
            Text(
              relativeLabel,
              style: textTheme.labelSmall?.copyWith(color: tt.textFaint),
            ),
          ],
        ],
      ),
    ];
  }
}

/// Keys a thread row for integration tests.
Key threadRowKey(RequestThread thread) =>
    TestIds.key(TestIds.requestThread(thread.threadId));
