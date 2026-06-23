import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/coordination/beacon_coordination_status.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class CoordinationCase extends UseCaseBase {
  CoordinationCase(
    this._beaconRepository,
    this._helpOfferRepository,
    this._coordinationRepository,
    this._beaconRoomRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final BeaconRoomRepository _beaconRoomRepository;

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

  Future<void> _ensureAuthor({
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.author.id != userId) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.notBeaconAuthor,
      );
    }
  }

  Future<List<HelpOfferWithCoordinationRow>> helpOffersWithCoordination({
    required String beaconId,
    required String viewerId,
  }) => _coordinationRepository.helpOffersWithCoordination(
        beaconId,
        viewerId: viewerId,
      );

  // TODO(contract): Phase-2 DTO migration — replace Map return with typed DTO at resolver boundary.
  // ignore: tentura_lints/no_map_dynamic_in_use_case_api
  Future<Map<String, dynamic>> setCoordinationResponse({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required int responseType,
    required bool inviteToRoom,
    required bool removeFromRoom,
  }) async {
    await _ensureAuthor(beaconId: beaconId, userId: authorUserId);
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
    return {
      'beaconId': beaconId,
      'coordinationStatus': snap.coordinationStatus,
      'coordinationStatusUpdatedAt':
          snap.coordinationStatusUpdatedAt?.toUtc().toIso8601String(),
    };
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
    await _coordinationRepository.setBeaconCoordinationFields(
      beaconId: beaconId,
      coordinationStatus: status,
    );
    return true;
  }
}
