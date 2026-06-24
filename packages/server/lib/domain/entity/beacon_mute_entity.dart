import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_mute_entity.freezed.dart';

/// A per-account mute of a specific beacon room.
///
/// [mutedUntil] null means muted indefinitely.
@freezed
abstract class BeaconMuteEntity with _$BeaconMuteEntity {
  const factory BeaconMuteEntity({
    required String accountId,
    required String beaconId,
    DateTime? mutedUntil,
  }) = _BeaconMuteEntity;

  const BeaconMuteEntity._();

  bool isActiveAt(DateTime now) =>
      mutedUntil == null || now.isBefore(mutedUntil!);
}
