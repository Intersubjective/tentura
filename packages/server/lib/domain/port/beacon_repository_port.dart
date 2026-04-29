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
    ({String question, List<String> variants})? polling,
    Set<String>? tags,
    int ticker = 0,
    String? iconCode,
    int? iconBackground,
    int? state,
    String? needSummary,
    String? successCriteria,
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
    DateTime? startAt,
    DateTime? endAt,
    double? latitude,
    double? longitude,
    String? iconCode,
    int? iconBackground,
    ({String question, List<String> variants})? polling,
    String? needSummary,
    String? successCriteria,
  });

  /// Updates an OPEN (state 0) beacon owned by [userId].
  /// Throws if not found, not owned, or not in the OPEN state.
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
  });

  Future<void> deleteBeaconById(String id, {required String userId});

  Future<void> updateBeaconState({
    required String beaconId,
    required int state,
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

  Future<void> reorderImages({
    required String beaconId,
    required List<String> imageIds,
  });

  /// Author or steward only; updates `beacon.public_status` and optional note.
  Future<BeaconEntity> updatePublicStatus({
    required String beaconId,
    required String userId,
    required int publicStatus,
    String? lastPublicMeaningfulChange,
  });
}
