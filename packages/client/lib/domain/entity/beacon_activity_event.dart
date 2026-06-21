import 'package:freezed_annotation/freezed_annotation.dart';

import 'beacon_activity_event_consts.dart';
import 'coordination_item.dart';

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
      BeaconActivityEventTypeBits.beaconLifecycleChanged => true,
      _ => false,
    };
  }

  /// Coordination-item kind for events encoded as `kind * 100 + eventKind`
  /// (see [BeaconActivityEventTypeBits]); `null` for non-coordination events
  /// (including promise = 500+). Range-checked because
  /// [CoordinationItemKind.fromInt] throws on unknown values.
  CoordinationItemKind? get coordinationKind =>
      (type >= BeaconActivityEventTypeBits.coordinationTypeMin &&
              type < BeaconActivityEventTypeBits.coordinationTypeMax)
          ? CoordinationItemKind.fromInt(type ~/ 100)
          : null;

  /// Coordination lifecycle state for a coordination event; `null` when this
  /// is not a coordination event or the remainder is not a known state.
  CoordinationItemEventKind? get coordinationEventKind =>
      coordinationKind == null
          ? null
          : CoordinationItemEventKind.fromInt(type % 100);
}
