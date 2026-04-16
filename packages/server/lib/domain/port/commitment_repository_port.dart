import 'package:tentura_server/domain/entity/commitment_entity.dart';

abstract class CommitmentRepositoryPort {
  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    String? helpType,
    int status = 0,
  });

  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String uncommitReason,
    String message = '',
  });

  Future<List<CommitmentEntity>> fetchByBeaconId(String beaconId);

  Future<List<CommitmentEntity>> fetchAllByBeaconId(String beaconId);

  Future<List<CommitmentEntity>> fetchByUserId(String userId);

  Future<bool> hasActiveCommitment({
    required String beaconId,
    required String userId,
  });
}
