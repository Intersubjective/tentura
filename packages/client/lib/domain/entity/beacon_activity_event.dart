import 'package:freezed_annotation/freezed_annotation.dart';

import 'beacon_activity_event_consts.dart';

part 'beacon_activity_event.freezed.dart';

@freezed
abstract class BeaconActivityEvent with _$BeaconActivityEvent {
  const factory BeaconActivityEvent({
    required String id,
    required String beaconId,
    required int visibility,
    required int type,
    required DateTime createdAt,
    String? actorId,
    String? targetUserId,
    String? sourceMessageId,
    String? coordinationItemId,
    String? diffJson,
  }) = _BeaconActivityEvent;

  const BeaconActivityEvent._();

  /// Meaningful coordination-log event (Log tab / My Work last-event row).
  ///
  /// Mirrors server [`isCoordinationLogEventType`].
  bool get isCoordinationLogEvent {
    if (type >= 100 && type < 500) return true;
    return switch (type) {
      BeaconActivityEventTypeBits.planUpdated => true,
      BeaconActivityEventTypeBits.factPinned => true,
      BeaconActivityEventTypeBits.blockerOpened => true,
      BeaconActivityEventTypeBits.blockerResolved => true,
      BeaconActivityEventTypeBits.needInfoOpened => true,
      BeaconActivityEventTypeBits.doneMarked => true,
      BeaconActivityEventTypeBits.factVisibilityChanged => true,
      BeaconActivityEventTypeBits.beaconPublished => true,
      _ => false,
    };
  }
}
