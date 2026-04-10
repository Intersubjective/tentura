sealed class CommitmentEvent {
  const CommitmentEvent(this.beaconId);

  final String beaconId;
}

final class CommitmentCreated extends CommitmentEvent {
  const CommitmentCreated(super.beaconId);
}

final class CommitmentWithdrawn extends CommitmentEvent {
  const CommitmentWithdrawn(super.beaconId);
}

/// Server-pushed invalidation: commitments for [beaconId] changed externally.
final class CommitmentInvalidated extends CommitmentEvent {
  const CommitmentInvalidated(super.beaconId);
}
