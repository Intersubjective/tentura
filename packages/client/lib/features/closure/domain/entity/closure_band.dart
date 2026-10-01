/// Result word relative to colleagues' silence (Arch §7 `ClosureBand`).
enum ClosureBand {
  raised,
  asIfSilent,
  lowered,
  none;

  static ClosureBand fromWire(String raw) =>
      values.firstWhere((b) => b.name == raw, orElse: () => none);
}
