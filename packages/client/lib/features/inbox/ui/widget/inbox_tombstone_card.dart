import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';

String _tombstoneContextLine(InboxItem item, L10n l10n) {
  final beacon = item.beacon;
  if (beacon == null) return l10n.inboxCategoryGeneral;
  final c = beacon.context.trim();
  return c.isEmpty ? l10n.inboxCategoryGeneral : c;
}

/// Passive “resolved before you acted” card (before-response terminal).
class InboxTombstoneCard extends StatelessWidget {
  const InboxTombstoneCard({
    required this.item,
    required this.onOpen,
    required this.onDismiss,
    super.key,
  });

  final InboxItem item;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDeleted = item.status == InboxItemStatus.deletedBeforeResponse;
    final contextLabel = _tombstoneContextLine(item, l10n);
    final title = isDeleted
        ? l10n.inboxTombstoneDeletedTitle
        : (item.beacon?.title.trim().isNotEmpty ?? false)
            ? item.beacon!.title.trim()
            : l10n.inboxTombstoneClosedTitle;
    final pillLabel = isDeleted
        ? l10n.inboxTombstoneStatusUnavailable
        : l10n.inboxTombstoneStatusResolved;
    final messageTitle = isDeleted
        ? l10n.inboxTombstoneDeletedTitle
        : l10n.inboxTombstoneClosedTitle;
    final messageBody = isDeleted
        ? l10n.inboxTombstoneDeletedSubtitle
        : l10n.inboxTombstoneClosedSubtitle;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contextLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        pillLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle_outline,
                        color: scheme.outline,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            messageTitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            messageBody,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.65,
                              ),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: onDismiss,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(l10n.inboxTombstoneDismiss),
                    ),
                    TextButton(
                      onPressed: onOpen,
                      child: Text(
                        l10n.inboxTombstoneOpen,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: -32,
            bottom: -32,
            child: Icon(
              Icons.inventory_2_outlined,
              size: 120,
              color: scheme.onSurface.withValues(alpha: 0.03),
            ),
          ),
        ],
      ),
    );
  }
}
