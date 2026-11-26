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

  Future<bool> hasPending({
    required String phantomId,
    required String senderId,
    required String beaconId,
  });

  Future<List<PhantomForwardClaim>> claimForMerge(
    OwnerGraphScope scope, {
    required String phantomId,
    required String senderId,
    required String mergeId,
    required String recipientId,
  });

  Future<bool> lockParentChain(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
  );

  /// Locks and reads a claim only if it belongs to the person's current merge.
  Future<PhantomForwardDelivery?> lockClaim(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
  );

  Future<void> resolve(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
    PhantomForwardResolution resolution,
  );
}
