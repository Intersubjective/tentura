import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/forward_edge_entity.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class ForwardEdgeRepository {
  const ForwardEdgeRepository(this._database);

  final TenturaDb _database;

  Future<void> create({
    required String beaconId,
    required String senderId,
    required String recipientId,
    required String note,
    String? context,
    String? parentEdgeId,
    String? batchId,
  }) => _database.managers.beaconForwardEdges.create(
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

  Future<void> createBatch({
    required String beaconId,
    required String senderId,
    required List<String> recipientIds,
    required String batchId,
    required String Function(String recipientId) noteForRecipient,
    String? context,
    String? parentEdgeId,
  }) => _database.transaction(() async {
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
  });

  Future<List<ForwardEdgeEntity>> fetchByBeaconId(String beaconId) =>
      _database.managers.beaconForwardEdges
          .filter((e) => e.beaconId.id(beaconId))
          .orderBy((e) => e.createdAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) => _database.managers.beaconForwardEdges
      .filter(
        context == null
            ? (e) => e.recipientId.id(recipientId)
            : (e) =>
                  e.recipientId.id(recipientId) &
                  e.context.equals(context),
      )
      .orderBy((e) => e.createdAt.desc())
      .get()
      .then((rows) => rows.map(_toEntity).toList());

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
        createdAt: (row.createdAt as PgDateTime).dateTime,
        recipientRejected: row.recipientRejected,
        recipientRejectionMessage: row.recipientRejectionMessage,
      );
}
