import 'package:meta/meta.dart';

/// Result of `beaconStageImage` (GraphQL `v2_BeaconImageStaged`). The staged
/// image is invisible to every reader until `beaconSetMedia` publishes it.
@immutable
class BeaconImageStagedResult {
  const BeaconImageStagedResult({
    required this.imageId,
    required this.beaconId,
  });

  final String imageId;
  final String beaconId;
}
