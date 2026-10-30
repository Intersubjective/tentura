import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';

/// [RoomViewerFacts] of [viewerId] on [beacon], for unit tests that stub the
/// per-Request reads ([isSteward], [participant]) the batched read replaces.
/// Like the tier rule, it asks for a steward only when the viewer is not the
/// author, and for a participant only when they are not a steward either.
Future<RoomViewerFacts> roomViewerFactsFromStubs({
  required BeaconEntity beacon,
  required String viewerId,
  required Future<bool> Function() isSteward,
  required Future<BeaconParticipantRecord?> Function() participant,
}) async {
  final isAuthor = beacon.author.id == viewerId;
  final steward = !isAuthor && await isSteward();
  final roomAccess = isAuthor || steward
      ? null
      : (await participant())?.roomAccess;
  return RoomViewerFacts(
    beaconId: beacon.id,
    authorId: beacon.author.id,
    kind: beacon.kind,
    status: beacon.status,
    updatedAt: beacon.updatedAt,
    isSteward: steward,
    participantRoomAccess: roomAccess,
  );
}
