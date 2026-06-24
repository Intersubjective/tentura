import 'package:injectable/injectable.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/coordination/beacon_coordination_status.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/coordination_status_result.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
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
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final BeaconRoomRepositoryPort _beaconRoomRepository;
  final EvaluationRepositoryPort _evaluationRepository;

  Future<void> _ensureAuthorOrSteward({
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.author.id == userId) return;
    final isSteward = await _beaconRoomRepository.isBeaconSteward(
      beaconId: beaconId,
      userId: userId,
    );
    if (!isSteward) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.notBeaconAuthor,
      );
    }
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
  }) => _coordinationRepository.helpOffersWithCoordination(
        beaconId,
        viewerId: viewerId,
      );

  Future<CoordinationStatusResult> setCoordinationResponse({
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
    if (beacon.state != 0) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.beaconNotOpen,
      );
    }
    if (CoordinationResponseType.tryFromInt(responseType) == null) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.invalidResponseType,
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
    final snap = await _coordinationRepository.beaconCoordinationSnapshot(
      beaconId,
    );
    return CoordinationStatusResult(
      beaconId: beaconId,
      coordinationStatus: snap.coordinationStatus,
      coordinationStatusUpdatedAt: snap.coordinationStatusUpdatedAt,
    );
  }

  Future<bool> setBeaconCoordinationStatus({
    required String beaconId,
    required String authorUserId,
    required int status,
  }) async {
    await _ensureAuthorOrSteward(beaconId: beaconId, userId: authorUserId);
    if (BeaconCoordinationStatus.tryFromInt(status) == null) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.invalidCoordinationStatus,
      );
    }

    if (status == BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue) {
      return _beaconRepository.runInBeaconStateTransaction(
        beaconId: beaconId,
        userId: authorUserId,
        fn: (beacon) async {
          if (beacon.state == 5) {
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
            await _beaconRepository.recordBeaconLifecycleTransition(
              beaconId: beaconId,
              fromState: beacon.state,
              toState: 0,
              reason: BeaconLifecycleChangeReason.reopenedFromReview,
              actorId: authorUserId,
            );
          }
          await _coordinationRepository.setBeaconCoordinationFields(
            beaconId: beaconId,
            coordinationStatus: status,
          );
          return true;
        },
      );
    }

    await _coordinationRepository.setBeaconCoordinationFields(
      beaconId: beaconId,
      coordinationStatus: status,
    );
    return true;
  }
}
