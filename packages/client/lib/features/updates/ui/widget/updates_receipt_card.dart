import 'package:flutter/material.dart';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';

import 'updates_feed_tile.dart';

/// Single Updates feed row for one attention receipt.
class UpdatesReceiptCard extends StatelessWidget {
  const UpdatesReceiptCard({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    required this.onSettle,
    super.key,
  });

  final AttentionReceipt receipt;
  final VoidCallback onTap;
  final VoidCallback onMarkSeen;
  final VoidCallback onMarkUnseen;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) => UpdatesFeedTile(
    receipt: receipt,
    onTap: onTap,
    onMarkSeen: onMarkSeen,
    onMarkUnseen: onMarkUnseen,
    onSettle: onSettle,
  );
}
