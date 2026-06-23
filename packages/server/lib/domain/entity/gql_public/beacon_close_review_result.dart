import 'package:meta/meta.dart';

/// Result of beacon lifecycle mutations that expose id/state/closesAt
/// (GraphQL `BeaconCloseReviewResult`).
@immutable
class BeaconCloseReviewResult {
  const BeaconCloseReviewResult({
    required this.id,
    required this.state,
    this.closesAt,
  });

  final String id;
  final int state;
  final DateTime? closesAt;
}
