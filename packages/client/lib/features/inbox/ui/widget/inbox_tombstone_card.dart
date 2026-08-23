import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

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
    final tt = context.tt;
    final scheme = theme.colorScheme;
    final isDeleted = item.status == InboxItemStatus.deletedBeforeResponse;
    final contextLabel =
        kShowBeaconCardContextCategory ? _tombstoneContextLine(item, l10n) : '';
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

    return BeaconCardShell(
      muted: true,
      color: scheme.surfaceContainerLow,
      padding: kPaddingAll,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (contextLabel.isNotEmpty) ...[
                          Text(
                            contextLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
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
                    padding: EdgeInsets.symmetric(
                      horizontal: tt.avatarTextGap,
                      vertical: tt.tightGap * 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(TenturaRadii.avatar),
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
                padding: EdgeInsets.symmetric(vertical: tt.screenHPadding),
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
                  SizedBox(width: tt.avatarTextGap),
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
                        SizedBox(height: tt.tightGap * 2),
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
              SizedBox(height: tt.screenHPadding),
              Row(
                children: [
                  FilledButton.tonal(
                    onPressed: onDismiss,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                        vertical: tt.cardGap,
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
