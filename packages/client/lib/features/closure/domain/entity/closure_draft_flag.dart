/// Whether the viewer's draft verdict reached the result (Arch §7).
enum ClosureDraftFlag {
  none,
  notCounted,
  lastEditNotCounted;

  static ClosureDraftFlag fromWire(String raw) =>
      values.firstWhere((f) => f.name == raw, orElse: () => none);
}
