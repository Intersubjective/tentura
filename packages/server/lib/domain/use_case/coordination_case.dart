import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/domain/coordination/beacon_coordination_status.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

@Singleton(order: 2)
class CoordinationCase {
  const CoordinationCase(
    this._beaconRepository,
    this._commitmentRepository,
    this._coordinationRepository,
  );

  final BeaconRepository _beaconRepository;
  final CommitmentRepository _commitmentRepository;
  final CoordinationRepository _coordinationRepository;

  Future<void> _ensureAuthor({
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.author.id != userId) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.notBeaconAuthor,
      );
    }
  }

  Future<List<Map<String, dynamic>>> commitmentsWithCoordination({
    required String beaconId,
  }) => _coordinationRepository.commitmentsWithCoordination(beaconId);

  Future<Map<String, dynamic>> setCoordinationResponse({
    required String beaconId,
    required String commitUserId,
    required String authorUserId,
    required int responseType,
  }) async {
    await _ensureAuthor(beaconId: beaconId, userId: authorUserId);
    if (CoordinationResponseType.tryFromInt(responseType) == null) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.invalidResponseType,
      );
    }
    final active = await _commitmentRepository.fetchByBeaconId(beaconId);
    if (!active.any((c) => c.userId == commitUserId)) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.commitmentNotActive,
      );
    }
    await _coordinationRepository.upsertResponse(
      beaconId: beaconId,
      commitUserId: commitUserId,
      authorUserId: authorUserId,
      responseType: responseType,
    );
    await _coordinationRepository.recomputeAndPersistBeaconCoordinationStatus(
      beaconId,
    );
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
    await _ensureAuthor(beaconId: beaconId, userId: authorUserId);
    if (BeaconCoordinationStatus.tryFromInt(status) == null) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.invalidCoordinationStatus,
      );
    }
    await _coordinationRepository.setBeaconCoordinationFields(
      beaconId: beaconId,
      coordinationStatus: status,
    );
    return true;
  }
}
