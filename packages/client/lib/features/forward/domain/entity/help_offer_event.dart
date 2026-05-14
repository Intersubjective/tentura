sealed class HelpOfferEvent {
  const HelpOfferEvent(this.beaconId);

  final String beaconId;
}

final class HelpOfferCreated extends HelpOfferEvent {
  const HelpOfferCreated(super.beaconId);
}

final class HelpOfferWithdrawn extends HelpOfferEvent {
  const HelpOfferWithdrawn(super.beaconId);
}

/// Server-pushed invalidation: help offers for [beaconId] changed externally.
final class HelpOfferInvalidated extends HelpOfferEvent {
  const HelpOfferInvalidated(super.beaconId);
}
