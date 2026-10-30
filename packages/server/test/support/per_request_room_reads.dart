import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

/// For room fakes that stub the per-Request reads: answers the batched
/// Requests-list reads from them, so a test keeps its per-Request stubs.
/// Rooms read this way are Requests (the fakes know no Posts).
mixin RoomReadsFromPerRequestStubs implements BeaconRoomRepositoryPort {
  @override
  Future<Map<String, RoomViewerFacts>> roomViewerFacts(
    Iterable<String> beaconIds, {
    required String viewerUserId,
  }) async => {
    for (final id in beaconIds)
      id: await _facts(id, viewerUserId),
  };

  Future<RoomViewerFacts> _facts(String id, String viewerUserId) async {
    final participant = await findParticipant(
      beaconId: id,
      userId: viewerUserId,
    );
    final state = await getBeaconRoomState(id);
    return RoomViewerFacts(
      beaconId: id,
      authorId: await isBeaconAuthor(beaconId: id, userId: viewerUserId)
          ? viewerUserId
          : null,
      kind: BeaconKind.request,
      status: BeaconStatus.open,
      updatedAt: DateTime.utc(2026),
      isSteward: await isBeaconSteward(beaconId: id, userId: viewerUserId),
      participantRoomAccess: participant?.roomAccess,
      nextMoveText: participant?.nextMoveText,
      currentLine: state?.currentLine,
      lastRoomMeaningfulChange: state?.lastRoomMeaningfulChange,
      lastSeenAt: await getMainRoomLastSeen(
        beaconId: id,
        userId: viewerUserId,
      ),
    );
  }

  @override
  Future<Map<String, int>> unreadMainRoomMessageCounts(
    Iterable<String> beaconIds, {
    required String viewerUserId,
  }) async => {
    for (final id in beaconIds)
      id: await countRoomMessagesAfter(
        beaconId: id,
        after: await getMainRoomLastSeen(beaconId: id, userId: viewerUserId),
        excludeAuthorId: viewerUserId,
      ),
  };
}

/// For item fakes that stub [listByBeacon]: answers the batched open-blocker
/// read from it.
mixin OpenBlockersFromListByBeacon implements CoordinationItemRepositoryPort {
  @override
  Future<Map<String, CoordinationItemRecord>> openBlockersByBeaconIds(
    Iterable<String> beaconIds, {
    required String viewerUserId,
  }) async => {
    for (final id in beaconIds)
      if (await listByBeacon(
            id,
            viewerUserId: viewerUserId,
            kind: coordinationItemKindBlocker,
            status: coordinationItemStatusOpen,
          )
          case [final first, ...])
        id: first.item,
  };
}
