import 'package:meta/meta.dart';

/// Result of beacon lifecycle mutations that expose id/status/closesAt
/// (GraphQL `BeaconCloseReviewResult`).
@immutable
class BeaconCloseReviewResult {
  const BeaconCloseReviewResult({
    required this.id,
    required this.status,
    this.closesAt,
  });

  final String id;
  final int status;
  final DateTime? closesAt;
}
