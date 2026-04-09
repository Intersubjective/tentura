import 'package:drift_postgres/drift_postgres.dart';
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

  /// User ids watching this beacon (`status == 1`), any context.
  Future<List<String>> fetchWatchingUserIdsByBeacon(String beaconId) =>
      _database.managers.inboxItems
          .filter(
            (e) => e.beaconId.id(beaconId) & e.status.equals(1),
          )
          .get()
          .then((rows) => rows.map((r) => r.userId).toList());

  /// After forward: sender moves to watching when they have no active commitment.
  /// Preserves existing `forward_count` and note preview on conflict.
  Future<void> upsertWatchingForSender({
    required String senderId,
    required String beaconId,
    String? context,
  }) async {
    final now = PgDateTime(DateTime.timestamp());
    await _database.into(_database.inboxItems).insert(
      InboxItemsCompanion.insert(
        userId: senderId,
        beaconId: beaconId,
        context: Value(context),
        status: const Value(1),
        forwardCount: const Value(0),
        latestForwardAt: Value(now),
        latestNotePreview: const Value(''),
        rejectionMessage: const Value(''),
      ),
      onConflict: DoUpdate(
        (_) => InboxItemsCompanion(
          status: const Value(1),
          rejectionMessage: const Value(''),
          latestForwardAt: Value(now),
          context: context != null ? Value(context) : const Value.absent(),
        ),
      ),
    );
  }

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
