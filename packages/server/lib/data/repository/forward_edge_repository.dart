import 'package:drift/drift.dart';
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
    await _insertActiveEdge(
      beaconId: beaconId,
      senderId: senderId,
      recipientId: recipientId,
      note: note,
      context: context,
      parentEdgeId: parentEdgeId,
      batchId: batchId,
    );
  });

  /// Inserts one batch of forward edges atomically.
  ///
  /// [onAfterEdgesInserted] runs inside the same transaction when at least one
  /// edge is inserted (e.g. sender inbox → watching when not committed).
  ///
  /// Returns recipient ids for which a new active edge was inserted.
  @override
  Future<List<String>> createBatch({
    required String beaconId,
    required String senderId,
    required List<String> recipientIds,
    required String batchId,
    required String Function(String recipientId) noteForRecipient,
    String? context,
    String? parentEdgeId,
    Future<void> Function()? onAfterEdgesInserted,
  }) => _database.withMutatingUser(senderId, () async {
    final inserted = <String>[];
    for (final recipientId in recipientIds) {
      if (await findActiveEdge(
            beaconId: beaconId,
            senderId: senderId,
            recipientId: recipientId,
          ) !=
          null) {
        continue;
      }
      await _insertActiveEdge(
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
        note: noteForRecipient(recipientId),
        context: context,
        parentEdgeId: parentEdgeId,
        batchId: batchId,
      );
      final edge = await findActiveEdge(
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
      );
      if (edge?.batchId == batchId) {
        inserted.add(recipientId);
      }
    }
    if (inserted.isNotEmpty) {
      await onAfterEdgesInserted?.call();
    }
    return inserted;
  });

  @override
  Future<List<ForwardEdgeEntity>> fetchByBeaconId(String beaconId) =>
      _database.managers.beaconForwardEdges
          .filter((e) => e.beaconId.id(beaconId) & e.cancelledAt.isNull())
          .orderBy((e) => e.createdAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<ForwardEdgeEntity>> fetchHelpOffererPathChain({
    required String beaconId,
    required String helpOffererId,
    required String viewerId,
  }) async {
    // Recursive CTE returns just the edge ids that participate in either the
    // help offerer's or the viewer's ancestor closure for this beacon. Reading
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
            Variable.withString(helpOffererId),
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

  @override
  Future<List<ForwardEdgeEntity>> fetchActiveInboundEdges({
    required String beaconId,
    required String recipientId,
  }) =>
      _database.managers.beaconForwardEdges
          .filter(
            (e) =>
                e.beaconId.id(beaconId) &
                e.recipientId.id(recipientId) &
                e.cancelledAt.isNull(),
          )
          .orderBy((e) => e.createdAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<ForwardEdgeEntity>> lockActiveInboundEdges({
    required String beaconId,
    required String recipientId,
  }) async {
    final idRows = await _database
        .customSelect(
          r'''
SELECT id
FROM beacon_forward_edge
WHERE beacon_id = $1
  AND recipient_id = $2
  AND cancelled_at IS NULL
FOR SHARE
''',
          variables: [
            Variable.withString(beaconId),
            Variable.withString(recipientId),
          ],
        )
        .get();
    if (idRows.isEmpty) return const [];
    final ids = idRows.map((r) => r.read<String>('id')).toList();
    return _database.managers.beaconForwardEdges
        .filter((e) => e.id.isIn(ids))
        .orderBy((e) => e.createdAt.desc())
        .get()
        .then((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<List<ForwardEdgeEntity>> fetchAllByBeaconId(String beaconId) =>
      _database.managers.beaconForwardEdges
          .filter((e) => e.beaconId.id(beaconId))
          .orderBy((e) => e.createdAt.asc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<int> countPriorOutgoingBatches({
    required String beaconId,
    required String senderId,
    required String batchId,
  }) =>
      _database
          .customSelect(
            r'''
SELECT count(DISTINCT batch_id)::int AS c
FROM beacon_forward_edge
WHERE beacon_id = $1
  AND sender_id = $2
  AND batch_id IS NOT NULL
  AND batch_id <> $3
''',
            variables: [
              Variable.withString(beaconId),
              Variable.withString(senderId),
              Variable.withString(batchId),
            ],
          )
          .map((r) => r.read<int>('c'))
          .getSingle();

  @override
  Future<ForwardEdgeEntity?> findActiveEdge({
    required String beaconId,
    required String senderId,
    required String recipientId,
  }) =>
      _database.managers.beaconForwardEdges
          .filter(
            (e) =>
                e.beaconId.id(beaconId) &
                e.senderId.id(senderId) &
                e.recipientId.id(recipientId) &
                e.cancelledAt.isNull(),
          )
          .getSingleOrNull()
          .then((row) => row == null ? null : _toEntity(row));

  @override
  Future<void> createForInviteAccept({
    required String beaconId,
    required String senderId,
    required String recipientId,
    String? parentEdgeId,
  }) =>
      _database.withMutatingUser(recipientId, () async {
        await _insertActiveEdge(
          beaconId: beaconId,
          senderId: senderId,
          recipientId: recipientId,
          note: '',
          parentEdgeId: parentEdgeId,
        );
      });

  Future<void> _insertActiveEdge({
    required String beaconId,
    required String senderId,
    required String recipientId,
    required String note,
    String? context,
    String? parentEdgeId,
    String? batchId,
  }) =>
      _database.into(_database.beaconForwardEdges).insert(
        BeaconForwardEdgesCompanion.insert(
          beaconId: beaconId,
          senderId: senderId,
          recipientId: recipientId,
          note: Value(note),
          context: Value(context),
          parentEdgeId: Value(parentEdgeId),
          batchId: Value(batchId),
        ),
        onConflict: DoNothing(),
      );

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
