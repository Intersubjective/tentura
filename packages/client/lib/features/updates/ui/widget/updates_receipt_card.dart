import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../widget/attention_visibility_ack.dart';

/// Single Updates feed row for one attention receipt.
class UpdatesReceiptCard extends StatelessWidget {
  const UpdatesReceiptCard({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    required this.onSettle,
    super.key,
  });

  final AttentionReceipt receipt;
  final VoidCallback onTap;
  final VoidCallback onMarkSeen;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final colors = Theme.of(context).colorScheme;
    final isUnread = !receipt.isSeen;
    final copy = resolveUpdatesReceiptDisplayCopy(
      title: receipt.title,
      body: receipt.body,
      presentationKey: receipt.presentationKey,
      l10n: l10n,
    );
    final requestTitle = _requestTitle();
    final localCreatedAt = receipt.createdAt.toLocal();
    final ageLabel = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';

    return AttentionVisibilityAck(
      receiptId: receipt.id,
      isSeen: receipt.isSeen,
      onAcknowledge: (_) async => onMarkSeen(),
      child: Semantics(
        label: copy.title,
        button: true,
        child: ListTile(
          onTap: onTap,
          contentPadding: tt.cardPadding,
          leading: Icon(
            _iconFor(receipt.kind),
            color: isUnread ? tt.info : tt.textMuted,
            size: tt.iconSize,
          ),
          title: Text(
            copy.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                TenturaText.title(
                  isUnread ? colors.onSurface : tt.textMuted,
                ).copyWith(
                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400,
                ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (requestTitle != null)
                Text(
                  requestTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              Text(
                copy.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
              if (receipt.isLiveObligation)
                Text(
                  l10n.updatesNextStepMarkDoneHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.bodySmall(tt.info),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: absoluteTime,
                child: Text(
                  ageLabel,
                  style: TenturaText.bodySmall(tt.textFaint),
                ),
              ),
              if (isUnread)
                IconButton(
                  tooltip: l10n.updatesMarkSeen,
                  onPressed: onMarkSeen,
                  icon: const Icon(Icons.done_outlined),
                ),
              if (receipt.isLiveObligation)
                IconButton(
                  tooltip: l10n.updatesMarkDone,
                  onPressed: onSettle,
                  icon: const Icon(Icons.task_alt_outlined),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _requestTitle() {
    if (receipt.beaconId == null || receipt.beaconId!.isEmpty) {
      return null;
    }
    final payloadTitle =
        beaconTitleFromPresentationPayload(receipt.presentationPayloadJson);
    if (payloadTitle != null) return payloadTitle;
    return null;
  }

  static IconData _iconFor(String kind) => switch (kind) {
    'needsMe' || 'blockerOpened' => Icons.notifications_active_outlined,
    'roomMention' => Icons.alternate_email,
    'roomActivityLowPriority' || 'newRelay' => Icons.forum_outlined,
    'inviteAccepted' => Icons.people_alt_outlined,
    _ => Icons.notifications_outlined,
  };
}
