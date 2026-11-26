import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../entity/phantom_pending_forward.dart';
import '../exception.dart';
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

  Future<bool> confirm({
    required String senderId,
    required String id,
    String? mergeId,
  }) async {
    await _settle(
      senderId,
      () async {
        final offer = await _pendingForwards.findById(
          senderId: senderId,
          id: id,
        );
        if (offer == null ||
            offer.state != PhantomPendingForwardState.offered ||
            (mergeId != null && offer.mergeId != mergeId)) {
          throw IdNotFoundException(id: id);
        }
        return (
          id: id,
          senderId: senderId,
          beaconId: offer.beaconId,
          parentForwardEdgeId: offer.parentForwardEdgeId,
          mergeId: offer.mergeId,
        );
      },
      source: PhantomForwardDeliverySource.manualOffer,
    );
    return true;
  }

  Future<void> _deliverClaim(PhantomForwardClaim claim) => _settle(
    claim.senderId,
    () => claim,
    source: PhantomForwardDeliverySource.inviteClaim,
  );

  Future<void> _settle(
    String senderId,
    FutureOr<PhantomForwardClaim> Function() readClaim, {
    required PhantomForwardDeliverySource source,
  }) => _ownerGraph.run(
    {senderId},
    senderId,
    (scope) => _attention.runAction(
      actorUserId: senderId,
      action: (transaction) async {
        final claim = await readClaim();
        await _postLock.lockForPostDelivery(
          claim.beaconId,
          senderId: senderId,
        );
        final parentIsLive = await _pendingForwards.lockParentChain(
          scope,
          claim,
        );
        final target = await _pendingForwards.lockDelivery(
          scope,
          claim,
          source: source,
        );
        final confirming = source == PhantomForwardDeliverySource.manualOffer;
        if (confirming && target is! PhantomForwardDelivery) {
          throw IdNotFoundException(id: claim.id);
        }
        if (target == null) return;

        final resolution = switch (target) {
          PhantomForwardRecipientGone() => PhantomForwardLapsed.recipientGone,
          PhantomForwardDelivery() when !parentIsLive =>
            PhantomForwardLapsed.parentUnavailable,
          PhantomForwardDelivery() => await _forward.deliverPending(
            transaction: transaction,
            claim: claim,
            delivery: target,
            source: source,
          ),
        };
        if (confirming && resolution is PhantomForwardLapsed) {
          throw UnauthorizedException(
            description: resolution == PhantomForwardLapsed.parentUnavailable
                ? 'Invalid parent forward edge for sender'
                : 'Recipient is not available for forwarding',
          );
        }
        await _pendingForwards.resolve(
          scope,
          claim,
          resolution,
          source: source,
        );
        if (target is PhantomForwardDelivery &&
            resolution is PhantomForwardLapsed) {
          await _pendingForwards.recordJoinerCard(scope, claim, target);
        }
      },
    ),
  );
}
