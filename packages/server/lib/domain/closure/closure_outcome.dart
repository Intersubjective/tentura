enum ClosureOutcome {
  done(1),
  notDone(2),
  cantJudge(3);

  const ClosureOutcome(this.smallintValue);

  final int smallintValue;

  static ClosureOutcome? tryFromInt(int? v) => switch (v) {
        1 => done,
        2 => notDone,
        3 => cantJudge,
        _ => null,
      };
}
