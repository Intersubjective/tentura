import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/domain/coordination/help_type.dart';
import 'package:tentura_server/domain/coordination/uncommit_reason.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

@Singleton(order: 2)
class CommitmentCase {
  const CommitmentCase(
    this._commitmentRepository,
    this._beaconRepository,
    this._coordinationRepository,
  );

  final CommitmentRepository _commitmentRepository;
  final BeaconRepository _beaconRepository;
  final CoordinationRepository _coordinationRepository;

  Future<void> commit({
    required String beaconId,
    required String userId,
    String message = '',
    String? helpType,
  }) async {
    if (!isAllowedHelpType(helpType)) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.invalidHelpType,
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.state != 0) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.beaconNotOpen,
      );
    }
    await _commitmentRepository.upsert(
      beaconId: beaconId,
      userId: userId,
      message: message,
      helpType: helpType,
      status: 0,
    );
    await _coordinationRepository.recomputeAndPersistBeaconCoordinationStatus(
      beaconId,
    );
  }

  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String uncommitReason,
    String message = '',
  }) async {
    if (!isAllowedUncommitReason(uncommitReason)) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.invalidUncommitReason,
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.state != 0) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.beaconNotOpen,
      );
    }
    await _coordinationRepository.deleteForCommit(
      beaconId: beaconId,
      userId: userId,
    );
    await _commitmentRepository.withdraw(
      beaconId: beaconId,
      userId: userId,
      message: message,
      uncommitReason: uncommitReason,
    );
    await _coordinationRepository.recomputeAndPersistBeaconCoordinationStatus(
      beaconId,
    );
  }
}
