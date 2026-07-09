import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_status_result.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class CoordinationCase extends UseCaseBase {
  CoordinationCase(
    this._beaconRepository,
    this._helpOfferRepository,
    this._coordinationRepository,
    this._beaconRoomRepository,
    this._evaluationRepository, {
    required BeaconRoomNotificationPort roomPush,
    required BeaconAccessGuard guard,
    required super.env,
    required super.logger,
  }) : _roomPush = roomPush,
       _guard = guard;

  final BeaconRepositoryPort _beaconRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final BeaconRoomRepositoryPort _beaconRoomRepository;
  final EvaluationRepositoryPort _evaluationRepository;
  final BeaconRoomNotificationPort _roomPush;
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
    final snap = await _coordinationRepository.acceptHelpOffer(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
    );
    unawaited(
      _roomPush
          .notifyRoomAdmitted(
            receiverId: offerUserId,
            beaconId: beaconId,
            actorUserId: actorUserId,
          )
          .catchError((Object e, StackTrace st) {
            logger.warning(
              'CoordinationCase: room-admitted push failed',
              e,
              st,
            );
          }),
    );
    return _statusResult(beaconId, snap);
  }

  Future<BeaconStatusResult> declineHelpOffer({
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
    if (participant?.roomAccess == RoomAccessBits.admitted) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.alreadyAdmitted,
      );
    }
    final snap = await _coordinationRepository.declineHelpOffer(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      reason: trimmedReason,
    );
    unawaited(
      _roomPush
          .notifyCommitmentDeclined(
            receiverId: offerUserId,
            beaconId: beaconId,
            actorUserId: actorUserId,
            reason: trimmedReason,
          )
          .catchError((Object e, StackTrace st) {
            logger.warning(
              'CoordinationCase: commitment-declined push failed',
              e,
              st,
            );
          }),
    );
    return _statusResult(beaconId, snap);
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
    final snap = await _coordinationRepository.removeFromRoom(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      reason: trimmedReason,
    );
    unawaited(
      _roomPush
          .notifyCommitmentRemoved(
            receiverId: offerUserId,
            beaconId: beaconId,
            actorUserId: actorUserId,
            reason: trimmedReason,
          )
          .catchError((Object e, StackTrace st) {
            logger.warning(
              'CoordinationCase: commitment-removed push failed',
              e,
              st,
            );
          }),
    );
    return _statusResult(beaconId, snap);
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

    return _beaconRepository.runInBeaconStateTransaction(
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

        await _beaconRepository.recordBeaconStatusTransition(
          beaconId: beaconId,
          fromStatus: beacon.status,
          toStatus: target,
          reason: reasonStringForTransition(reason),
          actorId: authorUserId,
        );

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
}
