import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

import 'coordination_item_overflow_menu.dart';

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
  if (item.kind == CoordinationItemKind.resolution && item.isOpen) {
    return _ItemHeaderTier.medium;
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
    required this.item,
    this.creatorParticipant,
    this.targetParticipant,
    this.responsibleParticipant,
    this.viewerId,
    this.onOpenItemThread,
    this.onResolve,
    this.onCancel,
    this.onAccept,
    this.onReject,
    this.onEdit,
    this.onRemind,
    super.key,
  });

  final CoordinationItem item;

  /// Source/target participants for the header avatar trail ([coordinationItemCardAvatarTrail]).
  final BeaconParticipant? creatorParticipant;
  final BeaconParticipant? targetParticipant;

  /// Person who would receive a remind push — may differ from [targetParticipant].
  final BeaconParticipant? responsibleParticipant;

  /// Current viewer — gates remind when equal to [CoordinationItem.responsibleUserId].
  final String? viewerId;

  /// Primary card tap — opens the beacon room scrolled to this item’s thread.
  final void Function(CoordinationItem item)? onOpenItemThread;
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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    final statusColor = coordinationItemColor(tt, item.kind, item.status);

    final kindLabel = switch (item.kind) {
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
      CoordinationItemKind.plan => item.isPlanStep
          ? l10n.coordinationPlanStepCardLabel
          : l10n.coordinationPlanCardLabel,
      CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
    };

    final menuEntries = coordinationItemCardMenuEntries(
      l10n: l10n,
      item: item,
      viewerId: widget.viewerId,
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
    final avatarTrail = coordinationItemCardAvatarTrail(
      source: widget.creatorParticipant,
      target: widget.targetParticipant,
    );
    final hasAvatarTrail =
        widget.creatorParticipant != null ||
        widget.targetParticipant != null;
    final staleCountdown = _formatStaleRemaining(item);
    final staleOverdueLabel = _formatStaleOverdue(item, l10n);
    final contentPreview = item.contentPreview;
    final showBodyToggle = contentPreview.length > _bodyPreviewThreshold;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenItemThread == null
            ? null
            : () => widget.onOpenItemThread!(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  eventIcon,
                  const SizedBox(width: 6),
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
                        if (staleOverdueLabel != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.notification_important_outlined,
                            size: 14,
                            color: tt.warn,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            staleOverdueLabel,
                            style: textTheme.labelSmall?.copyWith(
                              color: tt.warn,
                            ),
                          ),
                        ] else if (staleCountdown != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            staleCountdown,
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (item.messageCount > 0) ...[
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        TenturaCountBadge(
                          count: item.messageCount,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      ],
                    ),
                  ],
                  if (item.unreadCount > 0 &&
                      item.isActive &&
                      item.kind != CoordinationItemKind.plan) ...[
                    const SizedBox(width: 6),
                    TenturaCountBadge(
                      count: item.unreadCount,
                      backgroundColor: tt.info,
                    ),
                  ],
                  if (hasAvatarTrail) avatarTrail,
                  if (hasAvatarTrail && showMenu) const SizedBox(width: 8),
                  if (showMenu)
                    CoordinationItemCardOverflowMenu(
                      item: item,
                      menuEntries: menuEntries,
                      onSelected: (action) => switch (action) {
                        CoordinationItemCardMenuAction.edit =>
                          widget.onEdit?.call(),
                        CoordinationItemCardMenuAction.remind =>
                          widget.onRemind?.call(),
                        CoordinationItemCardMenuAction.accept =>
                          widget.onAccept?.call(),
                        CoordinationItemCardMenuAction.resolve =>
                          widget.onResolve?.call(),
                        CoordinationItemCardMenuAction.cancel =>
                          widget.onCancel?.call(),
                        CoordinationItemCardMenuAction.reject =>
                          (widget.onReject ?? widget.onCancel)?.call(),
                      },
                    ),
                ],
              ),
              if (contentPreview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  contentPreview,
                  style: textTheme.bodyMedium,
                  maxLines: _expanded ? null : 1,
                  overflow:
                      _expanded ? null : TextOverflow.ellipsis,
                ),
              ],
              if (showBodyToggle) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(44, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? l10n.itemShowLess : l10n.itemShowMore,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
