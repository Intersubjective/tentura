/// Beacon-level coordination (`beacon.coordination_status` smallint).
enum BeaconCoordinationStatus {
  noHelpOffersYet(0),
  helpOffersWaitingForReview(1),
  moreOrDifferentHelpNeeded(2),
  enoughHelpOffered(3);

  const BeaconCoordinationStatus(this.smallintValue);

  final int smallintValue;

  static BeaconCoordinationStatus fromSmallint(int v) => switch (v) {
        0 => noHelpOffersYet,
        1 => helpOffersWaitingForReview,
        2 => moreOrDifferentHelpNeeded,
        3 => enoughHelpOffered,
        _ => noHelpOffersYet,
      };
}
