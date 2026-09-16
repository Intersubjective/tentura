/// Viewer's access level to one request (issue #146 architecture §2.1).
enum BeaconAccessLevel {
  author(0),
  member(1),
  observer(2),
  stranger(3);

  const BeaconAccessLevel(this.value);
  final int value;

  static BeaconAccessLevel fromInt(int? v) => switch (v) {
    0 => author,
    1 => member,
    2 => observer,
    _ => stranger,
  };

  bool get canReadContent => value <= 2;
  bool get isMember => value <= 1;
}

/// Why the viewer has access. Bit values are persisted contracts (never renumber).
enum BeaconAccessReason {
  author(1),
  steward(2),
  admitted(4),
  forwarded(8),
  applied(16),
  discovered(32),
  contextChild(64),
  contextAncestor(128);

  const BeaconAccessReason(this.bit);
  final int bit;

  static Set<BeaconAccessReason> decode(int mask) =>
      {for (final r in values) if (mask & r.bit != 0) r};

  static int encode(Iterable<BeaconAccessReason> reasons) =>
      reasons.fold(0, (m, r) => m | r.bit);
}

BeaconAccessLevel beaconAccessLevelFromReasons(int mask) {
  if (mask & 1 != 0) return BeaconAccessLevel.author;
  if (mask & (2 | 4) != 0) return BeaconAccessLevel.member;
  if (mask & (8 | 16 | 32 | 64 | 128) != 0) return BeaconAccessLevel.observer;
  return BeaconAccessLevel.stranger;
}
