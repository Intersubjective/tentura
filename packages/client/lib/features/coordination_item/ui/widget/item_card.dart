import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

/// Accent color for a coordination item — shared with beacon Items / Log tabs.
Color coordinationItemColor(
  TenturaTokens tt,
  CoordinationItemKind kind,
  CoordinationItemStatus status,
) {
  if (status == CoordinationItemStatus.resolved ||
      status == CoordinationItemStatus.cancelled ||
      status == CoordinationItemStatus.superseded) {
    return tt.textMuted;
  }

  return switch (kind) {
    CoordinationItemKind.blocker => tt.danger,
    CoordinationItemKind.ask => switch (status) {
        CoordinationItemStatus.accepted => tt.good,
        _ => tt.warn,
      },
    CoordinationItemKind.resolution => tt.info,
    CoordinationItemKind.plan => tt.textMuted,
  };
}

enum _ItemMenuAction {
  edit,
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
  if (item.kind == CoordinationItemKind.resolution && item.isOpen) {
    return _ItemHeaderTier.medium;
  }
  if (item.kind == CoordinationItemKind.ask && item.isAccepted) {
    return _ItemHeaderTier.medium;
  }
  if (item.kind == CoordinationItemKind.plan) return _ItemHeaderTier.medium;
  return _ItemHeaderTier.low;
}

String? _formatStaleRemaining(L10n l10n, DateTime? staleAt) {
  if (staleAt == null) return null;
  final diff = staleAt.difference(DateTime.now());
  if (diff.isNegative) return l10n.itemStaleOverdue;
  if (diff.inDays >= 1) {
    return '${diff.inDays}d ${diff.inHours.remainder(24)}h';
  }
  if (diff.inHours >= 1) {
    return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  }
  return '${diff.inMinutes}m';
}

class ItemCard extends StatefulWidget {
  const ItemCard({
    required this.item,
    this.creatorParticipant,
    this.targetParticipant,
    this.onOpenItemThread,
    this.onResolve,
    this.onCancel,
    this.onAccept,
    this.onReject,
    this.onEdit,
    super.key,
  });

  final CoordinationItem item;

  /// Source/target participants for the header avatar trail ([coordinationItemCardAvatarTrail]).
  final BeaconParticipant? creatorParticipant;
  final BeaconParticipant? targetParticipant;

  /// Primary card tap — opens the beacon room scrolled to this item’s thread.
  final void Function(CoordinationItem item)? onOpenItemThread;
  final VoidCallback? onResolve;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onEdit;

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
      CoordinationItemKind.plan => item.isPlanStep
          ? l10n.coordinationPlanStepCardLabel
          : l10n.coordinationPlanCardLabel,
      CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
    };

    final statusIcon = switch (item.status) {
      CoordinationItemStatus.accepted => Icons.check_circle_outline,
      CoordinationItemStatus.resolved => Icons.check_circle,
      CoordinationItemStatus.cancelled => Icons.cancel_outlined,
      CoordinationItemStatus.superseded => Icons.swap_horiz,
      _ when item.kind == CoordinationItemKind.blocker => Icons.block,
      _ => Icons.help_outline,
    };

    final statusEntries = _statusMenuEntries(l10n);
    final menuEntries = _allMenuEntries(l10n, statusEntries);
    final showMenu = widget.onEdit != null ||
        (item.published && statusEntries.isNotEmpty);
    final headerTier = _itemHeaderTier(item);
    final eventIcon = Icon(
      statusIcon,
      size: kCoordinationLogEventIconSize,
      color: statusColor,
    );
    final avatarTrail = coordinationItemCardAvatarTrail(
      source: widget.creatorParticipant,
      target: widget.targetParticipant,
    );
    final hasAvatarTrail =
        widget.creatorParticipant != null ||
        widget.targetParticipant != null;
    final staleLabel = _formatStaleRemaining(l10n, item.staleAt);
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
                        if (staleLabel != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            staleLabel,
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
                  if (item.unreadCount > 0 && item.isActive) ...[
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
    return const [];
  }
}
