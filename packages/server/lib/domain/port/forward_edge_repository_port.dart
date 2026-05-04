import 'package:tentura_server/domain/entity/forward_edge_entity.dart';

abstract class ForwardEdgeRepositoryPort {
  Future<void> create({
    required String beaconId,
    required String senderId,
    required String recipientId,
    required String note,
    String? context,
    String? parentEdgeId,
    String? batchId,
  });

  Future<void> createBatch({
    required String beaconId,
    required String senderId,
    required List<String> recipientIds,
    required String batchId,
    required String Function(String recipientId) noteForRecipient,
    String? context,
    String? parentEdgeId,
    Future<void> Function()? onAfterEdgesInserted,
  });

  Future<List<ForwardEdgeEntity>> fetchByBeaconId(String beaconId);

  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  });

  Future<List<String>> fetchDistinctSenderIdsByBeaconId(String beaconId);

  /// Returns true when [authorId] has forwarded [beaconId] directly to [userId].
  Future<bool> isDirectAuthorForward({
    required String beaconId,
    required String authorId,
    required String userId,
  });
}
