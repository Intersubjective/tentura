/// Beacon-level coordination (`beacon.coordination_status`).
enum BeaconCoordinationStatus {
  neutral(0),
  moreOrDifferentHelpNeeded(2),
  enoughHelpOffered(3);

  const BeaconCoordinationStatus(this.smallintValue);

  final int smallintValue;

  static BeaconCoordinationStatus? tryFromInt(int v) => switch (v) {
        0 => neutral,
        2 => moreOrDifferentHelpNeeded,
        3 => enoughHelpOffered,
        _ => null,
      };
}
