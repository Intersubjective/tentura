import 'package:freezed_annotation/freezed_annotation.dart';

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
    String? diffJson,
  }) = _BeaconActivityEvent;
}
