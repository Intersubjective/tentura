import 'package:meta/meta.dart';

import '../forward_tree_edge.dart';
import '../help_path_node.dart';

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

/// An edge of the whole forward tree served by `beaconForwardGraph`, with
/// both ends as person nodes and the recipient's states. [readAt] and
/// [declinedInvite] are null unless the viewer is the author or the sender
/// of this edge.
@immutable
class ForwardTreeEdgeResult extends ForwardGraphEdgeResult {
  const ForwardTreeEdgeResult({
    required super.id,
    required super.beaconId,
    required super.senderId,
    required super.recipientId,
    required this.createdAt,
    required this.sender,
    required this.recipient,
    required this.forwardedOn,
    required this.offerStatus,
    super.parentEdgeId,
    super.batchId,
    this.readAt,
    this.declinedInvite,
  });

  final DateTime createdAt;
  final HelpPathNode sender;
  final HelpPathNode recipient;

  /// The recipient forwarded the beacon on (has live child edges).
  final bool forwardedOn;
  final ForwardRecipientOfferStatus offerStatus;
  final DateTime? readAt;
  final bool? declinedInvite;
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
    this.path = const [],
  });

  final String beaconId;
  final String authorId;
  final String? viewerId;
  final List<String> helpOffererIds;
  final List<ForwardGraphEdgeResult> edges;
  final List<HelpPathNode> path;
}
