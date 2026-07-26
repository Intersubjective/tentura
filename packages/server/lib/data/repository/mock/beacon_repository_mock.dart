import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_media_state.dart';
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

  /// beaconId -> imageId -> stagedAt (mock outbox for `beaconStageImage`).
  static final stagesByBeaconId = <String, Map<String, DateTime>>{};

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
    String? primaryNeedSlug,
    String? coverImageId,
    BeaconCoverSource coverSource = BeaconCoverSource.photo,
    BeaconStatus? status,
    String? addressLabel,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) async {
    final now = DateTime.timestamp();
    final images = [
      if (imageIds != null)
        for (final imageId in imageIds)
          ImageEntity(
            id: imageId,
            authorId: authorId,
            createdAt: DateTime.utc(2020),
          ),
    ];
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
      images: images,
      tags: tags,
      needs: needs ?? const <String>{},
      primaryNeedSlug: primaryNeedSlug,
      coverImageId: images.isEmpty ? null : (coverImageId ?? images.first.id),
      coverSource: coverSource,
      addressLabel: addressLabel,
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
    String? primaryNeedSlug,
    String? addressLabel,
  }) async {
    final existing = storageById[beaconId];
    if (existing == null ||
        existing.status != BeaconStatus.draft ||
        existing.author.id != userId) {
      throw const BeaconCreateException(
        description: 'Request is not an editable draft',
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
      primaryNeedSlug: primaryNeedSlug,
      updatedAt: now,
      addressLabel: addressLabel,
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
    String? primaryNeedSlug,
    String? addressLabel,
  }) async {
    final existing = storageById[beaconId];
    if (existing == null ||
        (!existing.status.isOpenFamily &&
            existing.status != BeaconStatus.reviewOpen) ||
        existing.author.id != userId) {
      throw const BeaconCreateException(
        description: 'Only open or wrapping-up requests can be edited',
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
      primaryNeedSlug: primaryNeedSlug,
      updatedAt: DateTime.timestamp(),
      addressLabel: addressLabel,
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
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async => 0;

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

  @override
  Future<BeaconMediaSnapshot> getMediaSnapshot(String beaconId) async {
    final b = storageById[beaconId];
    return BeaconMediaSnapshot(
      attachedImageIds: [
        for (final image in b?.images ?? const <ImageEntity>[]) image.id,
      ],
      stagedImageIds: {...?stagesByBeaconId[beaconId]?.keys},
    );
  }

  @override
  Future<void> insertStage({
    required String beaconId,
    required String imageId,
  }) async {
    (stagesByBeaconId[beaconId] ??= {})[imageId] = DateTime.timestamp();
  }

  @override
  Future<void> deleteStage({required String imageId}) async {
    for (final stages in stagesByBeaconId.values) {
      stages.remove(imageId);
    }
  }

  @override
  Future<void> setCover({
    required String beaconId,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
  }) async {
    final b = storageById[beaconId];
    if (b != null) {
      storageById[beaconId] = b.copyWith(
        coverImageId: coverImageId,
        coverSource: coverSource,
      );
    }
  }

  @override
  Future<List<String>> replaceMedia({
    required String beaconId,
    required List<String> imageIds,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
    String? coverThumbImageId,
  }) async {
    final b = storageById[beaconId];
    if (b == null) return const [];
    final currentAttached = {for (final image in b.images) image.id: image};
    final staged = stagesByBeaconId[beaconId] ?? const <String, DateTime>{};
    final desired = imageIds.toSet();
    final removed = [
      ...currentAttached.keys.where((id) => !desired.contains(id)),
      ...staged.keys.where((id) => !desired.contains(id)),
    ];
    stagesByBeaconId[beaconId]?.removeWhere((id, _) => !desired.contains(id));
    storageById[beaconId] = b.copyWith(
      images: [
        for (final imageId in imageIds)
          currentAttached[imageId] ??
              ImageEntity(
                id: imageId,
                authorId: b.author.id,
                createdAt: DateTime.timestamp(),
              ),
      ],
      coverImageId: coverImageId,
      coverSource: coverSource,
      coverThumbImageId: coverThumbImageId,
    );
    return removed;
  }

  @override
  Future<List<BeaconStageRow>> staleStages({
    required DateTime olderThan,
    int limit = 100,
  }) async => [
    for (final entry in stagesByBeaconId.entries)
      for (final stage in entry.value.entries)
        if (!stage.value.isAfter(olderThan))
          BeaconStageRow(
            beaconId: entry.key,
            imageId: stage.key,
            authorId: storageById[entry.key]?.author.id ?? '',
            stagedAt: stage.value,
          ),
  ];
}
