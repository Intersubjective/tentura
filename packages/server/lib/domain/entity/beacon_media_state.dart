import 'package:meta/meta.dart';

/// Attached-plus-staged media state for one beacon, read under its row lock.
@immutable
class BeaconMediaSnapshot {
  const BeaconMediaSnapshot({
    required this.attachedImageIds,
    required this.stagedImageIds,
  });

  /// Attached `beacon_image` ids, ordered by `position`.
  final List<String> attachedImageIds;

  /// This beacon's invisible staged image ids.
  final Set<String> stagedImageIds;

  int get combinedCount => attachedImageIds.length + stagedImageIds.length;
}

/// One `beacon_image_stage` row joined with its beacon's author, used by the
/// stage-expiry sweep.
@immutable
class BeaconStageRow {
  const BeaconStageRow({
    required this.beaconId,
    required this.imageId,
    required this.authorId,
    required this.stagedAt,
  });

  final String beaconId;
  final String imageId;
  final String authorId;
  final DateTime stagedAt;
}
