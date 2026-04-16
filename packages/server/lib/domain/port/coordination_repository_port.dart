import 'package:tentura_server/domain/entity/gql_public/commitment_with_coordination_row.dart';

abstract class CoordinationRepositoryPort {
  Future<void> deleteForCommit({
    required String beaconId,
    required String userId,
  });

  Future<void> upsertResponse({
    required String beaconId,
    required String commitUserId,
    required String authorUserId,
    required int responseType,
  });

  Future<({int coordinationStatus, DateTime? coordinationStatusUpdatedAt})>
      beaconCoordinationSnapshot(String beaconId);

  Future<void> setBeaconCoordinationFields({
    required String beaconId,
    required int coordinationStatus,
  });

  Future<void> recomputeAndPersistBeaconCoordinationStatus(String beaconId);

  Future<List<CommitmentWithCoordinationRow>> commitmentsWithCoordination(
    String beaconId,
  );
}
