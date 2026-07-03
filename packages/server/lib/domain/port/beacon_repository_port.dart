import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';

abstract class BeaconRepositoryPort {
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
    String? addressLabel,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  });

  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  });

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
    String? addressLabel,
  });

  /// Updates an open-family or reviewOpen beacon owned by [userId].
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
    String? addressLabel,
  });

  Future<void> deleteBeaconById(String id, {required String userId});

  /// Row-lock beacon and run [fn] with the locked entity snapshot.
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  });

  /// Atomically updates beacon status and inserts a status activity log row.
  Future<void> recordBeaconStatusTransition({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    required String? actorId,
  });

  Future<void> addImage({
    required String beaconId,
    required String imageId,
    required int position,
  });

  Future<void> removeImage({
    required String beaconId,
    required String imageId,
  });

  Future<int> getImageCount(String beaconId);

  /// Count beacons created by [userId] within the trailing [window]
  /// (spam-control rate limiting; counts drafts and published rows alike).
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  });

  Future<void> reorderImages({
    required String beaconId,
    required List<String> imageIds,
  });

  /// Draft → open and emit a `beaconPublished` activity event.
  Future<BeaconEntity> publishDraft({
    required String id,
    required String actorId,
  });
}
