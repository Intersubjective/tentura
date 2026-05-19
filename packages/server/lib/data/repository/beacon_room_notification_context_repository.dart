import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';

import 'beacon_room_repository.dart';
import '../database/tentura_db.dart';

@LazySingleton(as: BeaconRoomNotificationContextPort)
class BeaconRoomNotificationContextRepository
    implements BeaconRoomNotificationContextPort {
  const BeaconRoomNotificationContextRepository(
    this._room,
    this._db,
  );

  final BeaconRoomRepository _room;
  final TenturaDb _db;

  @override
  Future<BeaconNotificationContext> loadContextForBeacon(
    String beaconId,
  ) async {
    final author = await _room.beaconAuthorUserId(beaconId);
    final stewards = await _room.listStewardUserIds(beaconId);
    final admitted = await _room.listAdmittedUserIds(beaconId);
    final activeCoordination = await _usersWithActiveCoordination(beaconId);

    return BeaconNotificationContext(
      beaconAuthorId: author ?? '',
      admittedUserIds: admitted.toSet(),
      stewardUserIds: stewards.toSet(),
      usersWithActiveCoordination: activeCoordination,
    );
  }

  Future<Set<String>> _usersWithActiveCoordination(String beaconId) async {
    final rows = await (_db.select(_db.coordinationItems)
          ..where((t) => t.beaconId.equals(beaconId))
          ..where((t) => t.published.equals(true))
          ..where(
            (t) =>
                t.status.equals(coordinationItemStatusOpen) |
                t.status.equals(coordinationItemStatusAccepted),
          ))
        .get();
    final out = <String>{};
    for (final row in rows) {
      if (row.creatorId.isNotEmpty) {
        out.add(row.creatorId);
      }
      final target = row.targetPersonId;
      if (target != null && target.isNotEmpty) {
        out.add(target);
      }
      final accepted = row.acceptedById;
      if (accepted != null && accepted.isNotEmpty) {
        out.add(accepted);
      }
    }
    return out;
  }
}
