import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../entity/phantom_pending_forward.dart';
import '../port/owner_graph_transaction_port.dart';
import '../port/phantom_pending_forward_repository_port.dart';
import '../port/post_lock_port.dart';
import 'forward_case.dart';
import 'transactional_attention_case.dart';

@lazySingleton
final class PhantomForwardDeliveryCase {
  const PhantomForwardDeliveryCase(
    this._ownerGraph,
    this._postLock,
    this._pendingForwards,
    this._attention,
    this._forward,
    this._logger,
  );

  final OwnerGraphTransactionPort _ownerGraph;
  final PostLockPort _postLock;
  final PhantomPendingForwardRepositoryPort _pendingForwards;
  final TransactionalAttentionCase _attention;
  final ForwardCase _forward;
  final Logger _logger;

  Future<void> sweep() async => deliver(await _pendingForwards.findClaims());

  Future<void> deliver(Iterable<PhantomForwardClaim> claims) async {
    for (final claim in claims) {
      try {
        await _deliverClaim(claim);
      } on Object catch (error, stackTrace) {
        // The transaction rolls back, preserving the claim for recovery.
        _logger.severe(
          'Could not deliver pending forward ${claim.id}',
          error,
          stackTrace,
        );
      }
    }
  }

  Future<void> _deliverClaim(PhantomForwardClaim claim) => _ownerGraph.run(
    {claim.senderId},
    claim.senderId,
    (scope) => _attention.runAction(
      actorUserId: claim.senderId,
      action: (transaction) async {
        await _postLock.lockForPostDelivery(
          claim.beaconId,
          senderId: claim.senderId,
        );
        final parentIsLive = await _pendingForwards.lockParentChain(
          scope,
          claim,
        );
        final target = await _pendingForwards.lockClaim(scope, claim);
        if (target == null) return;

        final resolution = switch (target) {
          PhantomForwardRecipientGone() => PhantomForwardLapsed.recipientGone,
          PhantomForwardDelivery() when !parentIsLive =>
            PhantomForwardLapsed.parentUnavailable,
          PhantomForwardDelivery() => await _forward.deliverPending(
            transaction: transaction,
            claim: claim,
            delivery: target,
          ),
        };
        await _pendingForwards.resolve(scope, claim, resolution);
        if (target is PhantomForwardDelivery &&
            resolution is PhantomForwardLapsed) {
          await _pendingForwards.recordJoinerCard(scope, claim, target);
        }
      },
    ),
  );
}
