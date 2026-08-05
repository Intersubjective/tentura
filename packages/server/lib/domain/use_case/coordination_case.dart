import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_status_result.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class CoordinationCase extends UseCaseBase {
  CoordinationCase(
    this._beaconRepository,
    this._helpOfferRepository,
    this._coordinationRepository,
    this._beaconRoomRepository,
    this._evaluationRepository,
    this._userBlockRepository,
    this._commitmentRepository,
    this._commitmentQueryCase, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required BeaconAccessGuard guard,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention,
       _guard = guard;

  final BeaconRepositoryPort _beaconRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final BeaconRoomRepositoryPort _beaconRoomRepository;
  final EvaluationRepositoryPort _evaluationRepository;
  final UserBlockRepositoryPort _userBlockRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final CommitmentQueryCase _commitmentQueryCase;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;
  final BeaconAccessGuard _guard;

  Future<BeaconEntity> _ensureAuthorOrSteward({
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
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
    if (!await _guard.canReadContent(beaconId: beaconId, viewerId: viewerId)) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request content',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
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

  Future<BeaconEntity> _prepareAdmissionAction({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
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
    if (!active.any((c) => c.userId == offerUserId)) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.helpOfferNotActive,
      );
    }
    return beacon;
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
  }) =>
      _commitmentRepository.eventsForPair(
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
    await _commitmentRepository.record(
      beaconId: beaconId,
      userId: userId,
      actorUserId: actorUserId,
      kind: CommitmentEventKind.acknowledged,
    );
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
    await _commitmentRepository.record(
      beaconId: beaconId,
      userId: userId,
      actorUserId: actorUserId,
      kind: CommitmentEventKind.removedFromChat,
      reason: reason,
    );
  }

  Future<void> _recordReadmittedToChatIfTransition({
    required String beaconId,
    required String userId,
    required String actorUserId,
  }) async {
    final events = await _eventsForPair(beaconId: beaconId, userId: userId);
    if (!_isRemovedFromChatByEvents(events)) return;
    await _commitmentRepository.record(
      beaconId: beaconId,
      userId: userId,
      actorUserId: actorUserId,
      kind: CommitmentEventKind.readmittedToChat,
    );
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
    await _prepareAdmissionAction(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
    );
    return _attention!.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        final snap = await _coordinationRepository.acceptHelpOffer(
          beaconId: beaconId,
          offerUserId: offerUserId,
          actorUserId: actorUserId,
        );
        await _recordAcknowledgedIfTransition(
          beaconId: beaconId,
          userId: offerUserId,
          actorUserId: actorUserId,
        );
        await transaction.record(
          await _attentionIntents!.offerAccepted(
            receiverId: offerUserId,
            beaconId: beaconId,
            actorUserId: actorUserId,
            sourceEventKey: 'admission:${generateId('A')}',
          ),
        );
        return _statusResult(beaconId, snap);
      },
    );
  }

  Future<BeaconStatusResult> declineHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) async {
    final trimmedReason = _validateReason(reason);
    final hadAcknowledged = await _commitmentQueryCase.everAcknowledgedPair(
      beaconId: beaconId,
      userId: offerUserId,
    );
    await _prepareAdmissionAction(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
    );
    if (hadAcknowledged) {
      throw HelpOfferCoordinationException(
        coordinationCode:
            HelpOfferCoordinationExceptionCode.commitmentAlreadyAcknowledged,
      );
    }
    return _attention!.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
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
        if (hadAcknowledged) {
          await _recordSoftenedIfTransition(
            beaconId: beaconId,
            userId: offerUserId,
            actorUserId: actorUserId,
          );
        }
        await transaction.record(intent);
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
    await _prepareAdmissionAction(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
    );
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
        await _recordRemovedFromChatIfTransition(
          beaconId: beaconId,
          userId: offerUserId,
          actorUserId: actorUserId,
          reason: trimmedReason,
        );
        await transaction.record(intent);
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
        final intent = await _attentionIntents!.commitmentReleased(
          receiverId: offerUserId,
          beaconId: beaconId,
          actorUserId: authorUserId,
          reason: trimmedReason,
          sourceEventKey: 'admission:${generateId('A')}',
        );
        await _commitmentRepository.record(
          beaconId: beaconId,
          userId: offerUserId,
          actorUserId: authorUserId,
          kind: CommitmentEventKind.releasedByAuthor,
          reason: trimmedReason,
        );
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
    if (!active.any((c) => c.userId == offerUserId)) {
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
    if (removeFromRoom) {
      await _beaconRoomRepository.revokeOfferUserBeaconRoomAccess(
        beaconId: beaconId,
        offerUserId: offerUserId,
        authorUserId: authorUserId,
      );
    } else if (inviteToRoom) {
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
    ) => _beaconRepository.runInBeaconStateTransaction(
      beaconId: beaconId,
      userId: authorUserId,
      fn: (beacon) async {
        if (target == BeaconStatus.needsMoreHelp &&
            beacon.status == BeaconStatus.reviewOpen) {
          final w = await _evaluationRepository.getReviewWindow(beaconId);
          if (w == null || w.status != 0) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
            );
          }
          await _evaluationRepository.downgradeSubmittedReviewsToDraft(
            beaconId,
          );
          await _evaluationRepository.deleteReviewScaffoldingForBeacon(
            beaconId,
          );
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

    return _attention!.runAction(
      actorUserId: authorUserId,
      action: mutate,
    );
  }
}
