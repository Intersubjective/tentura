import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_status_result.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/beacon_kind_policy.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/author_invite_port.dart';
import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/admission_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

import 'beacon_plan_case.dart';
import '_use_case_base.dart';

@Singleton(order: 2)
final class CoordinationCase extends UseCaseBase {
  CoordinationCase(
    this._beaconRepository,
    this._helpOfferRepository,
    this._coordinationRepository,
    this._beaconRoomRepository,
    this._userBlockRepository,
    this._commitmentRepository,
    this._commitmentQueryCase,
    this._hierarchyRepository, {
    required this._guard,
    required super.env,
    required super.logger,
    this._beaconPlan,
    this._attentionIntents,
    this._attention,
    this._authorInvites,
    AttentionSystemSettlementPort? attentionSystemSettlement,
    ClosureCase? closureCase,
  }) : _attentionSystemSettlement = attentionSystemSettlement,
       _closureCase = closureCase,
       _admission = AdmissionOperation(
         _helpOfferRepository,
         _coordinationRepository,
         _commitmentRepository,
         closureCase,
         attentionSystemSettlement,
       );

  final BeaconRepositoryPort _beaconRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final BeaconRoomRepositoryPort _beaconRoomRepository;
  final UserBlockRepositoryPort _userBlockRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final CommitmentQueryCase _commitmentQueryCase;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;
  final AttentionSystemSettlementPort? _attentionSystemSettlement;
  final BeaconAccessGuard _guard;
  final ClosureCase? _closureCase;
  final BeaconPlanCase? _beaconPlan;
  final BeaconHierarchyRepositoryPort _hierarchyRepository;
  final AdmissionOperation _admission;
  final AuthorInvitePort? _authorInvites;

  Future<BeaconEntity> _ensureAuthorOrSteward({
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    BeaconKindPolicy.requireRequest(beacon);
    if (beacon.author.id == userId) return beacon;
    final isSteward = await _beaconRoomRepository.isBeaconSteward(
      beaconId: beaconId,
      userId: userId,
    );
    if (!isSteward) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.notBeaconAuthor,
      );
    }
    return beacon;
  }

  Future<BeaconEntity> _ensureAuthor({
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    BeaconKindPolicy.requireRequest(beacon);
    if (beacon.author.id != userId) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.notBeaconAuthor,
      );
    }
    return beacon;
  }

  Future<List<HelpOfferWithCoordinationRow>> helpOffersWithCoordination({
    required String beaconId,
    required String viewerId,
  }) async {
    if (!await _guard.canReadInvolvement(
      beaconId: beaconId,
      viewerId: viewerId,
    )) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request involvement',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    BeaconKindPolicy.requireRequest(beacon);
    final isAuthor = beacon.author.id == viewerId;
    final isSteward =
        !isAuthor &&
        await _beaconRoomRepository.isBeaconSteward(
          beaconId: beaconId,
          userId: viewerId,
        );
    final rows = await _coordinationRepository.helpOffersWithCoordination(
      beaconId,
      viewerId: viewerId,
    );
    return [
      for (final row in rows)
        if (isAuthor || isSteward || row.userId == viewerId)
          row
        else
          row.copyWith(clearAdmissionFields: true),
    ];
  }

  /// The viewer's own offer row (any status), or `null` when they never
  /// offered. Needs only content access: once an offer is declined the
  /// offerer loses involvement access, yet the decline and its reason are
  /// theirs to see.
  Future<HelpOfferWithCoordinationRow?> myHelpOffer({
    required String beaconId,
    required String viewerId,
  }) async {
    if (!await _guard.canReadContent(
      beaconId: beaconId,
      viewerId: viewerId,
    )) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request',
      );
    }
    final rows = await _coordinationRepository.helpOffersWithCoordination(
      beaconId,
      viewerId: viewerId,
    );
    for (final row in rows) {
      if (row.userId == viewerId) return row;
    }
    return null;
  }

  /// [allowRemoved]: also accept an offer that an author removal
  /// deactivated (see [_removedOfferFor]); the result says so, and the caller
  /// re-activates it as it lets the helper back in.
  Future<({BeaconEntity beacon, HelpOfferEntity offer, bool removed})>
  _prepareAdmissionAction({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    bool allowRemoved = false,
  }) async {
    final beacon = await _ensureAuthorOrSteward(
      beaconId: beaconId,
      userId: actorUserId,
    );
    if (await _userBlockRepository.isBlockedPair(
      a: actorUserId,
      b: offerUserId,
    )) {
      throw const UnauthorizedException(
        description: 'Cannot admit a blocked user',
      );
    }
    if (!beacon.status.isOpenFamily) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.beaconNotOpen,
      );
    }
    final active = await _helpOfferRepository.fetchByBeaconId(beaconId);
    HelpOfferEntity? offer;
    for (final candidate in active) {
      if (candidate.userId == offerUserId) {
        offer = candidate;
        break;
      }
    }
    if (offer != null) return (beacon: beacon, offer: offer, removed: false);
    final removed = allowRemoved
        ? await _removedOfferFor(beaconId: beaconId, userId: offerUserId)
        : null;
    if (removed == null) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.helpOfferNotActive,
      );
    }
    return (beacon: beacon, offer: removed, removed: true);
  }

  /// The offer of a helper the author removed, while they are still out:
  /// removal deactivates the offer (so it stops counting as active, like a
  /// decline) without an exit reason, and the pair's last exit or return is
  /// `removedFromChat`. A withdrawal or block cleanup after the removal sets
  /// a reason and ends the pair, so that offer stays inactive.
  Future<HelpOfferEntity?> _removedOfferFor({
    required String beaconId,
    required String userId,
  }) async {
    HelpOfferEntity? row;
    for (final candidate in await _helpOfferRepository.fetchAllByBeaconId(
      beaconId,
    )) {
      if (candidate.userId == userId) {
        row = candidate;
        break;
      }
    }
    if (row == null || !row.isWithdrawn || row.withdrawReason != null) {
      return null;
    }
    final events = await _eventsForPair(beaconId: beaconId, userId: userId);
    return _isRemovedAndStillOut(events) ? row : null;
  }

  bool _isRemovedAndStillOut(List<CommitmentEvent> events) {
    final sorted = [...events]..sort((a, b) => a.seq.compareTo(b.seq));
    var out = false;
    for (final event in sorted) {
      switch (event.kind) {
        case CommitmentEventKind.removedFromChat:
          out = true;
        case CommitmentEventKind.readmittedToChat:
        case CommitmentEventKind.withdrawnByHelper:
        case CommitmentEventKind.releasedByAuthor:
        case CommitmentEventKind.blockedCleanup:
        case CommitmentEventKind.unansweredAtClose:
          out = false;
        case CommitmentEventKind.offered:
        case CommitmentEventKind.acknowledged:
        case CommitmentEventKind.acknowledgementSoftened:
          break;
      }
    }
    return out;
  }

  String _validateReason(String reason) {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.reasonRequired,
      );
    }
    if (trimmed.length > 500) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.reasonTooLong,
      );
    }
    return trimmed;
  }

  bool _isAcknowledgingResponseType(int responseType) =>
      responseType == CoordinationResponseType.useful.smallintValue ||
      responseType == CoordinationResponseType.needCoordination.smallintValue;

  bool _isRemovedFromChatByEvents(List<CommitmentEvent> events) {
    final sorted = [...events]..sort((a, b) => a.seq.compareTo(b.seq));
    var removed = false;
    for (final event in sorted) {
      switch (event.kind) {
        case CommitmentEventKind.removedFromChat:
          removed = true;
        case CommitmentEventKind.readmittedToChat:
          removed = false;
        case CommitmentEventKind.offered:
        case CommitmentEventKind.acknowledged:
        case CommitmentEventKind.acknowledgementSoftened:
        case CommitmentEventKind.withdrawnByHelper:
        case CommitmentEventKind.releasedByAuthor:
        case CommitmentEventKind.blockedCleanup:
        case CommitmentEventKind.unansweredAtClose:
          break;
      }
    }
    return removed;
  }

  Future<List<CommitmentEvent>> _eventsForPair({
    required String beaconId,
    required String userId,
  }) => _commitmentRepository.eventsForPair(
    beaconId: beaconId,
    userId: userId,
  );

  Future<void> _recordAcknowledgedIfTransition({
    required String beaconId,
    required String userId,
    required String actorUserId,
  }) async {
    final events = await _eventsForPair(beaconId: beaconId, userId: userId);
    if (currentStakeState(events) == CommitmentStakeState.acknowledged) return;
    await _closureCase?.lockRequest(beaconId);
    await _commitmentRepository.record(
      beaconId: beaconId,
      userId: userId,
      actorUserId: actorUserId,
      kind: CommitmentEventKind.acknowledged,
    );
    await _closureCase?.applyMembershipEvent(beaconId, userId);
  }

  Future<void> _recordSoftenedIfTransition({
    required String beaconId,
    required String userId,
    required String actorUserId,
  }) async {
    final events = await _eventsForPair(beaconId: beaconId, userId: userId);
    if (currentStakeState(events) == CommitmentStakeState.softened) return;
    if (!everAcknowledged(events)) return;
    await _commitmentRepository.record(
      beaconId: beaconId,
      userId: userId,
      actorUserId: actorUserId,
      kind: CommitmentEventKind.acknowledgementSoftened,
    );
  }

  Future<void> _recordRemovedFromChatIfTransition({
    required String beaconId,
    required String userId,
    required String actorUserId,
    String? reason,
  }) async {
    final events = await _eventsForPair(beaconId: beaconId, userId: userId);
    if (_isRemovedFromChatByEvents(events)) return;
    await _closureCase?.lockRequest(beaconId);
    await _commitmentRepository.record(
      beaconId: beaconId,
      userId: userId,
      actorUserId: actorUserId,
      kind: CommitmentEventKind.removedFromChat,
      reason: reason,
    );
    await _closureCase?.applyMembershipEvent(beaconId, userId);
  }

  Future<void> _recordReadmittedToChatIfTransition({
    required String beaconId,
    required String userId,
    required String actorUserId,
  }) async {
    final events = await _eventsForPair(beaconId: beaconId, userId: userId);
    if (!_isRemovedFromChatByEvents(events)) return;
    await _closureCase?.lockRequest(beaconId);
    await _commitmentRepository.record(
      beaconId: beaconId,
      userId: userId,
      actorUserId: actorUserId,
      kind: CommitmentEventKind.readmittedToChat,
    );
    await _closureCase?.applyMembershipEvent(beaconId, userId);
  }

  Future<void> _recordResponseCommitmentEvents({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required int responseType,
    required bool inviteToRoom,
    required bool removeFromRoom,
  }) async {
    if (_isAcknowledgingResponseType(responseType)) {
      await _recordAcknowledgedIfTransition(
        beaconId: beaconId,
        userId: offerUserId,
        actorUserId: actorUserId,
      );
    } else if (await _commitmentQueryCase.everAcknowledgedPair(
      beaconId: beaconId,
      userId: offerUserId,
    )) {
      await _recordSoftenedIfTransition(
        beaconId: beaconId,
        userId: offerUserId,
        actorUserId: actorUserId,
      );
    }
    if (removeFromRoom) {
      await _recordRemovedFromChatIfTransition(
        beaconId: beaconId,
        userId: offerUserId,
        actorUserId: actorUserId,
      );
    } else if (inviteToRoom) {
      await _recordReadmittedToChatIfTransition(
        beaconId: beaconId,
        userId: offerUserId,
        actorUserId: actorUserId,
      );
    }
  }

  BeaconStatusResult _statusResult(
    String beaconId,
    ({BeaconStatus status, DateTime? statusChangedAt}) snap,
  ) => BeaconStatusResult(
    beaconId: beaconId,
    status: snap.status.smallintValue,
    statusChangedAt: snap.statusChangedAt,
  );

  Future<BeaconStatusResult> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
  }) async {
    return _attention!.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        // Lock order (Arch §0): hierarchy, then the child lock; revalidate
        // everything mutable only once they are held.
        await _hierarchyRepository.lockMutationScope();
        await _closureCase?.lockRequest(beaconId);
        final prepared = await _prepareAdmissionAction(
          beaconId: beaconId,
          offerUserId: offerUserId,
          actorUserId: actorUserId,
          allowRemoved: true,
        );
        final beacon = prepared.beacon;
        if (prepared.removed) {
          // Letting a removed helper back in: their offer counts again.
          await _helpOfferRepository.reactivate(
            beaconId: beaconId,
            userId: offerUserId,
          );
          await _recordReadmittedToChatIfTransition(
            beaconId: beaconId,
            userId: offerUserId,
            actorUserId: actorUserId,
          );
        }
        // The actor (author or steward) is the confirming author; the offer
        // checked above is the helper's confirmation, so step (a) is a no-op.
        final snap = await _admission.admitWithConfirmations(
          beacon: beacon,
          helperId: offerUserId,
          confirmingAuthorId: actorUserId,
          actorId: actorUserId,
          transaction: transaction,
          attention: () => _attentionIntents!.offerAccepted(
            receiverId: offerUserId,
            beaconId: beaconId,
            actorUserId: actorUserId,
            sourceEventKey: 'admission:${generateId('A')}',
            beaconTitle: beacon.title,
            bodyExcerpt: prepared.offer.message,
          ),
        );
        await _supersedePendingInvite(
          beaconId: beaconId,
          helperId: offerUserId,
          actorUserId: actorUserId,
        );
        return _statusResult(beaconId, snap);
      },
    );
  }

  /// Budding (Arch §5.4): the author accepted an ordinary offer from a
  /// pending invitee, so the invite is superseded (the N5 slot frees) and the
  /// invitee's `authorInviteReceived` receipt is cleared.
  Future<void> _supersedePendingInvite({
    required String beaconId,
    required String helperId,
    required String actorUserId,
  }) async {
    final invites = _authorInvites;
    if (invites == null) return;
    final pending = await invites.fetchPending(
      beaconId: beaconId,
      inviteeId: helperId,
    );
    if (pending == null) return;
    final ended = await invites.resolve(
      inviteId: pending.id,
      status: AuthorInviteStatus.superseded,
      resolvedBy: actorUserId,
    );
    if (ended == null) return;
    await _attentionSystemSettlement?.clearAuthorInviteReceived(
      beaconId: beaconId,
      inviteeId: helperId,
    );
  }

  Future<BeaconStatusResult> declineHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) async {
    final trimmedReason = _validateReason(reason);
    return _attention!.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        // Lock order (Arch §0): hierarchy before the child lock, ahead of the
        // offer row, as the helper's withdrawal takes them; the participant
        // trigger takes the hierarchy lock anyway, so taking it last deadlocks.
        await _hierarchyRepository.lockMutationScope();
        await _closureCase?.lockRequest(beaconId);
        final prepared = await _prepareAdmissionAction(
          beaconId: beaconId,
          offerUserId: offerUserId,
          actorUserId: actorUserId,
        );
        final beacon = prepared.beacon;
        // Re-read after locking: an invite accept may have acknowledged the
        // helper while this waited for the locks.
        final hadAcknowledged = await _commitmentQueryCase.everAcknowledgedPair(
          beaconId: beaconId,
          userId: offerUserId,
        );
        if (hadAcknowledged) {
          throw HelpOfferCoordinationException(
            coordinationCode: HelpOfferCoordinationExceptionCode
                .commitmentAlreadyAcknowledged,
          );
        }
        // Snapshot the affected helper while the pre-decline audience is intact.
        final intent = await _attentionIntents!.offerDeclined(
          receiverId: offerUserId,
          beaconId: beaconId,
          actorUserId: actorUserId,
          reason: trimmedReason,
          sourceEventKey: 'admission:${generateId('A')}',
        );
        final snap = await _coordinationRepository.declineHelpOffer(
          beaconId: beaconId,
          offerUserId: offerUserId,
          actorUserId: actorUserId,
          reason: trimmedReason,
        );
        await _helpOfferRepository.deactivate(
          beaconId: beaconId,
          userId: offerUserId,
        );
        await _beaconRoomRepository.revokeOfferUserBeaconRoomAccess(
          beaconId: beaconId,
          offerUserId: offerUserId,
          authorUserId: actorUserId,
        );
        await transaction.record(intent);
        await _attentionSystemSettlement?.settleAuthorHelpOfferSubmitted(
          beaconId: beaconId,
          authorAccountId: beacon.author.id,
          helpOffererUserId: offerUserId,
        );
        return _statusResult(beaconId, snap);
      },
    );
  }

  Future<BeaconStatusResult> removeFromRoom({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) async {
    final trimmedReason = _validateReason(reason);
    final prepared = await _prepareAdmissionAction(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
    );
    final beacon = prepared.beacon;
    final participant = await _beaconRoomRepository.findParticipant(
      beaconId: beaconId,
      userId: offerUserId,
    );
    if (participant?.roomAccess != RoomAccessBits.admitted) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.notAdmitted,
      );
    }
    return _attention!.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        await _hierarchyRepository.lockMutationScope();
        // Lock order (Arch §0): hierarchy, then the child lock, ahead of the
        // offer row, as decline and the helper's withdrawal take them.
        await _closureCase?.lockRequest(beaconId);
        // Snapshot before access revocation so the terminal receipt survives.
        final intent = await _attentionIntents!.offerRemoved(
          receiverId: offerUserId,
          beaconId: beaconId,
          actorUserId: actorUserId,
          reason: trimmedReason,
          sourceEventKey: 'admission:${generateId('A')}',
        );
        final snap = await _coordinationRepository.removeFromRoom(
          beaconId: beaconId,
          offerUserId: offerUserId,
          actorUserId: actorUserId,
          reason: trimmedReason,
        );
        // Maintainer's call on #401: a removed helper's offer stops counting
        // as active (as after a decline); accepting them again re-activates
        // it. No exit reason is set, which is what tells the two apart from a
        // withdrawal.
        await _helpOfferRepository.deactivate(
          beaconId: beaconId,
          userId: offerUserId,
        );
        await _recordRemovedFromChatIfTransition(
          beaconId: beaconId,
          userId: offerUserId,
          actorUserId: actorUserId,
          reason: trimmedReason,
        );
        await transaction.record(intent);
        // D04 terminal invalidation: the offer is gone, so any author
        // `helpOfferSubmitted` obligation still pointing at this helper ends
        // here. Normally already settled by accept; this closes the gap U07a
        // found for offers that reach a terminal state another way.
        await _attentionSystemSettlement?.supersedeAuthorHelpOfferSubmitted(
          beaconId: beaconId,
          authorAccountId: beacon.author.id,
          helpOffererUserId: offerUserId,
        );
        // Their plan steps lose their assignee (plan §4.6 item 4).
        await _beaconPlan?.unassignOnLeave(
          transaction: transaction,
          beaconId: beaconId,
          userId: offerUserId,
          actorId: actorUserId,
        );
        return _statusResult(beaconId, snap);
      },
    );
  }

  Future<BeaconStatusResult> releaseCommitment({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required String reason,
  }) async {
    final trimmedReason = _validateReason(reason);
    final beacon = await _ensureAuthor(
      beaconId: beaconId,
      userId: authorUserId,
    );
    if (!beacon.status.isOpenFamily) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.beaconNotOpen,
      );
    }
    if (!await _commitmentQueryCase.everAcknowledgedPair(
      beaconId: beaconId,
      userId: offerUserId,
    )) {
      throw HelpOfferCoordinationException(
        coordinationCode:
            HelpOfferCoordinationExceptionCode.commitmentNotAcknowledged,
      );
    }
    final events = await _eventsForPair(
      beaconId: beaconId,
      userId: offerUserId,
    );
    final stake = currentStakeState(events);
    if (stake == CommitmentStakeState.released ||
        stake == CommitmentStakeState.exited) {
      final snap = await _coordinationRepository.beaconStatusSnapshot(beaconId);
      return _statusResult(beaconId, snap);
    }
    return _attention!.runAction(
      actorUserId: authorUserId,
      action: (transaction) async {
        await _hierarchyRepository.lockMutationScope();
        final participant = await _beaconRoomRepository.findParticipant(
          beaconId: beaconId,
          userId: offerUserId,
        );
        if (participant?.roomAccess == RoomAccessBits.admitted) {
          final removalIntent = await _attentionIntents!.offerRemoved(
            receiverId: offerUserId,
            beaconId: beaconId,
            actorUserId: authorUserId,
            reason: trimmedReason,
            sourceEventKey: 'admission:${generateId('A')}',
          );
          await _coordinationRepository.removeFromRoom(
            beaconId: beaconId,
            offerUserId: offerUserId,
            actorUserId: authorUserId,
            reason: trimmedReason,
          );
          await _recordRemovedFromChatIfTransition(
            beaconId: beaconId,
            userId: offerUserId,
            actorUserId: authorUserId,
            reason: trimmedReason,
          );
          await transaction.record(removalIntent);
          await _attentionSystemSettlement?.supersedeAuthorHelpOfferSubmitted(
            beaconId: beaconId,
            authorAccountId: beacon.author.id,
            helpOffererUserId: offerUserId,
          );
          await _beaconPlan?.unassignOnLeave(
            transaction: transaction,
            beaconId: beaconId,
            userId: offerUserId,
            actorId: authorUserId,
          );
        }
        final intent = await _attentionIntents!.commitmentReleased(
          receiverId: offerUserId,
          beaconId: beaconId,
          actorUserId: authorUserId,
          reason: trimmedReason,
          sourceEventKey: 'admission:${generateId('A')}',
        );
        await _closureCase?.lockRequest(beaconId);
        await _commitmentRepository.record(
          beaconId: beaconId,
          userId: offerUserId,
          actorUserId: authorUserId,
          kind: CommitmentEventKind.releasedByAuthor,
          reason: trimmedReason,
        );
        await _closureCase?.applyMembershipEvent(beaconId, offerUserId);
        await transaction.record(intent);
        final snap = await _coordinationRepository.beaconStatusSnapshot(
          beaconId,
        );
        return _statusResult(beaconId, snap);
      },
    );
  }

  Future<BeaconStatusResult> setCoordinationResponse({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required int responseType,
    required bool inviteToRoom,
    required bool removeFromRoom,
  }) async {
    final beacon = await _ensureAuthor(
      beaconId: beaconId,
      userId: authorUserId,
    );
    if (!beacon.status.isOpenFamily) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.beaconNotOpen,
      );
    }
    if (CoordinationResponseType.tryFromInt(responseType) == null) {
      throw HelpOfferCoordinationException(
        coordinationCode:
            HelpOfferCoordinationExceptionCode.invalidResponseType,
      );
    }
    final active = await _helpOfferRepository.fetchByBeaconId(beaconId);
    // Inviting a removed helper back in also re-activates their offer.
    final readmitsRemoved =
        !active.any((c) => c.userId == offerUserId) &&
        inviteToRoom &&
        await _removedOfferFor(beaconId: beaconId, userId: offerUserId) !=
            null;
    if (!active.any((c) => c.userId == offerUserId) && !readmitsRemoved) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.helpOfferNotActive,
      );
    }
    if (inviteToRoom && !_isAcknowledgingResponseType(responseType)) {
      throw HelpOfferCoordinationException(
        coordinationCode:
            HelpOfferCoordinationExceptionCode.admissionRequiresAcknowledgement,
      );
    }
    if (!_isAcknowledgingResponseType(responseType) &&
        await _commitmentQueryCase.everAcknowledgedPair(
          beaconId: beaconId,
          userId: offerUserId,
        )) {
      throw HelpOfferCoordinationException(
        coordinationCode:
            HelpOfferCoordinationExceptionCode.commitmentAlreadyAcknowledged,
      );
    }
    await _coordinationRepository.upsertResponse(
      beaconId: beaconId,
      offerUserId: offerUserId,
      authorUserId: authorUserId,
      responseType: responseType,
    );
    if (removeFromRoom || inviteToRoom) {
      await _hierarchyRepository.lockMutationScope();
    }
    if (removeFromRoom) {
      await _beaconRoomRepository.revokeOfferUserBeaconRoomAccess(
        beaconId: beaconId,
        offerUserId: offerUserId,
        authorUserId: authorUserId,
      );
      await _helpOfferRepository.deactivate(
        beaconId: beaconId,
        userId: offerUserId,
      );
    } else if (inviteToRoom) {
      if (readmitsRemoved) {
        await _helpOfferRepository.reactivate(
          beaconId: beaconId,
          userId: offerUserId,
        );
      }
      await _beaconRoomRepository.inviteOfferUserToBeaconRoom(
        beaconId: beaconId,
        offerUserId: offerUserId,
        authorUserId: authorUserId,
      );
    }
    await _recordResponseCommitmentEvents(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: authorUserId,
      responseType: responseType,
      inviteToRoom: inviteToRoom,
      removeFromRoom: removeFromRoom,
    );
    final snap = await _coordinationRepository.beaconStatusSnapshot(beaconId);
    return BeaconStatusResult(
      beaconId: beaconId,
      status: snap.status.smallintValue,
      statusChangedAt: snap.statusChangedAt,
    );
  }

  Future<BeaconStatusResult> setBeaconStatus({
    required String beaconId,
    required String authorUserId,
    required int status,
  }) async {
    await _ensureAuthorOrSteward(beaconId: beaconId, userId: authorUserId);
    final target = coordinationTargetStatus(status);

    Future<BeaconStatusResult> mutate(
      AttentionTransaction? transaction,
    ) async {
      // The status trigger takes the hierarchy lock, so it (then the child
      // advisory lock) must come before the child row (Arch §4.1).
      await _hierarchyRepository.lockMutationScope();
      await _closureCase?.lockRequest(beaconId);
      return _beaconRepository.runInBeaconStateTransaction(
        beaconId: beaconId,
        userId: authorUserId,
        fn: (beacon) async {
          if (beacon.status == BeaconStatus.reviewOpen) {
            if (target == BeaconStatus.enoughHelp ||
                target == BeaconStatus.open) {
              throw HelpOfferCoordinationException(
                coordinationCode: HelpOfferCoordinationExceptionCode
                    .invalidCoordinationStatus,
              );
            }
          }

          if (target == BeaconStatus.needsMoreHelp &&
              beacon.status == BeaconStatus.reviewOpen) {
            final closure = _closureCase;
            if (closure != null) {
              await closure.reopen(authorId: authorUserId, beaconId: beaconId);
              final snap = await _coordinationRepository.beaconStatusSnapshot(
                beaconId,
              );
              return BeaconStatusResult(
                beaconId: beaconId,
                status: snap.status.smallintValue,
                statusChangedAt: snap.statusChangedAt,
              );
            }
          }

          final reason = switch (target) {
            BeaconStatus.needsMoreHelp =>
              BeaconStatusTransitionReason.needsMoreHelp,
            BeaconStatus.enoughHelp => BeaconStatusTransitionReason.enoughHelp,
            BeaconStatus.open => BeaconStatusTransitionReason.neutralOpen,
            _ => throw HelpOfferCoordinationException(
              coordinationCode:
                  HelpOfferCoordinationExceptionCode.invalidCoordinationStatus,
            ),
          };

          final verdict = validateBeaconStatusTransition(
            from: beacon.status,
            to: target,
            reason: reason,
          );
          if (verdict.verdict == BeaconStatusTransitionVerdict.noop) {
            final snap = await _coordinationRepository.beaconStatusSnapshot(
              beaconId,
            );
            return BeaconStatusResult(
              beaconId: beaconId,
              status: snap.status.smallintValue,
              statusChangedAt: snap.statusChangedAt,
            );
          }
          if (verdict.verdict != BeaconStatusTransitionVerdict.allowed) {
            throw HelpOfferCoordinationException(
              coordinationCode:
                  HelpOfferCoordinationExceptionCode.invalidCoordinationStatus,
            );
          }

          final intent = transaction == null
              ? null
              : await _attentionIntents!.requestStatusChanged(
                  beaconId: beaconId,
                  fromStatus: beacon.status.name,
                  toStatus: target.name,
                  actorUserId: authorUserId,
                  sourceEventKey: 'request_status:${generateId('A')}',
                );
          await _beaconRepository.recordBeaconStatusTransition(
            beaconId: beaconId,
            fromStatus: beacon.status,
            toStatus: target,
            reason: reasonStringForTransition(reason),
            actorId: authorUserId,
          );
          if (intent != null) {
            await transaction!.record(intent);
          }

          final snap = await _coordinationRepository.beaconStatusSnapshot(
            beaconId,
          );
          return BeaconStatusResult(
            beaconId: beaconId,
            status: snap.status.smallintValue,
            statusChangedAt: snap.statusChangedAt,
          );
        },
      );
    }

    return _attention!.runAction(
      actorUserId: authorUserId,
      action: mutate,
    );
  }
}
