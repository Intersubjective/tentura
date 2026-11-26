enum PhantomPendingForwardState { pending, claimed, delivered, lapsed, offered }

typedef PhantomPendingForward = ({
  String id,
  String phantomId,
  String senderId,
  String beaconId,
  String? parentForwardEdgeId,
  String note,
  DateTime createdAt,
  PhantomPendingForwardState state,
  String? mergeId,
  String? recipientId,
  String? forwardEdgeId,
  String? lapseReason,
  DateTime? resolvedAt,
});
