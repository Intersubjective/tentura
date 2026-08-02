import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/user_block/user_block_withdraw_reason.dart';
import 'package:tentura_server/utils/id.dart';

import '_use_case_base.dart';

const _blockRateLimitWindow = Duration(days: 1);

@Singleton(order: 2)
final class UserBlockCase extends UseCaseBase {
  UserBlockCase(
    this._unitOfWork,
    this._blocks,
    this._helpOffers,
    this._forwardEdges,
    this._contacts,
    this._users,
    this._beacons,
    this._coordination,
    this._inbox, {
    AttentionIntentCase? attentionIntents,
    AttentionDispatchPort? attentionDispatch,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attentionDispatch = attentionDispatch;

  final MutatingUnitOfWorkPort _unitOfWork;
  final UserBlockRepositoryPort _blocks;
  final HelpOfferRepositoryPort _helpOffers;
  final ForwardEdgeRepositoryPort _forwardEdges;
  final UserContactRepositoryPort _contacts;
  final UserRepositoryPort _users;
  final BeaconRepositoryPort _beacons;
  final CoordinationRepositoryPort _coordination;
  final InboxRepositoryPort _inbox;
  final AttentionIntentCase? _attentionIntents;
  final AttentionDispatchPort? _attentionDispatch;

  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) {
    if (blockerId == blockedId) {
      throw ArgumentError.value(blockedId, 'blockedId', 'cannot block yourself');
    }
    return _unitOfWork.run(
      actorUserId: blockerId,
      action: () async {
        await _requireUserExists(blockedId);
        await _enforceRateLimit(blockerId);
        await _blocks.block(
          blockerId: blockerId,
          blockedId: blockedId,
          cascadeMode: cascadeMode,
        );
        // Direct blocks only — cascade-derived rows must never trigger cleanup
        // (the user was never shown a warning for people they did not choose).
        await _cleanupDirectPair(blockerId, blockedId);
        await _blocks.applyWithdrawal(
          blockerId: blockerId,
          blockedId: blockedId,
        );
      },
    );
  }

  Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) =>
      _unitOfWork.run(
        actorUserId: blockerId,
        action: () => _blocks.unblock(
          blockerId: blockerId,
          blockedId: blockedId,
        ),
      );

  /// Promote an inherited block to a direct block (metadata only; no cleanup).
  Future<void> promoteToDirect({
    required String blockerId,
    required String blockedId,
  }) =>
      _unitOfWork.run(
        actorUserId: blockerId,
        action: () => _blocks.promoteToDirect(
          blockerId: blockerId,
          blockedId: blockedId,
        ),
      );

  Future<void> _requireUserExists(String userId) async {
    try {
      await _users.getById(userId);
    } on StateError {
      throw IdNotFoundException(id: userId);
    }
  }

  Future<void> _enforceRateLimit(String blockerId) async {
    final recent = await _blocks.countRecentByBlocker(
      blockerId: blockerId,
      window: _blockRateLimitWindow,
    );
    if (recent >= env.blockRateLimitPerDay) {
      logger.info('user block rate-limited for user $blockerId');
      throw const RateLimitedException(
        description: 'Too many blocks recently, please wait',
      );
    }
  }

  Future<void> _cleanupDirectPair(String blockerId, String blockedId) async {
    await _withdrawPendingHelpOffers(blockerId, blockedId);
    await _cancelForwardEdgesBetween(blockerId, blockedId);
    await _deleteContactsBetween(blockerId, blockedId);
  }

  Future<void> _withdrawPendingHelpOffers(
    String blockerId,
    String blockedId,
  ) async {
    await _withdrawOffersByOfferer(
      offererId: blockerId,
      beaconAuthorId: blockedId,
    );
    await _withdrawOffersByOfferer(
      offererId: blockedId,
      beaconAuthorId: blockerId,
    );
  }

  Future<void> _withdrawOffersByOfferer({
    required String offererId,
    required String beaconAuthorId,
  }) async {
    final offers = await _helpOffers.fetchByUserId(offererId);
    final authorByBeacon = <String, String>{};
    for (final offer in offers) {
      if (!offer.isActive) continue;
      final authorId = await _beaconAuthorId(
        offer.beaconId,
        cache: authorByBeacon,
      );
      if (authorId != beaconAuthorId) continue;
      final beaconId = offer.beaconId;
      await _coordination.deleteForCommit(
        beaconId: beaconId,
        userId: offererId,
      );
      await _helpOffers.withdraw(
        beaconId: beaconId,
        userId: offererId,
        withdrawReason: kBlockWithdrawReason,
      );
      final beaconAfter = await _beacons.getBeaconById(beaconId: beaconId);
      if (beaconAfter.status.isOpenFamily) {
        await _inbox.upsertWatchingForSender(
          senderId: offererId,
          beaconId: beaconId,
          touchForwardOrdering: false,
        );
        final intents = _attentionIntents;
        final dispatch = _attentionDispatch;
        if (intents != null && dispatch != null) {
          await dispatch.record(
            await intents.helpWithdrawn(
              beaconId: beaconId,
              withdrawerUserId: offererId,
              sourceEventKey: 'help_withdrawn:${generateId('A')}',
            ),
          );
        }
      } else {
        await _inbox.applyTombstoneAfterWithdraw(
          userId: offererId,
          beaconId: beaconId,
        );
      }
    }
  }

  Future<String> _beaconAuthorId(
    String beaconId, {
    required Map<String, String> cache,
  }) async {
    final cached = cache[beaconId];
    if (cached != null) return cached;
    final authorId = (await _beacons.getBeaconById(beaconId: beaconId))
        .author
        .id;
    cache[beaconId] = authorId;
    return authorId;
  }

  Future<void> _cancelForwardEdgesBetween(
    String blockerId,
    String blockedId,
  ) async {
    await _cancelEdgesFromSenderToRecipient(
      senderId: blockerId,
      recipientId: blockedId,
    );
    await _cancelEdgesFromSenderToRecipient(
      senderId: blockedId,
      recipientId: blockerId,
    );
  }

  Future<void> _cancelEdgesFromSenderToRecipient({
    required String senderId,
    required String recipientId,
  }) async {
    final inbound = await _forwardEdges.fetchByRecipientId(recipientId);
    for (final edge in inbound) {
      if (edge.senderId != senderId || edge.cancelledAt != null) continue;
      await _forwardEdges.cancel(edge.id, senderId);
      await _inbox.markForwardCancelledForRecipient(
        beaconId: edge.beaconId,
        recipientId: edge.recipientId,
      );
    }
  }

  Future<void> _deleteContactsBetween(
    String blockerId,
    String blockedId,
  ) async {
    await _contacts.delete(viewerId: blockerId, subjectId: blockedId);
    await _contacts.delete(viewerId: blockedId, subjectId: blockerId);
  }
}
