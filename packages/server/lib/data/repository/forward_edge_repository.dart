import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: ForwardEdgeRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class ForwardEdgeRepository implements ForwardEdgeRepositoryPort {
  const ForwardEdgeRepository(this._database);

  final TenturaDb _database;

  @override
  Future<ForwardEdgeEntity?> fetchById(String edgeId) =>
      _database.managers.beaconForwardEdges
          .filter((e) => e.id.equals(edgeId))
          .getSingleOrNull()
          .then((row) => row == null ? null : _toEntity(row));

  @override
  Future<bool> existsWithParent(String parentEdgeId) =>
      _database.managers.beaconForwardEdges
          .filter((e) => e.parentEdgeId.id(parentEdgeId))
          .exists();

  @override
  Future<void> cancel(String edgeId, String senderId) =>
      _database.managers.beaconForwardEdges
          .filter(
            (e) =>
                e.id.equals(edgeId) &
                e.senderId.id(senderId) &
                e.cancelledAt.isNull(),
          )
          .update(
            (o) => o(cancelledAt: Value(PgDateTime(DateTime.timestamp()))),
          );

  @override
  Future<void> updateNote(String edgeId, String senderId, String note) =>
      _database.managers.beaconForwardEdges
          .filter(
            (e) =>
                e.id.equals(edgeId) &
                e.senderId.id(senderId) &
                e.cancelledAt.isNull(),
          )
          .update((o) => o(note: Value(note)));

  @override
  Future<void> markAsRead(String edgeId, String recipientId) =>
      _database.managers.beaconForwardEdges
          .filter(
            (e) =>
                e.id.equals(edgeId) &
                e.recipientId.id(recipientId) &
                e.recipientReadAt.isNull(),
          )
          .update(
            (o) => o(
              recipientReadAt: Value(PgDateTime(DateTime.timestamp())),
            ),
          );

  @override
  Future<void> create({
    required String beaconId,
    required String senderId,
    required String recipientId,
    required String note,
    String? context,
    String? parentEdgeId,
    String? batchId,
  }) => _database.withMutatingUser(senderId, () async {
    await _database.managers.beaconForwardEdges.create(
      (o) => o(
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
        note: Value(note),
        context: Value(context),
        parentEdgeId: Value(parentEdgeId),
        batchId: Value(batchId),
      ),
    );
  });

  /// Inserts one batch of forward edges atomically.
  ///
  /// [onAfterEdgesInserted] runs inside the same transaction (e.g. sender
  /// inbox → watching when not committed).
  @override
  Future<void> createBatch({
    required String beaconId,
    required String senderId,
    required List<String> recipientIds,
    required String batchId,
    required String Function(String recipientId) noteForRecipient,
    String? context,
    String? parentEdgeId,
    Future<void> Function()? onAfterEdgesInserted,
  }) => _database.withMutatingUser(senderId, () async {
    for (final recipientId in recipientIds) {
      await _database.managers.beaconForwardEdges.create(
        (o) => o(
          beaconId: beaconId,
          senderId: senderId,
          recipientId: recipientId,
          note: Value(noteForRecipient(recipientId)),
          context: Value(context),
          parentEdgeId: Value(parentEdgeId),
          batchId: Value(batchId),
        ),
      );
    }
    await onAfterEdgesInserted?.call();
  });

  @override
  Future<List<ForwardEdgeEntity>> fetchByBeaconId(String beaconId) =>
      _database.managers.beaconForwardEdges
          .filter((e) => e.beaconId.id(beaconId) & e.cancelledAt.isNull())
          .orderBy((e) => e.createdAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<ForwardEdgeEntity>> fetchCommitterPathChain({
    required String beaconId,
    required String committerId,
    required String viewerId,
  }) async {
    // Recursive CTE returns just the edge ids that participate in either the
    // committer's or the viewer's ancestor closure for this beacon. Reading
    // the full row via [managers.beaconForwardEdges] keeps the timestamptz
    // mapping consistent with [fetchByBeaconId] (PgDateTime -> DateTime).
    final idRows = await _database
        .customSelect(
          r'''
          WITH RECURSIVE chain AS (
            SELECT e.id, e.parent_edge_id
              FROM beacon_forward_edge e
             WHERE e.beacon_id    = $1
               AND e.cancelled_at IS NULL
               AND ( e.recipient_id = $2
                     OR e.recipient_id = $3
                     OR e.sender_id    = $3 )
            UNION
            SELECT p.id, p.parent_edge_id
              FROM beacon_forward_edge p
              JOIN chain c ON p.id = c.parent_edge_id
             WHERE p.cancelled_at IS NULL
          )
          SELECT id FROM chain
          ''',
          variables: [
            Variable.withString(beaconId),
            Variable.withString(committerId),
            Variable.withString(viewerId),
          ],
        )
        .get();
    final ids = idRows.map((r) => r.read<String>('id')).toList();
    if (ids.isEmpty) return const [];
    return _database.managers.beaconForwardEdges
        .filter((e) => e.id.isIn(ids))
        .orderBy((e) => e.createdAt.asc())
        .get()
        .then((rows) => rows.map(_toEntity).toList());
  }

  /// Distinct users who sent at least one forward edge for this beacon.
  @override
  Future<List<String>> fetchDistinctSenderIdsByBeaconId(String beaconId) =>
      _database.managers.beaconForwardEdges
          .filter((e) => e.beaconId.id(beaconId) & e.cancelledAt.isNull())
          .get()
          .then(
            (rows) => rows.map((r) => r.senderId).toSet().toList(),
          );

  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) => _database.managers.beaconForwardEdges
      .filter(
        context == null
            ? (e) => e.recipientId.id(recipientId) & e.cancelledAt.isNull()
            : (e) =>
                  e.recipientId.id(recipientId) &
                  e.context.equals(context) &
                  e.cancelledAt.isNull(),
      )
      .orderBy((e) => e.createdAt.desc())
      .get()
      .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<bool> isDirectAuthorForward({
    required String beaconId,
    required String authorId,
    required String userId,
  }) => _database.managers.beaconForwardEdges
      .filter(
        (e) =>
            e.beaconId.id(beaconId) &
            e.senderId.id(authorId) &
            e.recipientId.id(userId) &
            e.cancelledAt.isNull(),
      )
      .exists();

  static ForwardEdgeEntity _toEntity(BeaconForwardEdge row) =>
      ForwardEdgeEntity(
        id: row.id,
        beaconId: row.beaconId,
        senderId: row.senderId,
        recipientId: row.recipientId,
        note: row.note,
        context: row.context,
        parentEdgeId: row.parentEdgeId,
        batchId: row.batchId,
        createdAt: row.createdAt.dateTime,
        recipientRejected: row.recipientRejected,
        recipientRejectionMessage: row.recipientRejectionMessage,
        cancelledAt: row.cancelledAt?.dateTime,
        recipientReadAt: row.recipientReadAt?.dateTime,
      );
}
