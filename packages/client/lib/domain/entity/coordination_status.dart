/// Beacon-level coordination (`beacon.coordination_status` smallint).
enum BeaconCoordinationStatus {
  noCommitmentsYet(0),
  commitmentsWaitingForReview(1),
  moreOrDifferentHelpNeeded(2),
  enoughHelpCommitted(3);

  const BeaconCoordinationStatus(this.smallintValue);

  final int smallintValue;

  static BeaconCoordinationStatus fromSmallint(int v) => switch (v) {
        0 => noCommitmentsYet,
        1 => commitmentsWaitingForReview,
        2 => moreOrDifferentHelpNeeded,
        3 => enoughHelpCommitted,
        _ => noCommitmentsYet,
      };
}
