import 'package:meta/meta.dart';

/// Result of `beaconCancel` (GraphQL `BeaconCancelResult`).
@immutable
class BeaconCancelResult {
  const BeaconCancelResult({
    required this.id,
    required this.status,
  });

  final String id;
  final int status;
}
