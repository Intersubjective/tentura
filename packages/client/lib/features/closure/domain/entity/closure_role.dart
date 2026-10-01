/// The viewer's role in a closure epoch (Arch §7 `ClosureRole`).
enum ClosureRole {
  author,
  voter,
  member;

  static ClosureRole fromWire(String raw) =>
      values.firstWhere((r) => r.name == raw, orElse: () => member);
}
