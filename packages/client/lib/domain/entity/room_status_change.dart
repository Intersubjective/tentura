import 'dart:convert';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';

/// What a `statusChanged` system line says (server contract, U090):
/// payload `{version: 1, fromStatus, toStatus, reason}` with smallint
/// statuses. The actor is the line's author; a null author is either a
/// change nobody made (the wrapping-up window ran out) or an actor whose
/// account was deleted since (`author_id` is `ON DELETE SET NULL`).
class RoomStatusChange {
  const RoomStatusChange({
    required this.from,
    required this.to,
    required this.reason,
  });

  /// Null for any other row or an unreadable payload.
  static RoomStatusChange? fromMessage(RoomMessage m) {
    if (m.systemMessageKind != BeaconRoomSystemMessageKind.statusChanged) {
      return null;
    }
    final raw = m.systemPayloadJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] != 1) return null;
      final from = decoded['fromStatus'];
      final to = decoded['toStatus'];
      if (from is! int || to is! int) return null;
      final reason = decoded['reason'];
      return RoomStatusChange(
        from: BeaconStatus.fromSmallint(from),
        to: BeaconStatus.fromSmallint(to),
        reason: reason is String ? reason : '',
      );
    } on Object {
      return null;
    }
  }

  final BeaconStatus from;
  final BeaconStatus to;

  /// A [BeaconLifecycleChangeReason] wire value.
  final String reason;

  /// Nobody made this change: the wrapping-up window ran out.
  bool get isAutomatic =>
      reason == BeaconLifecycleChangeReason.closureExpired ||
      reason == BeaconLifecycleChangeReason.reviewExpired;
}

/// Drops the discussion's «Final check» step when the server says the review
/// window never applied (#825). The open line goes away, and the following
/// close line starts from the status before that step, so the chat does not
/// say the Request went through a final check.
List<RoomMessage> omitSkippedFinalCheckStatusLines(List<RoomMessage> messages) {
  RoomStatusChange? opened;
  String? openedId;
  for (final message in messages) {
    final change = RoomStatusChange.fromMessage(message);
    if (change == null) continue;
    if ((change.reason == BeaconLifecycleChangeReason.closureOpened ||
            change.reason ==
                BeaconLifecycleChangeReason.legacyClosureOpenReason) &&
        change.to == BeaconStatus.reviewOpen) {
      opened = change;
      openedId = message.id;
    }
  }
  if (opened == null || openedId == null) return messages;
  final from = opened.from.smallintValue;
  return [
    for (final message in messages)
      if (message.id != openedId)
        _rewriteImmediateClose(message, fromStatus: from),
  ];
}

RoomMessage _rewriteImmediateClose(
  RoomMessage message, {
  required int fromStatus,
}) {
  final change = RoomStatusChange.fromMessage(message);
  if (change == null ||
      change.reason != BeaconLifecycleChangeReason.authorCloseNow ||
      change.from != BeaconStatus.reviewOpen) {
    return message;
  }
  final raw = message.systemPayloadJson;
  if (raw == null) return message;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return message;
    decoded['fromStatus'] = fromStatus;
    return message.copyWith(systemPayloadJson: jsonEncode(decoded));
  } on Object {
    return message;
  }
}
