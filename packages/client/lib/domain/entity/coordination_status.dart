/// Beacon-level coordination (`beacon.coordination_status` smallint).
enum BeaconCoordinationStatus {
  neutral(0),
  moreOrDifferentHelpNeeded(2),
  enoughHelpOffered(3);

  const BeaconCoordinationStatus(this.smallintValue);

  final int smallintValue;

  static BeaconCoordinationStatus fromSmallint(int v) => switch (v) {
        0 => neutral,
        1 => neutral, // ACL: legacy auto-derived value during migration rollout
        2 => moreOrDifferentHelpNeeded,
        3 => enoughHelpOffered,
        _ => neutral,
      };
}
