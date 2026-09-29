enum ClosureBand {
  none(0),
  raised(1),
  asIfSilent(2),
  lowered(3);

  const ClosureBand(this.smallintValue);

  final int smallintValue;

  static ClosureBand? tryFromInt(int? v) => switch (v) {
        0 => none,
        1 => raised,
        2 => asIfSilent,
        3 => lowered,
        _ => null,
      };
}
