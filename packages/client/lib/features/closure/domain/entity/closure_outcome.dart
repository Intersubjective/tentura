/// A helper's outcome as judged by a voter (Arch §7 `ClosureOutcome`).
enum ClosureOutcome {
  done,
  notDone,
  cantJudge;

  /// GraphQL enum value on the wire.
  String get wire => name;

  static ClosureOutcome fromWire(String raw) =>
      values.firstWhere((o) => o.name == raw, orElse: () => cantJudge);
}
