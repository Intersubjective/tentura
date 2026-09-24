import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Sender-visible delivery/read glyph for the sender's own discussion messages.
class RoomMessageReceiptGlyph extends StatelessWidget {
  const RoomMessageReceiptGlyph({
    required this.receipt,
    super.key,
  });

  final RoomMessageReceipt receipt;

  static const double _iconSize = 12;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    final IconData iconData;
    final Color color;
    final String label;
    switch (receipt.state) {
      case RoomMessageReceiptState.pending:
        iconData = Icons.schedule;
        color = tt.textMuted;
        label = l10n.beaconRoomReceiptPending;
      case RoomMessageReceiptState.sent:
        iconData = Icons.done;
        color = tt.textMuted;
        label = l10n.beaconRoomReceiptSent;
      case RoomMessageReceiptState.read:
        iconData = Icons.done_all;
        color = tt.info;
        label = l10n.beaconRoomReceiptRead(receipt.readerIds.length);
    }

    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: ExcludeSemantics(
          child: Icon(iconData, size: _iconSize, color: color),
        ),
      ),
    );
  }
}
