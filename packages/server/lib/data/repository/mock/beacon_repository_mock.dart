import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/polling_entity.dart';
import 'package:tentura_server/domain/entity/polling_variant_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

import 'data/beacons.dart';

@Injectable(
  as: BeaconRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class BeaconRepositoryMock implements BeaconRepositoryPort {
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
    String? iconCode,
    int? iconBackground,
    int? state,
    String? needSummary,
    String? successCriteria,
  }) async {
    final now = DateTime.timestamp();
    final beacon = BeaconEntity(
      id: BeaconEntity.newId,
      title: title,
      context: context,
      description: description ?? '',
      state: state ?? 0,
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
      iconCode: iconCode,
      iconBackground: iconBackground,
      needSummary: needSummary,
      successCriteria: successCriteria,
    );
    return storageById[beacon.id] = beacon;
  }

  @override
  Future<BeaconEntity> updateDraftBeacon({
    required String beaconId,
    required String userId,
    required String title,
    required String description,
    String? context,
    Set<String>? tags,
    DateTime? startAt,
    DateTime? endAt,
    double? latitude,
    double? longitude,
    String? iconCode,
    int? iconBackground,
    ({String question, List<String> variants})? polling,
    String? needSummary,
    String? successCriteria,
  }) async {
    final existing = storageById[beaconId];
    if (existing == null ||
        existing.state != 3 ||
        existing.author.id != userId) {
      throw const BeaconCreateException(
        description: 'Beacon is not an editable draft',
      );
    }
    final now = DateTime.timestamp();
    var pollingEntity = existing.polling;
    if (polling != null) {
      final pid = PollingEntity.newId;
      pollingEntity = PollingEntity(
        id: pid,
        question: polling.question,
        author: existing.author,
        createdAt: now,
        updatedAt: now,
        variants: [
          for (var i = 0; i < polling.variants.length; i++)
            PollingVariantEntity(
              id: PollingVariantEntity.newId,
              pollingId: pid,
              description: polling.variants[i],
            ),
        ],
      );
    }
    final updated = existing.copyWith(
      title: title,
      description: description,
      context: context,
      tags: tags,
      startAt: startAt,
      endAt: endAt,
      coordinates: latitude != null && longitude != null
          ? Coordinates(lat: latitude, long: longitude)
          : null,
      iconCode: iconCode,
      iconBackground: iconBackground,
      polling: pollingEntity,
      updatedAt: now,
      needSummary: needSummary,
      successCriteria: successCriteria,
    );
    return storageById[beaconId] = updated;
  }

  @override
  Future<BeaconEntity> updateBeacon({
    required String beaconId,
    required String userId,
    required String title,
    required String description,
    String? context,
    Set<String>? tags,
    DateTime? startAt,
    DateTime? endAt,
    double? latitude,
    double? longitude,
    String? iconCode,
    int? iconBackground,
    String? needSummary,
    String? successCriteria,
  }) async {
    final existing = storageById[beaconId];
    if (existing == null ||
        existing.state != 0 ||
        existing.author.id != userId) {
      throw const BeaconCreateException(
        description: 'Only open beacons can be edited',
      );
    }
    final updated = existing.copyWith(
      title: title,
      description: description,
      context: context,
      tags: tags,
      startAt: startAt,
      endAt: endAt,
      coordinates: latitude != null && longitude != null
          ? Coordinates(lat: latitude, long: longitude)
          : null,
      iconCode: iconCode,
      iconBackground: iconBackground,
      updatedAt: DateTime.timestamp(),
      needSummary: needSummary,
      successCriteria: successCriteria,
    );
    return storageById[beaconId] = updated;
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
