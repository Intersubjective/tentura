import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/beacon_room_lifecycle_write_policy.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';

/// Thrown when a room write is refused because the discussion is read-only.
const kRoomReadOnlyException = BeaconCreateException(
  description: 'Discussion is read-only for this request',
);

/// Room read-only checks shared by the room, poll and baton use cases.
///
/// Expired-post state and read-only refusal classification come from
/// [BeaconRoomWriteStatePort]; a hierarchy repository that does not implement
/// it (test fakes) reports neither.
extension RoomWriteGuard on BeaconHierarchyRepositoryPort {
  /// The hierarchy repository as a [BeaconRoomWriteStatePort], when it is one.
  BeaconRoomWriteStatePort? get _writeState => switch (this) {
    final BeaconRoomWriteStatePort state => state,
    _ => null,
  };

  /// Whether [beaconId] is an expired post; false when unknown.
  Future<bool> isExpiredPostForRoomWrite(String beaconId) async =>
      await _writeState?.isExpiredPost(beaconId) ?? false;

  /// Whether [error] is the database refusing a write to a read-only room.
  bool isReadOnlyRoomWriteError(Object error) =>
      _writeState?.isReadOnlyWriteError(error) ?? false;

  /// Whether the room of [beaconId] refuses ordinary user writes: its
  /// lifecycle status blocks them, or it is an expired post.
  Future<bool> isRoomReadOnly(String beaconId) async {
    final status = await loadBeaconStatus(beaconId);
    if (status != null &&
        BeaconRoomLifecycleWritePolicy.blocksOrdinaryUserWrites(status)) {
      return true;
    }
    return isExpiredPostForRoomWrite(beaconId);
  }

  /// Throws [kRoomReadOnlyException] when [isRoomReadOnly].
  Future<void> rejectIfRoomReadOnly(String beaconId) async {
    if (await isRoomReadOnly(beaconId)) {
      throw kRoomReadOnlyException;
    }
  }

  /// Runs [action], turning a read-only refusal into [kRoomReadOnlyException].
  Future<T> translateRoomWriteError<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      if (isReadOnlyRoomWriteError(error)) {
        throw kRoomReadOnlyException;
      }
      rethrow;
    }
  }
}
