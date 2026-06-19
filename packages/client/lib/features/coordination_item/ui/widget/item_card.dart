import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

enum _ItemMenuAction {
  edit,
  remind,
  accept,
  resolve,
  cancel,
  reject,
}

/// Mirrors beacon activity log tiers — drives header label weight only.
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

String _participantDisplayName(BeaconParticipant? participant) {
  if (participant == null) return '';
  final title = participant.userTitle.trim();
  if (title.isNotEmpty) return title;
  final id = participant.userId;
  return id.length <= 16 ? id : '${id.substring(0, 14)}…';
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

    final statusEntries = _statusMenuEntries(l10n);
    final menuEntries = _allMenuEntries(l10n, statusEntries);
    final showMenu = widget.onEdit != null ||
        (item.published && statusEntries.isNotEmpty);
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
    final showNeedsAttention = item.isActive && item.isStale;
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
                        if (showNeedsAttention) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.notification_important_outlined,
                            size: 14,
                            color: tt.warn,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.itemNeedsAttention,
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
                    PopupMenuButton<_ItemMenuAction>(
                      tooltip: l10n.beaconHudOverflowMore,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, size: 18),
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      itemBuilder: (ctx) => [
                        for (final e in menuEntries)
                          PopupMenuItem<_ItemMenuAction>(
                            value: e.$1,
                            child: Text(e.$2),
                          ),
                      ],
                      onSelected: (action) => switch (action) {
                        _ItemMenuAction.edit => widget.onEdit?.call(),
                        _ItemMenuAction.remind => widget.onRemind?.call(),
                        _ItemMenuAction.accept => widget.onAccept?.call(),
                        _ItemMenuAction.resolve => widget.onResolve?.call(),
                        _ItemMenuAction.cancel => widget.onCancel?.call(),
                        _ItemMenuAction.reject =>
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

  List<(_ItemMenuAction, String)> _allMenuEntries(
    L10n l10n,
    List<(_ItemMenuAction, String)> statusEntries,
  ) {
    final entries = <(_ItemMenuAction, String)>[];
    if (widget.onEdit != null) {
      entries.add((_ItemMenuAction.edit, l10n.helpOffersTabActionEdit));
    }
    final viewer = widget.viewerId;
    if (viewer != null &&
        widget.onRemind != null &&
        widget.item.canRemind(viewer)) {
      final name = _participantDisplayName(
        widget.responsibleParticipant,
      );
      entries.add((
        _ItemMenuAction.remind,
        name.isEmpty ? l10n.itemNeedsAttention : l10n.remindAction(name),
      ));
    }
    entries.addAll(statusEntries);
    return entries;
  }

  List<(_ItemMenuAction, String)> _statusMenuEntries(L10n l10n) {
    final item = widget.item;
    if (!item.published || !item.isActive) {
      return const [];
    }

    if (item.kind == CoordinationItemKind.blocker) {
      return [
        if (widget.onResolve != null)
          (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
        if (widget.onCancel != null)
          (_ItemMenuAction.cancel, l10n.coordinationBlockerActionCancel),
      ];
    }
    if (item.kind == CoordinationItemKind.resolution && item.isOpen) {
      return [
        if (widget.onAccept != null)
          (_ItemMenuAction.accept, l10n.coordinationResolutionAcceptLabel),
        if (widget.onReject != null || widget.onCancel != null)
          (
            _ItemMenuAction.reject,
            l10n.coordinationResolutionRejectLabel,
          ),
      ];
    }
    if (item.kind == CoordinationItemKind.plan && item.isPlanStep) {
      return [
        if (widget.onResolve != null)
          (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
      ];
    }
    if (item.kind == CoordinationItemKind.ask) {
      if (item.isOpen && widget.onAccept != null) {
        return [
          (_ItemMenuAction.accept, l10n.coordinationAskAcceptLabel),
          if (widget.onResolve != null)
            (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
          if (widget.onCancel != null)
            (_ItemMenuAction.cancel, l10n.coordinationBlockerActionCancel),
        ];
      }
      if (item.isAccepted) {
        return [
          if (widget.onResolve != null)
            (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
          if (widget.onCancel != null)
            (_ItemMenuAction.cancel, l10n.coordinationBlockerActionCancel),
        ];
      }
    }
    if (item.kind == CoordinationItemKind.promise) {
      if (item.isOpen && widget.onAccept != null) {
        return [
          (_ItemMenuAction.accept, l10n.coordinationPromiseAcceptLabel),
          if (widget.onResolve != null)
            (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
          if (widget.onCancel != null)
            (_ItemMenuAction.cancel, l10n.coordinationBlockerActionCancel),
        ];
      }
      if (item.isAccepted) {
        return [
          if (widget.onResolve != null)
            (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
          if (widget.onCancel != null)
            (_ItemMenuAction.cancel, l10n.coordinationBlockerActionCancel),
        ];
      }
    }
    return const [];
  }
}
