import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/port/beacon_room_co_participant_lookup_port.dart';

import '../database/tentura_db.dart';

/// Batch-friendly admitted beacon-room co-participant lookup.
@LazySingleton(as: BeaconRoomCoParticipantLookupPort)
class BeaconRoomCoParticipantLookup
    implements BeaconRoomCoParticipantLookupPort {
  BeaconRoomCoParticipantLookup(this._database);

  final TenturaDb _database;

  @override
  Future<Set<String>> coParticipantPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async {
    final candidates = peerIds
        .where((id) => id.isNotEmpty && id != viewerId)
        .toList();
    if (candidates.isEmpty) {
      return {};
    }

    final viewerBeaconRows = await (_database.select(
      _database.beaconParticipants,
    )..where(
      (p) =>
          p.userId.equals(viewerId) &
          p.roomAccess.equals(RoomAccessBits.admitted),
    )).get();
    if (viewerBeaconRows.isEmpty) {
      return {};
    }

    final viewerBeaconIds = viewerBeaconRows.map((r) => r.beaconId).toSet();
    final coParticipantRows = await (_database.select(
      _database.beaconParticipants,
    )..where(
      (p) =>
          p.beaconId.isIn(viewerBeaconIds) &
          p.userId.isIn(candidates) &
          p.roomAccess.equals(RoomAccessBits.admitted),
    )).get();
    return coParticipantRows.map((r) => r.userId).toSet();
  }
}
