import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'attention_visibility_ack.dart';

/// Updates feed row for trust-given / trust-received change receipts.
class TrustChangeReceiptCard extends StatefulWidget {
  const TrustChangeReceiptCard({
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
  State<TrustChangeReceiptCard> createState() => _TrustChangeReceiptCardState();
}

class _TrustChangeReceiptCardState extends State<TrustChangeReceiptCard> {
  bool _highlightActive = false;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.receipt.isSeen) {
      _highlightActive = true;
      _highlightTimer = Timer(const Duration(milliseconds: 220), () {
        if (mounted) setState(() => _highlightActive = false);
      });
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
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
    final requestTitle = _requestTitle(receipt);
    final localCreatedAt = receipt.createdAt.toLocal();
    final ageLabel = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';
    final direction = trustChangeDirectionFromPresentationKey(
      receipt.presentationKey ?? '',
    );
    final tone = switch (direction) {
      TrustChangeDirection.up => TenturaTone.good,
      TrustChangeDirection.down => TenturaTone.danger,
      TrustChangeDirection.neutral => TenturaTone.neutral,
    };
    final icon = switch (direction) {
      TrustChangeDirection.up => Icons.arrow_upward,
      TrustChangeDirection.down => Icons.arrow_downward,
      TrustChangeDirection.neutral => Icons.remove,
    };
    final iconColor = tenturaToneColor(tt, tone);
    final iconBackground = iconColor.withValues(alpha: 0.12);

    return AttentionVisibilityAck(
      receiptId: receipt.id,
      isSeen: receipt.isSeen,
      onAcknowledge: (_) async => widget.onMarkSeen(),
      child: Semantics(
        identifier: TestIds.updatesReceipt(receipt.id),
        label: copy.title,
        button: true,
        child: TenturaChangeHighlight(
          active: _highlightActive,
          child: ListTile(
            onTap: widget.onTap,
            contentPadding: tt.cardPadding,
            leading: _TrustToneGlyph(
              icon: icon,
              backgroundColor: iconBackground,
              iconColor: iconColor,
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
                    onPressed: widget.onMarkSeen,
                    icon: const Icon(Icons.done_outlined),
                  ),
                if (receipt.isLiveObligation)
                  IconButton(
                    tooltip: l10n.updatesMarkDone,
                    onPressed: widget.onSettle,
                    icon: const Icon(Icons.task_alt_outlined),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _requestTitle(AttentionReceipt receipt) {
    if (receipt.beaconId == null || receipt.beaconId!.isEmpty) {
      return null;
    }
    return beaconTitleFromPresentationPayload(receipt.presentationPayloadJson);
  }
}

class _TrustToneGlyph extends StatelessWidget {
  const _TrustToneGlyph({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final dimension = tt.iconSize;
    return SizedBox.square(
      dimension: dimension,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(dimension / 2),
        ),
        child: Icon(
          icon,
          size: dimension * 0.55,
          color: iconColor,
        ),
      ),
    );
  }
}
