enum PhantomPendingForwardState { pending, claimed, delivered, lapsed, offered }

enum PhantomForwardDeliverySource {
  inviteClaim(PhantomPendingForwardState.claimed),
  manualOffer(PhantomPendingForwardState.offered);

  const PhantomForwardDeliverySource(this.state);

  final PhantomPendingForwardState state;
}

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
  String? mergeId,
});

sealed class PhantomForwardClaimTarget {
  const PhantomForwardClaimTarget();
}

final class PhantomForwardDelivery extends PhantomForwardClaimTarget {
  const PhantomForwardDelivery({required this.recipientId, required this.note});

  final String recipientId;
  final String note;
}

final class PhantomForwardRecipientGone extends PhantomForwardClaimTarget {
  const PhantomForwardRecipientGone();
}

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
  recipientPaused('recipient_paused'),
  recipientGone('recipient_gone');

  const PhantomForwardLapsed(this.reason);

  final String reason;
}
