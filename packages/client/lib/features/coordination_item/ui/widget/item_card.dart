import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

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

class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.item,
    this.onOpenRoom,
    this.onResolve,
    this.onCancel,
    this.onAccept,
    this.onReject,
    super.key,
  });

  final CoordinationItem item;

  /// Primary card tap — typically opens the beacon room.
  final VoidCallback? onOpenRoom;
  final VoidCallback? onResolve;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenRoom,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: kSpacingSmall),
                  Expanded(
                    child: Text(
                      kindLabel,
                      style: textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                        _ItemMenuAction.accept => onAccept?.call(),
                        _ItemMenuAction.resolve => onResolve?.call(),
                        _ItemMenuAction.cancel => onCancel?.call(),
                        _ItemMenuAction.reject =>
                          (onReject ?? onCancel)?.call(),
                      },
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.title,
                style: textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(_ItemMenuAction, String)> _menuEntries(L10n l10n) {
    if (!item.published || !item.isActive) {
      return const [];
    }

    if (item.kind == CoordinationItemKind.blocker) {
      return [
        if (onResolve != null)
          (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
        if (onCancel != null)
          (_ItemMenuAction.cancel, l10n.coordinationBlockerActionCancel),
      ];
    }
    if (item.kind == CoordinationItemKind.resolution && item.isOpen) {
      return [
        if (onAccept != null)
          (_ItemMenuAction.accept, l10n.coordinationResolutionAcceptLabel),
        if (onReject != null || onCancel != null)
          (
            _ItemMenuAction.reject,
            l10n.coordinationResolutionRejectLabel,
          ),
      ];
    }
    if (item.kind == CoordinationItemKind.plan && item.isPlanStep) {
      return [
        if (onResolve != null)
          (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
      ];
    }
    if (item.kind == CoordinationItemKind.ask) {
      if (item.isOpen && onAccept != null) {
        return [
          (_ItemMenuAction.accept, l10n.coordinationAskAcceptLabel),
          if (onResolve != null)
            (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
          if (onCancel != null)
            (_ItemMenuAction.cancel, l10n.coordinationBlockerActionCancel),
        ];
      }
      if (item.isAccepted) {
        return [
          if (onResolve != null)
            (_ItemMenuAction.resolve, l10n.coordinationBlockerActionResolve),
          if (onCancel != null)
            (_ItemMenuAction.cancel, l10n.coordinationBlockerActionCancel),
        ];
      }
    }
    return const [];
  }
}
