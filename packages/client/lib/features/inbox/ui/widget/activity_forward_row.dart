import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'activity_event_subcard_block.dart';
import 'activity_forward_outcome_copy.dart';

/// Compact answered-forward row in the Activity stream (design §5.1 / §5.2).
class ActivityForwardRow extends StatelessWidget {
  const ActivityForwardRow({
    required this.receipt,
    required this.onOpenBeacon,
    this.onRestore,
    this.onHide,
    this.onMarkEventSeen,
    super.key,
  });

  final AttentionReceipt receipt;
  final VoidCallback onOpenBeacon;
  final VoidCallback? onRestore;
  final VoidCallback? onHide;
  final ValueChanged<String>? onMarkEventSeen;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final beaconId = receipt.beaconId ?? '';
    final headline = activityForwardRowHeadline(receipt, l10n);
    final outcomeLabel = activityForwardOutcomeLabel(l10n, receipt.forwardOutcome);
    final isUnread = !receipt.isSeen;
    final glyph = updatesFeedGlyphFor(receipt, tt);
    final localCreatedAt = receipt.createdAt.toLocal();
    final ageLabel = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';

    Widget? trailingAction;
    switch (receipt.forwardOutcome) {
      case AttentionForwardOutcome.notInterested:
        trailingAction = TenturaTextAction(
          label: l10n.activityForwardRestore,
          onPressed: onRestore,
        );
      case AttentionForwardOutcome.closedBeforeResponse:
      case AttentionForwardOutcome.deletedBeforeResponse:
        trailingAction = TenturaTextAction(
          label: l10n.actionHide,
          onPressed: onHide,
        );
      default:
        trailingAction = null;
    }

    final eventsBlock = receipt.eventsPreview.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.only(
              left: tt.listRowPadding.left,
              right: tt.listRowPadding.right,
            ),
            child: ActivityEventSubcardBlock(
              eventTotal: receipt.eventTotal ?? receipt.eventsPreview.length,
              eventsPreview: receipt.eventsPreview,
              beaconId: beaconId,
              onMarkSeen: onMarkEventSeen ?? (_) {},
            ),
          );

    return Semantics(
      identifier: TestIds.activityForwardRow(beaconId),
      button: true,
      label: headline,
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onOpenBeacon,
              child: Padding(
                padding: tt.listRowPadding,
                child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: tt.avatarSize,
                  child: Icon(
                    glyph.icon,
                    size: tt.iconSize,
                    color: glyph.color,
                  ),
                ),
                SizedBox(width: tt.avatarTextGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TenturaText.titleSmall(scheme.onSurface)
                                  .copyWith(
                                fontWeight: isUnread
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(width: tt.iconTextGap),
                          Tooltip(
                            message: absoluteTime,
                            child: Text(
                              ageLabel,
                              style: TenturaText.withTabular(
                                TenturaText.bodySmall(tt.textFaint),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (outcomeLabel != null) ...[
                        SizedBox(height: tt.tightGap),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                outcomeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.bodySmall(tt.textMuted),
                              ),
                            ),
                            if (trailingAction != null) trailingAction,
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
              ),
            ),
            if (eventsBlock != null) eventsBlock,
          ],
        ),
      ),
    );
  }
}
