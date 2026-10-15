import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/author_invite_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
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
    this._commitmentRepository,
    this._inbox,
    this._capabilityEvidence,
    this._hierarchyRepository, {
    required TrustLedgerPort trustLedger,
    AttentionIntentCase? attentionIntents,
    AttentionDispatchPort? attentionDispatch,
    WitnessWindowPort? witnessWindow,
    ClosureCase? closureCase,
    AuthorInvitePort? authorInvites,
    AttentionSystemSettlementPort? attentionSystemSettlement,
    BeaconRoomRepositoryPort? roomRepository,
    TransactionalAttentionCase? attention,
    BeaconPlanCase? beaconPlan,
    required super.env,
    required super.logger,
  }) : _trustLedger = trustLedger,
       _attentionIntents = attentionIntents,
       _attentionDispatch = attentionDispatch,
       _witnessWindow = witnessWindow,
       _closureCase = closureCase,
       _authorInvites = authorInvites,
       _attentionSystemSettlement = attentionSystemSettlement,
       _roomRepository = roomRepository,
       _attention = attention,
       _beaconPlan = beaconPlan;

  final MutatingUnitOfWorkPort _unitOfWork;
  final UserBlockRepositoryPort _blocks;
  final HelpOfferRepositoryPort _helpOffers;
  final ForwardEdgeRepositoryPort _forwardEdges;
  final UserContactRepositoryPort _contacts;
  final UserRepositoryPort _users;
  final BeaconRepositoryPort _beacons;
  final CommitmentRepositoryPort _commitmentRepository;
  final InboxRepositoryPort _inbox;
  final CapabilityEvidencePort _capabilityEvidence;
  final BeaconHierarchyRepositoryPort _hierarchyRepository;
  final TrustLedgerPort _trustLedger;
  final AttentionIntentCase? _attentionIntents;
  final AttentionDispatchPort? _attentionDispatch;
  final WitnessWindowPort? _witnessWindow;
  final ClosureCase? _closureCase;
  final AuthorInvitePort? _authorInvites;
  final AttentionSystemSettlementPort? _attentionSystemSettlement;
  final BeaconRoomRepositoryPort? _roomRepository;
  final TransactionalAttentionCase? _attention;
  final BeaconPlanCase? _beaconPlan;

  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) {
    if (blockerId == blockedId) {
      throw ArgumentError.value(
        blockedId,
        'blockedId',
        'cannot block yourself',
      );
    }
    Future<void> action(AttentionTransaction? transaction) async {
      await _hierarchyRepository.lockMutationScope();
      await _requireUserExists(blockedId);
      await _enforceRateLimit(blockerId);
      await _blocks.block(
        blockerId: blockerId,
        blockedId: blockedId,
        cascadeMode: cascadeMode,
      );
      // Direct blocks only — cascade-derived rows must never trigger cleanup
      // (the user was never shown a warning for people they did not choose).
      await _cleanupDirectPair(blockerId, blockedId, transaction);
      await _blocks.applyWithdrawal(
        blockerId: blockerId,
        blockedId: blockedId,
      );
      await _invalidateWitnessWindows(blockerId, blockedId);
      await _trustLedger.project([(blockerId, blockedId)]);
    }

    // The same unit of work either way; the attention runner only adds the
    // transaction handle that plan cleanup records its revision through.
    final attention = _attention;
    return attention != null
        ? attention.runAction(actorUserId: blockerId, action: action)
        : _unitOfWork.run(actorUserId: blockerId, action: () => action(null));
  }

  Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) => _unitOfWork.run(
    actorUserId: blockerId,
    action: () async {
      await _hierarchyRepository.lockMutationScope();
      await _blocks.unblock(
        blockerId: blockerId,
        blockedId: blockedId,
      );
      await _invalidateWitnessWindows(blockerId, blockedId);
      await _trustLedger.project([(blockerId, blockedId)]);
    },
  );

  /// Promote an inherited block to a direct block (metadata only; no cleanup).
  Future<void> promoteToDirect({
    required String blockerId,
    required String blockedId,
  }) => _unitOfWork.run(
    actorUserId: blockerId,
    action: () => _blocks.promoteToDirect(
      blockerId: blockerId,
      blockedId: blockedId,
    ),
  );

  Future<void> _invalidateWitnessWindows(
    String blockerId,
    String blockedId,
  ) async {
    final witnessWindow = _witnessWindow;
    if (witnessWindow == null) return;
    await witnessWindow.invalidateFor(userId: blockerId);
    await witnessWindow.invalidateFor(userId: blockedId);
  }

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

  Future<void> _cleanupDirectPair(
    String blockerId,
    String blockedId,
    AttentionTransaction? transaction,
  ) async {
    await _withdrawPendingHelpOffers(blockerId, blockedId, transaction);
    await _withdrawPendingAuthorInvites(blockerId, blockedId);
    await _cancelForwardEdgesBetween(blockerId, blockedId);
    await _deleteContactsBetween(blockerId, blockedId);
  }

  /// Budding (Arch §5.4): pending author invites between the pair become
  /// withdrawn and the invitee's `authorInviteReceived` receipt is cleared.
  /// Their delivery edges are cancelled with the other edges between the pair.
  Future<void> _withdrawPendingAuthorInvites(
    String blockerId,
    String blockedId,
  ) async {
    final invites = _authorInvites;
    if (invites == null) return;
    final ended = await invites.withdrawPendingBetween(blockerId, blockedId);
    for (final invite in ended) {
      await _attentionSystemSettlement?.clearAuthorInviteReceived(
        beaconId: invite.beaconId,
        inviteeId: invite.inviteeId,
      );
    }
  }

  Future<void> _withdrawPendingHelpOffers(
    String blockerId,
    String blockedId,
    AttentionTransaction? transaction,
  ) async {
    await _withdrawOffersByOfferer(
      blockerId: blockerId,
      offererId: blockerId,
      beaconAuthorId: blockedId,
      transaction: transaction,
    );
    await _withdrawOffersByOfferer(
      blockerId: blockerId,
      offererId: blockedId,
      beaconAuthorId: blockerId,
      transaction: transaction,
    );
  }

  Future<void> _withdrawOffersByOfferer({
    required String blockerId,
    required String offererId,
    required String beaconAuthorId,
    required AttentionTransaction? transaction,
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
      await _closureCase?.lockRequest(beaconId);
      await _commitmentRepository.record(
        beaconId: beaconId,
        userId: offererId,
        actorUserId: offererId,
        mutatingUserId: blockerId,
        kind: CommitmentEventKind.blockedCleanup,
        reason: kBlockWithdrawReason,
      );
      await _closureCase?.applyMembershipEvent(beaconId, offererId);
      await _helpOffers.withdraw(
        beaconId: beaconId,
        userId: offererId,
        withdrawReason: kBlockWithdrawReason,
        mutatingUserId: blockerId,
      );
      // Leave the room too, as an ordinary withdrawal does
      // (HelpOfferCase.withdraw). Otherwise the participant row stays
      // committed with room access, and after an unblock the author still
      // lists an "Active helper" whose offer is withdrawn, while the helper's
      // Requests tab (active offers only) no longer shows the request (B059).
      await _roomRepository?.revokeOfferUserBeaconRoomAccess(
        beaconId: beaconId,
        offerUserId: offererId,
        authorUserId: blockerId,
      );
      // Without room access they can't hold plan steps either: free them as
      // a withdrawal or an author removal does (plan §4.6 item 4;
      // BeaconPlanCase.unassignOnLeave covers blocked users). Someone still
      // admitted (a steward) keeps theirs.
      if (transaction != null) {
        await _beaconPlan?.unassignOnLeave(
          transaction: transaction,
          beaconId: beaconId,
          userId: offererId,
          actorId: blockerId,
        );
      }
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
    final authorId = (await _beacons.getBeaconById(
      beaconId: beaconId,
    )).author.id;
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
      await _capabilityEvidence.reconcileForwardReasons(
        forwardEdgeId: edge.id,
        observerId: senderId,
        subjectId: edge.recipientId,
        slugs: const [],
      );
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
