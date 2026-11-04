import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

import '../constellation_field_patches.dart';
import '../entity/constellation_field.dart';

/// Applies a room message or room seen invalidation to unread flags on
/// [field], or returns null when the change does not affect unread state.
ConstellationField? patchFieldHasUnreadFromRealtime(
  ConstellationField field,
  RealtimeEntityChange change, {
  required String viewerId,
  required bool Function(String beaconId) isBeaconMuted,
}) {
  final beaconId = change.aggregateId;
  if (change.kind == RealtimeEntityKind.roomSeen) {
    if (change.readCursor == null) {
      return null;
    }
    final cleared = patchFieldBeaconHasUnread(
      field,
      beaconId,
      hasUnread: false,
    );
    return identical(cleared, field) ? null : cleared;
  }
  if (change.kind == RealtimeEntityKind.roomMessage) {
    if (viewerId.isEmpty) {
      return null;
    }
    final actor = change.actorUserId;
    if (actor == null || actor == viewerId) {
      return null;
    }
    if (isBeaconMuted(beaconId)) {
      return null;
    }
    final paint = change.roomMessagePaint;
    if (paint?.systemMessageKind != null) {
      return null;
    }
    if (change.operation != RealtimeOperation.insert && paint == null) {
      return null;
    }
    final marked = patchFieldBeaconHasUnread(
      field,
      beaconId,
      hasUnread: true,
    );
    return identical(marked, field) ? null : marked;
  }
  return null;
}
