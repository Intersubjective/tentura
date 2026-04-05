/// Author per-commit response (`beacon_commitment_coordination.response_type`).
enum CoordinationResponseType {
  useful(0),
  overlapping(1),
  needDifferentSkill(2),
  needCoordination(3),
  notSuitable(4);

  const CoordinationResponseType(this.smallintValue);

  final int smallintValue;

  static CoordinationResponseType? tryFromInt(int? v) {
    if (v == null) return null;
    return switch (v) {
      0 => useful,
      1 => overlapping,
      2 => needDifferentSkill,
      3 => needCoordination,
      4 => notSuitable,
      _ => null,
    };
  }
}
