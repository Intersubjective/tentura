import 'package:tentura_server/domain/entity/beacon_update_entity.dart';

abstract class BeaconUpdateRepositoryPort {
  Future<BeaconUpdateEntity> createUpdate({
    required String beaconId,
    required String authorId,
    required String content,
  });

  Future<BeaconUpdateEntity> editUpdate({
    required String id,
    required String authorId,
    required String content,
  });

  Future<BeaconUpdateEntity?> getById(String id);

  Future<List<BeaconUpdateEntity>> fetchByBeaconId(String beaconId);
}
