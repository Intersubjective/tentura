import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/exception.dart';

/// Resolves provenance for an outbound forward from [senderId].
///
/// When [clientParentEdgeId] is supplied it must reference an active inbound
/// edge on the same beacon whose recipient is [senderId]. Otherwise, when the
/// sender has inbound edges, prefer a direct author→sender hop, else the most
/// recent active inbound edge. Author / mutual-first-hop senders with no inbound
/// edge use `null`.
String? resolveForwardParentEdgeId({
  required String? clientParentEdgeId,
  required List<ForwardEdgeEntity> activeInboundEdges,
  required String senderId,
  required String authorId,
}) {
  if (clientParentEdgeId != null) {
    final match = activeInboundEdges.where(
      (e) => e.id == clientParentEdgeId && e.recipientId == senderId,
    );
    if (match.isEmpty) {
      throw const UnauthorizedException(
        description: 'Invalid parent forward edge for sender',
      );
    }
    return clientParentEdgeId;
  }

  if (activeInboundEdges.isEmpty) {
    return null;
  }

  final authorDirect = activeInboundEdges.where(
    (e) => e.senderId == authorId && e.recipientId == senderId,
  );
  if (authorDirect.isNotEmpty) {
    return authorDirect.first.id;
  }

  return activeInboundEdges.first.id;
}
