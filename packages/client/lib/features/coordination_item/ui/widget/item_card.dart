import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.item,
    this.onResolve,
    this.onCancel,
    this.onAccept,
    this.onReject,
    this.onTap,
    super.key,
  });

  final CoordinationItem item;
  final VoidCallback? onResolve;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    final statusColor = switch (item.status) {
      CoordinationItemStatus.open => colorScheme.error,
      CoordinationItemStatus.accepted => colorScheme.primary,
      CoordinationItemStatus.resolved => colorScheme.primary,
      CoordinationItemStatus.cancelled => colorScheme.outline,
      _ => colorScheme.secondary,
    };

    final kindLabel = switch (item.kind) {
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.plan => item.isPlanStep
          ? l10n.coordinationPlanStepCardLabel
          : l10n.coordinationPlanCardLabel,
      CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
      _ => l10n.coordinationItemCardTitle,
    };

    final statusIcon = switch (item.status) {
      CoordinationItemStatus.accepted => Icons.check_circle_outline,
      CoordinationItemStatus.resolved => Icons.check_circle,
      CoordinationItemStatus.cancelled => Icons.cancel_outlined,
      _ when item.kind == CoordinationItemKind.blocker => Icons.block,
      _ => Icons.help_outline,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              kindLabel,
                              style: textTheme.labelSmall?.copyWith(
                                color: statusColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (item.isActive)
                    Flexible(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        alignment: WrapAlignment.end,
                        children: _actionChips(l10n),
                      ),
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

  List<Widget> _actionChips(L10n l10n) {
    if (item.kind == CoordinationItemKind.blocker) {
      return [
        _ActionChip(
          label: l10n.coordinationBlockerActionResolve,
          onPressed: onResolve,
          icon: Icons.check,
        ),
        const SizedBox(width: 4),
        _ActionChip(
          label: l10n.coordinationBlockerActionCancel,
          onPressed: onCancel,
          icon: Icons.close,
        ),
      ];
    }
    if (item.kind == CoordinationItemKind.resolution && item.isOpen) {
      return [
        _ActionChip(
          label: l10n.coordinationResolutionAcceptLabel,
          onPressed: onAccept,
          icon: Icons.check,
        ),
        const SizedBox(width: 4),
        _ActionChip(
          label: l10n.coordinationResolutionRejectLabel,
          onPressed: onReject ?? onCancel,
          icon: Icons.close,
        ),
      ];
    }
    if (item.kind == CoordinationItemKind.plan && item.isPlanStep) {
      return [
        _ActionChip(
          label: l10n.coordinationBlockerActionResolve,
          onPressed: onResolve,
          icon: Icons.check,
        ),
      ];
    }
    if (item.kind == CoordinationItemKind.ask) {
      if (item.isOpen && onAccept != null) {
        return [
          _ActionChip(
            label: l10n.coordinationAskAcceptLabel,
            onPressed: onAccept,
            icon: Icons.handshake_outlined,
          ),
          const SizedBox(width: 4),
          _ActionChip(
            label: l10n.coordinationBlockerActionResolve,
            onPressed: onResolve,
            icon: Icons.check,
          ),
          const SizedBox(width: 4),
          _ActionChip(
            label: l10n.coordinationBlockerActionCancel,
            onPressed: onCancel,
            icon: Icons.close,
          ),
        ];
      }
      if (item.isAccepted) {
        return [
          _ActionChip(
            label: l10n.coordinationBlockerActionResolve,
            onPressed: onResolve,
            icon: Icons.check,
          ),
          const SizedBox(width: 4),
          _ActionChip(
            label: l10n.coordinationBlockerActionCancel,
            onPressed: onCancel,
            icon: Icons.close,
          ),
        ];
      }
    }
    return const [];
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.onPressed,
    required this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
