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
          .filter((e) => e.beaconId.id(beaconId))
          .orderBy((e) => e.createdAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  /// Distinct users who sent at least one forward edge for this beacon.
  @override
  Future<List<String>> fetchDistinctSenderIdsByBeaconId(String beaconId) =>
      _database.managers.beaconForwardEdges
          .filter((e) => e.beaconId.id(beaconId))
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
            ? (e) => e.recipientId.id(recipientId)
            : (e) =>
                  e.recipientId.id(recipientId) &
                  e.context.equals(context),
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
            e.senderId.equals(authorId) &
            e.recipientId.equals(userId),
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
      );
}
