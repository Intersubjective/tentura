import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Compact inline rendering of a coordination item event in the Room message
/// timeline. Displayed when `roomMessage.linkedItemId != null`.
class ItemCardInRoom extends StatelessWidget {
  const ItemCardInRoom({
    required this.item,
    required this.eventKind,
    this.timelineAuthorId,
    this.onTap,
    super.key,
  });

  final CoordinationItem item;
  final CoordinationItemEventKind eventKind;
  final String? timelineAuthorId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final tt = context.tt;

    final selfCommitmentAccepted = item.kind == CoordinationItemKind.ask &&
        eventKind == CoordinationItemEventKind.accepted &&
        (item.source == 1 ||
            (timelineAuthorId != null &&
                timelineAuthorId == item.creatorId));

    final label = switch (item.kind) {
      CoordinationItemKind.ask => switch (eventKind) {
          CoordinationItemEventKind.created =>
            l10n.coordinationSemanticAskOpened,
          CoordinationItemEventKind.accepted => selfCommitmentAccepted
              ? l10n.coordinationSemanticSelfAskAccepted
              : l10n.coordinationSemanticAskAccepted,
          CoordinationItemEventKind.resolved =>
            l10n.coordinationSemanticAskResolved,
          CoordinationItemEventKind.cancelled =>
            l10n.coordinationSemanticAskCancelled,
          _ => l10n.coordinationAskCardLabel,
        },
      CoordinationItemKind.blocker => switch (eventKind) {
          CoordinationItemEventKind.created =>
            l10n.coordinationSemanticBlockerOpened,
          CoordinationItemEventKind.resolved =>
            l10n.coordinationSemanticBlockerResolved,
          CoordinationItemEventKind.cancelled =>
            l10n.coordinationSemanticBlockerCancelled,
          _ => l10n.coordinationBlockerCardLabel,
        },
      CoordinationItemKind.resolution => switch (eventKind) {
          CoordinationItemEventKind.created =>
            l10n.coordinationSemanticResolutionOpened,
          CoordinationItemEventKind.resolved =>
            l10n.coordinationSemanticResolutionResolved,
          CoordinationItemEventKind.cancelled =>
            l10n.coordinationSemanticResolutionCancelled,
          _ => l10n.coordinationResolutionCardLabel,
        },
      CoordinationItemKind.plan => switch (eventKind) {
          CoordinationItemEventKind.created ||
          CoordinationItemEventKind.updated =>
            l10n.coordinationSemanticPlanOpened,
          CoordinationItemEventKind.superseded =>
            l10n.coordinationSemanticPlanSuperseded,
          CoordinationItemEventKind.resolved =>
            item.isPlanStep
                ? l10n.coordinationSemanticPlanStepResolved
                : l10n.coordinationSemanticPlanOpened,
          _ => l10n.coordinationPlanCardLabel,
        },
    };

    final iconData = switch (item.kind) {
      CoordinationItemKind.ask => switch (eventKind) {
          CoordinationItemEventKind.created => Icons.help_outline,
          CoordinationItemEventKind.accepted => Icons.handshake_outlined,
          CoordinationItemEventKind.resolved => Icons.check_circle_outline,
          CoordinationItemEventKind.cancelled => Icons.cancel_outlined,
          _ => Icons.help_outline,
        },
      _ => switch (eventKind) {
          CoordinationItemEventKind.created => Icons.block,
          CoordinationItemEventKind.resolved => Icons.check_circle_outline,
          CoordinationItemEventKind.cancelled => Icons.cancel_outlined,
          _ => Icons.info_outline,
        },
    };

    final color = switch (eventKind) {
      CoordinationItemEventKind.created => colorScheme.error,
      CoordinationItemEventKind.accepted => colorScheme.primary,
      CoordinationItemEventKind.resolved => colorScheme.primary,
      CoordinationItemEventKind.cancelled => tt.textMuted,
      _ => colorScheme.secondary,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(iconData, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: textTheme.labelSmall?.copyWith(color: color),
                  ),
                  if (item.title.isNotEmpty)
                    Text(
                      item.title,
                      style: textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
