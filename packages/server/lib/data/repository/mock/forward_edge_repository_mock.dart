import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/forward_batch_create_result.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';

@Injectable(
  as: ForwardEdgeRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ForwardEdgeRepositoryMock implements ForwardEdgeRepositoryPort {
  @override
  Future<ForwardEdgeEntity?> fetchById(String edgeId) => Future.value();

  @override
  Future<bool> existsWithParent(String parentEdgeId) => Future.value(false);

  @override
  Future<void> cancel(String edgeId, String senderId) => Future.value();

  @override
  Future<void> updateNote(String edgeId, String senderId, String note) =>
      Future.value();

  @override
  Future<void> markAsRead(String edgeId, String recipientId) => Future.value();

  @override
  Future<void> create({
    required String beaconId,
    required String senderId,
    required String recipientId,
    required String note,
    String? context,
    String? parentEdgeId,
    String? batchId,
  }) => Future.value();

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
  }) => Future.value(
    const ForwardBatchCreateResult(
      createdEdges: [],
      availabilitySkippedRecipientIds: [],
    ),
  );

  @override
  Future<List<ForwardEdgeEntity>> fetchByBeaconId(String beaconId) =>
      Future.value(const []);

  @override
  Future<List<ForwardEdgeEntity>> fetchHelpOffererPathChain({
    required String beaconId,
    required String helpOffererId,
    required String viewerId,
  }) => Future.value(const []);

  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) => Future.value(const []);

  @override
  Future<List<String>> fetchDistinctSenderIdsByBeaconId(String beaconId) =>
      Future.value(const []);

  @override
  Future<bool> isDirectAuthorForward({
    required String beaconId,
    required String authorId,
    required String userId,
  }) => Future.value(false);

  @override
  Future<List<ForwardEdgeEntity>> fetchActiveInboundEdges({
    required String beaconId,
    required String recipientId,
  }) => Future.value(const []);

  @override
  Future<List<ForwardEdgeEntity>> lockActiveInboundEdges({
    required String beaconId,
    required String recipientId,
  }) => Future.value(const []);

  @override
  Future<List<ForwardEdgeEntity>> fetchAllByBeaconId(String beaconId) =>
      Future.value(const []);

  @override
  Future<int> countPriorOutgoingBatches({
    required String beaconId,
    required String senderId,
    required String batchId,
  }) => Future.value(0);

  @override
  Future<ForwardEdgeEntity?> findActiveEdge({
    required String beaconId,
    required String senderId,
    required String recipientId,
  }) => Future.value();

  @override
  Future<void> createForInviteAccept({
    required String beaconId,
    required String senderId,
    required String recipientId,
    String? parentEdgeId,
  }) => Future.value();

  @override
  Future<Set<String>> fetchRecipientIdsForwardedBySenderWithinDays({
    required String senderId,
    required int withinDays,
  }) => Future.value(const {});
}
