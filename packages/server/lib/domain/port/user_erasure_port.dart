import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Persistence helpers for the account-erasure transaction (§4.5).
abstract class UserErasurePort {
  /// Published, non-draft beacons owned by [userId], ordered by id.
  Future<List<OwnedPublishedBeaconRow>> listOwnedPublishedBeacons({
    required String userId,
  });

  /// Private draft beacon ids owned by [userId], ordered by id.
  Future<List<String>> listOwnedDraftBeaconIds({required String userId});

  /// Clears personal content/media metadata on an owned published row already
  /// transitioned to deleted. Returns image ids whose rows were removed and
  /// must be GC-enqueued only after the surrounding transaction commits.
  Future<List<String>> scrubDeletedOwnedBeaconContent({
    required String beaconId,
    required String ownerId,
  });

  /// Hard-deletes a private draft and dependent rows. Returns image ids for
  /// post-commit GC enqueue (same contract as [scrubDeletedOwnedBeaconContent]).
  Future<List<String>> hardDeleteOwnedDraftBeacon({
    required String beaconId,
    required String ownerId,
  });

  /// Deletes user-scoped evaluation, subjective ack, and capability-event rows
  /// that must be scrubbed before the account row is removed.
  Future<void> deleteUserScopedEvaluationAndCapabilityRows({
    required String userId,
  });

  /// Removes ordinary (non-system) room messages authored by [userId]. System
  /// hierarchy notices keep their rows and rely on `author_id` SET NULL.
  Future<void> deleteOrdinaryRoomMessagesAuthoredByUser({
    required String userId,
  });

  /// Deletes every image row authored by [userId]. Returns ids for post-commit GC.
  Future<List<String>> deleteOwnedImageRows({required String userId});
}

final class OwnedPublishedBeaconRow {
  const OwnedPublishedBeaconRow({
    required this.beaconId,
    required this.status,
  });

  final String beaconId;
  final BeaconStatus status;
}
