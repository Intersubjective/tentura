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
    List<String>? imageIds,
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
      images: [
        if (imageIds != null)
          for (final imageId in imageIds)
            ImageEntity(
              id: imageId,
              authorId: authorId,
              createdAt: DateTime.utc(2020),
            ),
      ],
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
  Future<void> deleteBeaconById(String id, {required String userId}) async =>
      storageById.removeWhere((key, value) => value.id == id);

  @override
  Future<void> updateBeaconState({
    required String beaconId,
    required int state,
  }) async {
    final b = storageById[beaconId];
    if (b != null) {
      storageById[beaconId] = b.copyWith(state: state);
    }
  }

  @override
  Future<void> addImage({
    required String beaconId,
    required String imageId,
    required int position,
  }) async {
    final b = storageById[beaconId];
    if (b != null) {
      storageById[beaconId] = b.copyWith(
        images: [
          ...b.images,
          ImageEntity(
            id: imageId,
            authorId: b.author.id,
            createdAt: DateTime.timestamp(),
          ),
        ],
      );
    }
  }

  @override
  Future<void> removeImage({
    required String beaconId,
    required String imageId,
  }) async {
    final b = storageById[beaconId];
    if (b != null) {
      storageById[beaconId] = b.copyWith(
        images: b.images.where((i) => i.id != imageId).toList(),
      );
    }
  }

  @override
  Future<int> getImageCount(String beaconId) async {
    final b = storageById[beaconId];
    return b?.images.length ?? 0;
  }

  @override
  Future<void> reorderImages({
    required String beaconId,
    required List<String> imageIds,
  }) async {}
}
