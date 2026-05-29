import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';

/// Patches room participant rows after a coordination response + room action.
List<BeaconParticipant> applyCoordinationRoomParticipantPatch({
  required List<BeaconParticipant> participants,
  required String offerUserId,
  required bool inviteToRoom,
  required bool removeFromRoom,
}) {
  if (!inviteToRoom && !removeFromRoom) {
    return participants;
  }
  final idx = participants.indexWhere((p) => p.userId == offerUserId);
  if (idx < 0) {
    if (!inviteToRoom) return participants;
    return [
      ...participants,
      BeaconParticipant(
        id: '',
        beaconId: '',
        userId: offerUserId,
        role: BeaconParticipantRoleBits.helper,
        status: BeaconParticipantStatusBits.committed,
        roomAccess: RoomAccessBits.admitted,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    ];
  }
  final p = participants[idx];
  final next = inviteToRoom
      ? p.copyWith(
          roomAccess: RoomAccessBits.admitted,
          status: BeaconParticipantStatusBits.committed,
          updatedAt: DateTime.now().toUtc(),
        )
      : p.copyWith(
          roomAccess: RoomAccessBits.none,
          updatedAt: DateTime.now().toUtc(),
        );
  return [...participants]..[idx] = next;
}

int? patchedHelpOfferRoomAccess({
  required int? current,
  required bool inviteToRoom,
  required bool removeFromRoom,
}) {
  if (removeFromRoom) return RoomAccessBits.none;
  if (inviteToRoom) return RoomAccessBits.admitted;
  return current;
}

CoordinationResponseType? coordinationResponseFromSmallint(int responseType) =>
    CoordinationResponseType.tryFromInt(responseType);
