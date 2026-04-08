import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/inbox_item_entity.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class InboxRepository {
  const InboxRepository(this._database);

  final TenturaDb _database;

  Future<List<InboxItemEntity>> fetchByUserId(
    String userId, {
    String? context,
    int limit = 50,
    int offset = 0,
  }) => _database.managers.inboxItems
      .filter(
        context == null
            ? (e) => e.userId.id(userId)
            : (e) => e.userId.id(userId) & e.context.equals(context),
      )
      .orderBy((e) => e.latestForwardAt.desc())
      .get(limit: limit, offset: offset)
      .then((rows) => rows.map(_toEntity).toList());

  /// User ids who rejected this beacon (inbox_item.status == 2), any context.
  Future<List<String>> fetchRejectedUserIdsByBeacon(String beaconId) =>
      _database.managers.inboxItems
          .filter(
            (e) => e.beaconId.id(beaconId) & e.status.equals(2),
          )
          .get()
          .then((rows) => rows.map((r) => r.userId).toList());

  Future<void> setStatus({
    required String userId,
    required String beaconId,
    required int status,
    required String rejectionMessage,
  }) => _database.managers.inboxItems
      .filter(
        (e) => e.userId.id(userId) & e.beaconId.id(beaconId),
      )
      .update(
        (o) => o(
          status: Value(status),
          rejectionMessage: Value(rejectionMessage),
        ),
      );

  static InboxItemEntity _toEntity(InboxItem row) =>
      InboxItemEntity(
        userId: row.userId,
        beaconId: row.beaconId,
        context: row.context,
        forwardCount: row.forwardCount,
        latestForwardAt: row.latestForwardAt.dateTime,
        latestNotePreview: row.latestNotePreview,
        status: row.status,
        rejectionMessage: row.rejectionMessage,
      );
}
