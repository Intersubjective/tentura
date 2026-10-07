import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/post_summary.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_media_state.dart';

abstract class BeaconRepositoryPort {
  /// Open Post conversations visible to this viewer.
  Future<List<PostSummary>> myPosts(String viewerId);

  /// The viewer's conversation row for one Post; null when the viewer is not
  /// in it (left, not admitted, or the Post is gone).
  Future<PostSummary?> postSummary({
    required String viewerId,
    required String beaconId,
  });

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
    String? primaryNeedSlug,
    String? coverImageId,
    BeaconCoverSource coverSource = BeaconCoverSource.photo,
    BeaconStatus? status,
    String? addressLabel,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
    bool? isDiscoverable,
    BeaconKind kind = BeaconKind.request,
    BeaconForwardPolicyValue forwardPolicy = BeaconForwardPolicyValue.open,
    String? clientOpId,
  });

  /// Creates a nested child beacon with immutable [parentBeaconId].
  ///
  /// Draft children keep [publishedAt] null; direct publication sets it.
  Future<BeaconEntity> createChildBeacon({
    required String authorId,
    required String parentBeaconId,
    required String title,
    required String description,
    String? context,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    Set<String>? tags,
    Set<String>? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    required bool draft,
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
    String? primaryNeedSlug,
    String? addressLabel,
    bool? isDiscoverable,
    bool isDiscoverableProvided = false,
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
    String? primaryNeedSlug,
    String? addressLabel,
    bool? isDiscoverable,
    bool isDiscoverableProvided = false,
  });

  Future<void> deleteBeaconById(String id, {required String userId});

  Future<List<String>> deadlineReminderCandidateIds({
    required DateTime nextUtcDayStart,
    required DateTime followingUtcDayStart,
  });
  Future<BeaconEntity?> lockOpenBeaconForDeadlineReminder({
    required String beaconId,
    required DateTime nextUtcDayStart,
    required DateTime followingUtcDayStart,
  });

  /// Row-lock beacon and run [fn] with the locked entity snapshot.
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  });

  /// Takes the Post lock sequence (see `PostLockPort`) for [beaconId]; must run
  /// inside the caller's transaction.
  Future<void> lockPostForMutation(String beaconId);

  /// Sets `beacon.forward_policy`; the caller holds the beacon row lock.
  Future<void> setForwardPolicy({
    required String beaconId,
    required BeaconForwardPolicyValue policy,
  });

  /// Turns an open Post into an open-forwarding Request in one `UPDATE` (the
  /// Post shape CHECK forbids writing content before `kind` flips); throws
  /// `BeaconCreateException` unless exactly one open Post row was updated.
  Future<void> convertPostToRequest({
    required String beaconId,
    required String title,
    required String description,
    required Set<String>? needs,
    required String? primaryNeedSlug,
    required DateTime? startAt,
    required DateTime? endAt,
    required bool isDiscoverable,
  });

  /// Post addressees other than the author or stewards; caller holds Post lock.
  Future<List<String>> postMemberUserIds(String beaconId);

  /// Admits selected members and removes the rest after the kind change, in
  /// the caller's conversion transaction.
  Future<void> convertPostMembers({
    required String beaconId,
    required String authorId,
    required Set<String> helperIds,
  });

  /// Inserts the kind-4 system message announcing a Post's conversion.
  Future<void> postConvertedToRequestMessage(String beaconId);

  /// Sets `beacon.post_root_message_id` once; a no-op when already set.
  Future<void> setPostRootMessage({
    required String beaconId,
    required String messageId,
  });

  /// Whether [userId] is an addressee (`role 6`) of [beaconId] other than its
  /// author; the caller holds the Post lock.
  Future<bool> isPostAddressee({
    required String beaconId,
    required String userId,
  });

  /// An addressee steps out: inbox row rejected (declining a pending contact
  /// edge) and `room_access` set to left.
  Future<void> leavePostAsAddressee({
    required String beaconId,
    required String userId,
  });

  /// An addressee comes back: inbox row back to watching and room access
  /// reconciled from the live forward edges (set directly for a Request).
  Future<void> returnToPostAsAddressee({
    required String beaconId,
    required String userId,
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

  /// Publishes a nested child draft: sets status/open, [publishedAt], activity.
  Future<BeaconEntity> publishChildDraft({
    required String childBeaconId,
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
    String? coverThumbImageId,
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

  Future<int> reviewReopenCount(String beaconId);

  Future<void> incrementReviewReopenCount(String beaconId);
}
