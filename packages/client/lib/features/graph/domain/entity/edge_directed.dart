import 'package:tentura/features/forward/domain/entity/forward_recipient_offer_status.dart';

import 'node_details.dart';

enum GenealogyEdgeBranch { ego, target, neutral }

/// One directed edge for the graph view.
///
/// `node` is an optional payload describing the destination node (the source
/// node is resolved from a separate index in the cubit). When `node` is
/// `null`, the cubit lazy-fetches the destination using the id prefix
/// (`U` -> profile, `B` -> beacon).
///
/// Forwards graph: [forwardEdgeId] and the `forward*` fields carry V2 forward
/// edge payload so the cubit can draw every edge with distinct identity and
/// per-recipient markers. [forwardRecipientIsGhostEndpoint] is true when the
/// server hid this endpoint behind an anonymous/blocked count (`Ufg:` ids).
typedef EdgeDirected = ({
  String src,
  String dst,
  double weight,
  NodeDetails? node,
  GenealogyEdgeBranch? branch,
  int? srcTotalNeighborCount,
  int? dstTotalNeighborCount,
  String? forwardEdgeId,
  bool? forwardRecipientIsGhostEndpoint,
  ForwardRecipientOfferStatus? forwardOfferStatus,
  bool? forwardDeclinedInvite,
  DateTime? forwardReadAt,
  bool? forwardForwardedOn,
  int? forwardSenderAnonymousCount,
  int? forwardRecipientAnonymousCount,
  String? forwardParentEdgeId,
});
