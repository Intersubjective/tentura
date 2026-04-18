import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/coordination/beacon_coordination_status.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/gql_public/commitment_with_coordination_row.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class CoordinationCase extends UseCaseBase {
  CoordinationCase(
    this._beaconRepository,
    this._commitmentRepository,
    this._coordinationRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final CoordinationRepositoryPort _coordinationRepository;

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

  Future<List<CommitmentWithCoordinationRow>> commitmentsWithCoordination({
    required String beaconId,
  }) => _coordinationRepository.commitmentsWithCoordination(beaconId);

  // TODO(contract): Phase-2 DTO migration — replace Map return with typed DTO at resolver boundary.
  // ignore: no_map_dynamic_in_use_case_api
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
