import 'package:flutter/material.dart';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'updates_feed_tile.dart';

/// Single Updates feed row for one attention receipt.
class UpdatesReceiptCard extends StatelessWidget {
  const UpdatesReceiptCard({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    this.onSettle,
    this.action,
    this.actor,
    this.unreadView = false,
    this.viewerUserId,
    super.key,
  });

  final AttentionReceipt receipt;
  final VoidCallback onTap;
  final VoidCallback onMarkSeen;
  final VoidCallback onMarkUnseen;
  final VoidCallback? onSettle;
  final Widget? action;
  final Profile? actor;

  /// Passed to [UpdatesFeedTile.unreadView] (#736).
  final bool unreadView;

  /// Replaces the viewer's name with «You» on forward-helped path rows (#774).
  final String? viewerUserId;

  @override
  Widget build(BuildContext context) => UpdatesFeedTile(
    receipt: receipt,
    actor: actor,
    onTap: onTap,
    onMarkSeen: onMarkSeen,
    onMarkUnseen: onMarkUnseen,
    onSettle: onSettle,
    action: action,
    unreadView: unreadView,
    viewerUserId: viewerUserId,
  );
}
