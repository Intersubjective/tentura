import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
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

    final actions = _actions(l10n);

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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      kindLabel,
                      style: TenturaText.typeLabel(statusColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(L10n l10n) {
    if (!item.isActive) {
      return const [];
    }

    if (item.kind == CoordinationItemKind.blocker) {
      return [
        TenturaTextAction(
          label: l10n.coordinationBlockerActionResolve,
          onPressed: onResolve,
          tone: TenturaTone.good,
          icon: const Icon(Icons.check),
        ),
        TenturaTextAction(
          label: l10n.coordinationBlockerActionCancel,
          onPressed: onCancel,
          tone: TenturaTone.danger,
          icon: const Icon(Icons.close),
        ),
      ];
    }
    if (item.kind == CoordinationItemKind.resolution && item.isOpen) {
      return [
        TenturaTextAction(
          label: l10n.coordinationResolutionAcceptLabel,
          onPressed: onAccept,
          tone: TenturaTone.good,
          icon: const Icon(Icons.check),
        ),
        TenturaTextAction(
          label: l10n.coordinationResolutionRejectLabel,
          onPressed: onReject ?? onCancel,
          tone: TenturaTone.danger,
          icon: const Icon(Icons.close),
        ),
      ];
    }
    if (item.kind == CoordinationItemKind.plan && item.isPlanStep) {
      return [
        TenturaTextAction(
          label: l10n.coordinationBlockerActionResolve,
          onPressed: onResolve,
          tone: TenturaTone.good,
          icon: const Icon(Icons.check),
        ),
      ];
    }
    if (item.kind == CoordinationItemKind.ask) {
      if (item.isOpen && onAccept != null) {
        return [
          TenturaTextAction(
            label: l10n.coordinationAskAcceptLabel,
            onPressed: onAccept,
            icon: const Icon(Icons.handshake_outlined),
          ),
          TenturaTextAction(
            label: l10n.coordinationBlockerActionResolve,
            onPressed: onResolve,
            tone: TenturaTone.good,
            icon: const Icon(Icons.check),
          ),
          TenturaTextAction(
            label: l10n.coordinationBlockerActionCancel,
            onPressed: onCancel,
            tone: TenturaTone.danger,
            icon: const Icon(Icons.close),
          ),
        ];
      }
      if (item.isAccepted) {
        return [
          TenturaTextAction(
            label: l10n.coordinationBlockerActionResolve,
            onPressed: onResolve,
            tone: TenturaTone.good,
            icon: const Icon(Icons.check),
          ),
          TenturaTextAction(
            label: l10n.coordinationBlockerActionCancel,
            onPressed: onCancel,
            tone: TenturaTone.danger,
            icon: const Icon(Icons.close),
          ),
        ];
      }
    }
    return const [];
  }
}
