import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

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
            ? (e) => e.userId.id(userId) & e.isHidden.equals(false)
            : (e) =>
                  e.userId.id(userId) &
                  e.isHidden.equals(false) &
                  e.context.equals(context),
      )
      .orderBy((e) => e.latestForwardAt.desc())
      .get(limit: limit, offset: offset)
      .then((rows) => rows.map(_toEntity).toList());

  Future<void> setHidden({
    required String userId,
    required String beaconId,
    required bool isHidden,
  }) => _database.managers.inboxItems
      .filter(
        (e) => e.userId.id(userId) & e.beaconId.id(beaconId),
      )
      .update((o) => o(isHidden: Value(isHidden)));

  Future<void> setWatching({
    required String userId,
    required String beaconId,
    required bool isWatching,
  }) => _database.managers.inboxItems
      .filter(
        (e) => e.userId.id(userId) & e.beaconId.id(beaconId),
      )
      .update((o) => o(isWatching: Value(isWatching)));

  static InboxItemEntity _toEntity(InboxItem row) =>
      InboxItemEntity(
        userId: row.userId,
        beaconId: row.beaconId,
        context: row.context,
        forwardCount: row.forwardCount,
        latestForwardAt: (row.latestForwardAt as PgDateTime).dateTime,
        latestNotePreview: row.latestNotePreview,
        isHidden: row.isHidden,
        isWatching: row.isWatching,
      );
}
