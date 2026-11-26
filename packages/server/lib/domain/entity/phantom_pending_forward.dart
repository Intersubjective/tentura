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

/// The immutable identity and lock targets returned by claiming a forward.
typedef PhantomForwardClaim = ({
  String id,
  String senderId,
  String beaconId,
  String? parentForwardEdgeId,
  String mergeId,
});

typedef PhantomForwardDelivery = ({String recipientId, String note});

sealed class PhantomForwardResolution {
  const PhantomForwardResolution();
}

final class PhantomForwardDelivered extends PhantomForwardResolution {
  const PhantomForwardDelivered(this.edgeId);

  final String edgeId;
}

enum PhantomForwardLapsed implements PhantomForwardResolution {
  forwardNoLongerAllowed('forward_no_longer_allowed'),
  parentUnavailable('parent_unavailable'),
  recipientPaused('recipient_paused');

  const PhantomForwardLapsed(this.reason);

  final String reason;
}
