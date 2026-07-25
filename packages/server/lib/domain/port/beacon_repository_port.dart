import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_media_state.dart';

abstract class BeaconRepositoryPort {
  /// Creates the beacon row, attaches [imageIds] in order, then sets the
  /// cover last in the same transaction (so the composite membership FK sees
  /// the attachment row first). [coverImageId] must be a member of
  /// [imageIds] when given; when null and [imageIds] is non-empty, the first
  /// image becomes cover.
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
    String? primaryNeedSlug,
    String? coverImageId,
    BeaconCoverSource coverSource = BeaconCoverSource.photo,
    BeaconStatus? status,
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
    String? primaryNeedSlug,
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
    String? primaryNeedSlug,
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

  /// Attached (position-ordered) plus this beacon's staged image ids, read
  /// under the caller's already-held row lock.
  Future<BeaconMediaSnapshot> getMediaSnapshot(String beaconId);

  /// Inserts an invisible stage row; the image is not visible to any reader
  /// until [replaceMedia] promotes it.
  Future<void> insertStage({
    required String beaconId,
    required String imageId,
  });

  /// Deletes a stage row for [imageId] (no-op if absent).
  Future<void> deleteStage({required String imageId});

  /// Reconciles attached media to exactly [imageIds] in that order (promoting
  /// any of them still in the stage table), then sets `cover_image_id` /
  /// `cover_source` last. Returns every image id whose row must now be
  /// deleted: attachments omitted from [imageIds] and stages omitted from
  /// [imageIds]. Callers enqueue GC and delete those rows in the same
  /// transaction as this call.
  Future<List<String>> replaceMedia({
    required String beaconId,
    required List<String> imageIds,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
  });

  /// Sets cover fields directly (legacy add/remove paths that do not run a
  /// full reconciliation).
  Future<void> setCover({
    required String beaconId,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
  });

  /// Stage rows created at or before [olderThan], joined with their beacon's
  /// author, for the 24-hour expiry sweep.
  Future<List<BeaconStageRow>> staleStages({
    required DateTime olderThan,
    int limit = 100,
  });
}
