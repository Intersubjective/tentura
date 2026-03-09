import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';

import '../beacon_repository.dart';
import 'data/beacons.dart';

@Injectable(
  as: BeaconRepository,
  env: [Environment.test],
  order: 1,
)
class BeaconRepositoryMock implements BeaconRepository {
  static final storageById = <String, BeaconEntity>{...kBeaconById};

  const BeaconRepositoryMock();

  @override
  Future<BeaconEntity> createBeacon({
    required String authorId,
    required String title,
    String? description,
    String? context,
    String? imageId,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    ({String question, List<String> variants})? polling,
    Set<String>? tags,
    int ticker = 0,
  }) async {
    final now = DateTime.timestamp();
    final beacon = BeaconEntity(
      id: BeaconEntity.newId,
      title: title,
      context: context,
      description: description ?? '',
      startAt: startAt,
      endAt: endAt,
      createdAt: now,
      updatedAt: now,
      author: UserEntity(id: authorId),
      coordinates: latitude != null && longitude != null
          ? Coordinates(lat: latitude, long: longitude)
          : null,
      image: imageId == null
          ? null
          : ImageEntity(
              id: imageId,
              authorId: authorId,
            ),
      tags: tags,
    );
    return storageById[beacon.id] = beacon;
  }

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    final beacon =
        storageById[beaconId] ?? (throw IdNotFoundException(id: beaconId));
    if (filterByUserId != null && beacon.author.id != filterByUserId) {
      throw IdNotFoundException(id: beaconId);
    }
    return beacon;
  }

  @override
  Future<void> deleteBeaconById(String id) async =>
      storageById.removeWhere((key, value) => value.id == id);
}
