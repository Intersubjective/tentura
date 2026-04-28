import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

class RoomMessageTile extends StatelessWidget {
  const RoomMessageTile({
    required this.message,
    required this.myProfile,
    this.onLongPress,
    super.key,
  });

  final RoomMessage message;

  /// Current user (for aligning / styling mine vs others').
  final Profile myProfile;

  /// e.g. pin-as-fact menu.
  final void Function(RoomMessage message)? onLongPress;

  static String _semanticShortLabel(int? marker) => switch (marker) {
        BeaconRoomSemanticMarker.updatePlan => 'Plan',
        BeaconRoomSemanticMarker.pinFactPublic => 'Public fact',
        BeaconRoomSemanticMarker.pinFactPrivate => 'Room fact',
        BeaconRoomSemanticMarker.participantStatusChanged => 'Status',
        BeaconRoomSemanticMarker.blocker => 'Blocker',
        BeaconRoomSemanticMarker.needInfo => 'Need info',
        BeaconRoomSemanticMarker.done => 'Done',
        _ => marker == null ? '' : 'System',
      };

  static String _bodyForDisplay(RoomMessage message) {
    final raw = message.body.trim();
    if (raw.isNotEmpty) return raw;
    final sp = message.systemPayloadJson;
    if (sp == null || sp.isEmpty) return '';
    try {
      final map = jsonDecode(sp);
      if (map is! Map<String, dynamic>) return '';
      final plan = map['currentPlan'];
      if (plan is String && plan.trim().isNotEmpty) return plan.trim();
      final fact = map['factText'];
      if (fact is String && fact.trim().isNotEmpty) return fact.trim();
      final req = map['requestText'];
      if (req is String && req.trim().isNotEmpty) return req.trim();
    } on Object catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = message.authorId == myProfile.id;
    final bubbleColor = isMine
        ? theme.colorScheme.primary.withValues(alpha: 0.14)
        : theme.colorScheme.surfaceContainerHighest;
    final align =
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final authorLabel =
        message.authorId.length <= 12
            ? message.authorId
            : '${message.authorId.substring(0, 10)}…';

    final semantic = _semanticShortLabel(message.semanticMarker);
    final display = _bodyForDisplay(message);
    final isStateCard = message.semanticMarker == BeaconRoomSemanticMarker.blocker ||
        message.semanticMarker == BeaconRoomSemanticMarker.needInfo ||
        message.semanticMarker == BeaconRoomSemanticMarker.done;

    return Padding(
      padding: kPaddingH.add(kPaddingSmallT),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            authorLabel,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: kSpacingSmall),
          InkWell(
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(message),
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isStateCard
                    ? theme.colorScheme.tertiaryContainer.withValues(
                        alpha: 0.35,
                      )
                    : bubbleColor,
                borderRadius: BorderRadius.circular(12),
                border: isStateCard
                    ? Border.all(color: theme.colorScheme.tertiary)
                    : null,
              ),
              child: Padding(
                padding: kPaddingH.add(kPaddingSmallT),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (semantic.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: kSpacingSmall / 2),
                        child: Text(
                          semantic,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (display.isNotEmpty)
                      SelectableText(
                        display,
                        style: theme.textTheme.bodyMedium,
                      ),
                    const SizedBox(height: kSpacingSmall),
                    Text(
                      _formatTime(message.createdAt),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}
