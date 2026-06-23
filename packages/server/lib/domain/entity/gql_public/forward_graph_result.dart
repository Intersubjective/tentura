import 'package:meta/meta.dart';

/// One forward edge in the V2 forwards-graph view (GraphQL `ForwardGraphEdge`).
@immutable
class ForwardGraphEdgeResult {
  const ForwardGraphEdgeResult({
    required this.id,
    required this.beaconId,
    required this.senderId,
    required this.recipientId,
    this.parentEdgeId,
    this.batchId,
  });

  final String id;
  final String beaconId;
  final String senderId;
  final String recipientId;
  final String? parentEdgeId;
  final String? batchId;
}

/// Result of `beaconForwardGraph` / `beaconHelpOffererForwardPath`
/// (GraphQL `ForwardGraphResult`).
@immutable
class ForwardGraphResult {
  const ForwardGraphResult({
    required this.beaconId,
    required this.authorId,
    required this.helpOffererIds,
    required this.edges,
    this.viewerId,
  });

  final String beaconId;
  final String authorId;
  final String? viewerId;
  final List<String> helpOffererIds;
  final List<ForwardGraphEdgeResult> edges;
}
