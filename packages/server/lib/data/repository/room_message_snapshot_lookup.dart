import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/room_message_snapshot.dart';
import 'package:tentura_server/domain/port/room_message_snapshot_lookup_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: RoomMessageSnapshotLookupPort)
final class RoomMessageSnapshotLookup
    implements RoomMessageSnapshotLookupPort {
  RoomMessageSnapshotLookup(this._database);

  final TenturaDb _database;

  @override
  Future<RoomMessageSnapshot?> findEligibleInsert({
    required String messageId,
    required String beaconId,
  }) async {
    final row = await (_database.select(_database.beaconRoomMessages)..where(
      (m) => m.id.equals(messageId) & m.beaconId.equals(beaconId),
    )).getSingleOrNull();
    if (row == null || row.body.trim().isEmpty) {
      return null;
    }
    if (row.linkedNextMoveId != null ||
        row.linkedFactCardId != null ||
        row.linkedPollingId != null ||
        row.linkedItemId != null ||
        row.linkedEventKind != null ||
        row.semanticMarker != null ||
        row.systemPayload != null) {
      return null;
    }

    final attachmentRows = await (_database.select(
      _database.beaconRoomMessageAttachments,
    )..where((a) => a.messageId.equals(messageId))).get();
    if (attachmentRows.isNotEmpty) {
      return null;
    }

    return RoomMessageSnapshot(
      id: row.id,
      beaconId: row.beaconId,
      authorId: row.authorId,
      body: row.body,
      createdAt: row.createdAt.dateTime,
      editedAt: row.editedAt?.dateTime,
      mentions: List<String>.from(row.mentions),
      threadItemId: row.threadItemId,
    );
  }
}
