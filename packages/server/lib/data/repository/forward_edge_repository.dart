import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/forward_batch_create_result.dart';
import 'package:tentura_server/domain/entity/forward_edge_created.dart';
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
  /// Recipient ids are deduplicated in first-request order. Per-recipient
  /// availability advisory locks are taken in sorted id order before inserts.
  /// Each insert is conditional on the recipient not being availability-paused
  /// (`resume_on` strictly after today's UTC calendar date). Active-edge dedup
  /// is separate and is not reported as an availability skip.
  ///
  /// [onAfterEdgesInserted] runs inside the same transaction when at least one
  /// edge is inserted (e.g. sender inbox → watching when not committed).
  @override
  Future<ForwardBatchCreateResult> createBatch({
    required String beaconId,
    required String senderId,
    required List<String> recipientIds,
    required String batchId,
    required String Function(String recipientId) noteForRecipient,
    String? context,
    String? parentEdgeId,
    Future<void> Function()? onAfterEdgesInserted,
  }) => _database.withMutatingUser(senderId, () async {
    final seen = <String>{};
    final orderedUniqueRecipients = <String>[];
    for (final recipientId in recipientIds) {
      if (seen.add(recipientId)) {
        orderedUniqueRecipients.add(recipientId);
      }
    }

    final lockOrder = orderedUniqueRecipients.toList()..sort();
    for (final recipientId in lockOrder) {
      await _acquireAvailabilityLock(recipientId);
    }

    final inserted = <ForwardEdgeCreated>[];
    final availabilitySkipped = <String>[];

    for (final recipientId in orderedUniqueRecipients) {
      final edgeId = ForwardEdgeEntity.newId;
      final note = noteForRecipient(recipientId);
      final didInsert = await _insertActiveEdgeIfAvailable(
        edgeId: edgeId,
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
        note: note,
        context: context,
        parentEdgeId: parentEdgeId,
        batchId: batchId,
      );
      if (didInsert) {
        inserted.add(
          ForwardEdgeCreated(edgeId: edgeId, recipientId: recipientId),
        );
        continue;
      }

      final existing = await findActiveEdge(
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
      );
      if (existing == null) {
        availabilitySkipped.add(recipientId);
      }
    }

    if (inserted.isNotEmpty) {
      await onAfterEdgesInserted?.call();
    }
    return ForwardBatchCreateResult(
      createdEdges: inserted,
      availabilitySkippedRecipientIds: availabilitySkipped,
    );
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

  @override
  Future<Set<String>> fetchRecipientIdsForwardedBySenderWithinDays({
    required String senderId,
    required int withinDays,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT DISTINCT recipient_id
FROM beacon_forward_edge
WHERE sender_id = $1
  AND created_at >= now() - make_interval(days => $2::integer)
''',
          variables: [
            Variable.withString(senderId),
            Variable<int>(withinDays),
          ],
        )
        .get();
    return rows.map((r) => r.read<String>('recipient_id')).toSet();
  }

  Future<bool> _insertActiveEdgeIfAvailable({
    required String edgeId,
    required String beaconId,
    required String senderId,
    required String recipientId,
    required String note,
    String? context,
    String? parentEdgeId,
    String? batchId,
  }) async {
    final inserted = await _database.customInsert(
      r'''
INSERT INTO public.beacon_forward_edge (
  id,
  beacon_id,
  sender_id,
  recipient_id,
  note,
  context,
  parent_edge_id,
  batch_id
)
SELECT
  $1,
  $2,
  $3,
  $4,
  $5,
  $6,
  $7,
  $8
WHERE NOT EXISTS (
  SELECT 1
  FROM public.beacon_forward_edge e
  WHERE e.beacon_id = $2
    AND e.sender_id = $3
    AND e.recipient_id = $4
    AND e.cancelled_at IS NULL
)
AND NOT EXISTS (
  SELECT 1
  FROM public.user_availability ua
  WHERE ua.user_id = $4
    AND ua.resume_on > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date
)
''',
      variables: [
        Variable.withString(edgeId),
        Variable.withString(beaconId),
        Variable.withString(senderId),
        Variable.withString(recipientId),
        Variable.withString(note),
        Variable(context),
        Variable(parentEdgeId),
        Variable(batchId),
      ],
      updates: {_database.beaconForwardEdges},
    );
    return inserted > 0;
  }

  Future<void> _acquireAvailabilityLock(String userId) =>
      _database.customStatement(
        r"SELECT pg_advisory_xact_lock(hashtextextended('user_availability:' || $1, 4242))",
        [userId],
      );

  Future<void> _insertActiveEdge({
    String? edgeId,
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
          id: edgeId == null ? const Value.absent() : Value(edgeId),
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
