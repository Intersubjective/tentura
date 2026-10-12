/// Storage side of settling attention clears whose capture was abandoned.
///
/// Separate from the sweep port because nobody on the request path calls it:
/// the task worker does, on a timer.
// ignore: one_member_abstracts -- injectable port with a single timer-driven call
abstract interface class AttentionCaptureSettlementPort {
  /// Settles clears still `pending` with their snapshot stored and not touched
  /// for [staleAfter]: those older than [expireAfter] are expired, the rest are
  /// resumed to completion. The snapshot is cleared either way. Returns how
  /// many operations were settled.
  Future<int> settleAbandonedCaptures({
    required Duration staleAfter,
    required Duration expireAfter,
  });
}
