/// `beacon_closure.finalize_reason` (m0203 CHECK: 1, 2).
enum FinalizeReason {
  authorCloseNow(1),
  expired(2);

  const FinalizeReason(this.dbValue);

  final int dbValue;

  static FinalizeReason? tryFromInt(int? v) => switch (v) {
        1 => authorCloseNow,
        2 => expired,
        _ => null,
      };
}
