import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

/// Accent color for a coordination item — shared with log tab styling.
Color coordinationItemColor(
  ColorScheme cs,
  CoordinationItemKind kind,
  CoordinationItemStatus status,
) =>
    switch (status) {
      CoordinationItemStatus.open
          when kind == CoordinationItemKind.ask ||
              kind == CoordinationItemKind.blocker =>
        cs.error,
      CoordinationItemStatus.open => cs.primary,
      CoordinationItemStatus.accepted => cs.primary,
      CoordinationItemStatus.resolved => cs.tertiary,
      CoordinationItemStatus.cancelled => cs.outline,
      CoordinationItemStatus.superseded => cs.outline,
    };

enum _ItemMenuAction {
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
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    final statusColor = coordinationItemColor(
      colorScheme,
      item.kind,
      item.status,
    );

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

    final showMenu = item.published && item.isActive;
    final menuEntries = _menuEntries(l10n);
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
    final hasSourceAvatar = widget.creatorParticipant != null;
    final staleLabel = _formatStaleRemaining(l10n, item.staleAt);
    final createdLabel =
        coordinationLogTimestampLabel(item.createdAt.toUtc());
    final body = item.body.trim();
    final showBodyToggle = body.length > _bodyPreviewThreshold;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenItemThread == null
            ? null
            : () => widget.onOpenItemThread!(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  eventIcon,
                  const SizedBox(width: 6),
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
                  if (hasSourceAvatar) ...[
                    const SizedBox(width: 6),
                    avatarTrail,
                  ],
                  const Spacer(),
                  if (staleLabel != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      staleLabel,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (showMenu && menuEntries.isNotEmpty)
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
                        _ItemMenuAction.accept => widget.onAccept?.call(),
                        _ItemMenuAction.resolve => widget.onResolve?.call(),
                        _ItemMenuAction.cancel => widget.onCancel?.call(),
                        _ItemMenuAction.reject =>
                          (widget.onReject ?? widget.onCancel)?.call(),
                      },
                    )
                  else
                    const SizedBox(width: 44, height: 44),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  body,
                  style: textTheme.bodyMedium,
                  maxLines: _expanded ? null : 1,
                  overflow:
                      _expanded ? null : TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    createdLabel,
                    style: textTheme.labelSmall,
                  ),
                  const Spacer(),
                  if (showBodyToggle)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(44, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded ? l10n.itemShowLess : l10n.itemShowMore,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(_ItemMenuAction, String)> _menuEntries(L10n l10n) {
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
