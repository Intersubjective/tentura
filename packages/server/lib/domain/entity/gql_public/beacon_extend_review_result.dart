import 'package:meta/meta.dart';

/// Result of extending an open Request review window.
@immutable
class BeaconExtendReviewResult {
  const BeaconExtendReviewResult({
    required this.id,
    required this.closesAt,
    required this.extensionsRemaining,
  });

  final String id;
  final DateTime closesAt;
  final int extensionsRemaining;
}
