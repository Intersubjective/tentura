import 'package:tentura_server/domain/entity/forward_edge_entity.dart';

abstract class ForwardEdgeRepositoryPort {
  Future<ForwardEdgeEntity?> fetchById(String edgeId);

  Future<bool> existsWithParent(String parentEdgeId);

  Future<void> cancel(String edgeId, String senderId);

  Future<void> updateNote(String edgeId, String senderId, String note);

  Future<void> markAsRead(String edgeId, String recipientId);

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

  /// Recursive ancestor closure for `BeaconHelpOffererForwardPathCase`.
  ///
  /// Seeds the chain on three predicate disjuncts and walks `parent_edge_id`
  /// upwards via a Postgres recursive CTE:
  /// * edges that delivered the beacon to [helpOffererId] (recipient_id),
  /// * edges where [viewerId] is the recipient,
  /// * edges where [viewerId] is the sender.
  ///
  /// Cancelled edges (`cancelled_at IS NOT NULL`) are excluded at every
  /// recursion level so a cancelled mid-chain hop is omitted, mirroring
  /// [fetchByBeaconId]. When the viewer is the beacon author or the
  /// help offerer themselves the viewer-OR clauses match nothing extra and
  /// the result reduces to the help offerer's ancestor closure.
  Future<List<ForwardEdgeEntity>> fetchHelpOffererPathChain({
    required String beaconId,
    required String helpOffererId,
    required String viewerId,
  });

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
