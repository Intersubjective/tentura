import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/image_entity.dart';
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
    Set<String>? tags,
    Set<String>? needs,
    int ticker = 0,
    String? iconCode,
    int? iconBackground,
    BeaconStatus? status,
    String? needSummary,
    String? successCriteria,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) async {
    final now = DateTime.timestamp();
    final beacon = BeaconEntity(
      id: BeaconEntity.newId,
      title: title,
      context: context,
      description: description ?? '',
      status: status ?? BeaconStatus.open,
      startAt: startAt,
      endAt: endAt,
      createdAt: now,
      updatedAt: now,
      author: UserEntity(id: authorId),
      lineageParentBeaconId: lineageParentBeaconId,
      lineageRootBeaconId: lineageRootBeaconId,
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
      needs: needs ?? const <String>{},
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
    Set<String>? needs,
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
        existing.status != BeaconStatus.draft ||
        existing.author.id != userId) {
      throw const BeaconCreateException(
        description: 'Beacon is not an editable draft',
      );
    }
    final now = DateTime.timestamp();
    final updated = existing.copyWith(
      title: title,
      description: description,
      context: context,
      tags: tags,
      needs: needs ?? const <String>{},
      startAt: startAt,
      endAt: endAt,
      coordinates: latitude != null && longitude != null
          ? Coordinates(lat: latitude, long: longitude)
          : null,
      iconCode: iconCode,
      iconBackground: iconBackground,
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
    Set<String>? needs,
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
        (!existing.status.isOpenFamily &&
            existing.status != BeaconStatus.reviewOpen) ||
        existing.author.id != userId) {
      throw const BeaconCreateException(
        description: 'Only open or wrapping-up beacons can be edited',
      );
    }
    final updated = existing.copyWith(
      title: title,
      description: description,
      context: context,
      tags: tags,
      needs: needs ?? const <String>{},
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
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) async {
    final locked = await getBeaconById(beaconId: beaconId);
    return fn(locked);
  }

  @override
  Future<void> recordBeaconStatusTransition({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    required String? actorId,
  }) async {
    final b = storageById[beaconId];
    if (b != null) {
      storageById[beaconId] = b.copyWith(
        status: toStatus,
        statusChangedAt: DateTime.timestamp(),
      );
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

  @override
  Future<BeaconEntity> publishDraft({
    required String id,
    required String actorId,
  }) async {
    final b = storageById[id];
    if (b == null || b.author.id != actorId) {
      throw IdNotFoundException(id: id);
    }
    if (b.status == BeaconStatus.draft) {
      return storageById[id] = b.copyWith(
        status: BeaconStatus.open,
        updatedAt: DateTime.timestamp(),
      );
    }
    return b;
  }
}
