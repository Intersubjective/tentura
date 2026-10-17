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
