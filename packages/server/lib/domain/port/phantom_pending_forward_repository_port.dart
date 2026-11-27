import '../entity/phantom_pending_forward.dart';
import 'owner_graph_transaction_port.dart';

abstract interface class PhantomPendingForwardRepositoryPort {
  /// Inserts a pending forward for a person owned by [senderId].
  /// Returns true only for a new row. Reuse [id] when retrying the same write.
  Future<bool> record(
    OwnerGraphScope scope, {
    required String id,
    required String phantomId,
    required String senderId,
    required String beaconId,
    required String? parentForwardEdgeId,
    required String note,
  });

  Future<PhantomPendingForward?> findById({
    required String senderId,
    required String id,
  });

  Future<
    List<
      ({
        String id,
        String phantomId,
        String displayName,
        PhantomPendingForwardState state,
      })
    >
  >
  listForRequest({
    required String senderId,
    required String beaconId,
  });

  Future<bool> hasPending({
    required String phantomId,
    required String senderId,
    required String beaconId,
  });

  /// Returns only invite claims for automatic delivery. Manual offers record
  /// owner attention in the same transaction and return an empty list.
  Future<List<PhantomForwardClaim>> assignForMerge(
    OwnerGraphScope scope, {
    required String phantomId,
    required String senderId,
    required String mergeId,
    required String recipientId,
    required PhantomForwardDeliverySource source,
  });

  Future<List<PhantomForwardClaim>> findClaims();

  Future<bool> lockParentChain(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
  );

  /// Locks the assigned row and checks whether its merge is still current.
  Future<PhantomForwardClaimTarget?> lockDelivery(
    OwnerGraphScope scope,
    PhantomForwardClaim claim, {
    required PhantomForwardDeliverySource source,
  });

  Future<void> resolve(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
    PhantomForwardResolution resolution, {
    PhantomForwardDeliverySource source =
        PhantomForwardDeliverySource.inviteClaim,
  });

  Future<void> recordJoinerCard(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
    PhantomForwardDelivery delivery,
  );
}
