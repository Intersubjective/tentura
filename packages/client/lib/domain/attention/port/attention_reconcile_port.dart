import '../entity/attention_clear.dart';

/// The one attention capability the Settings **Reset counters** command needs.
///
/// Narrow on purpose: the surface that repairs the counters has no business
/// reaching the feed, the acks or the clear axis, and a UI test for the copy
/// rules should not have to stand up the whole attention owner to get one
/// mutation to answer. `AttentionCase` remains the single owner of attention
/// state (§0.3); this is a view onto it, not a second one.
abstract interface class AttentionReconcilePort {
  /// D15 — repair, never erasure. The returned summary is authoritative and
  /// may legitimately be non-zero.
  Future<AttentionReconcileResult> reconcile();
}
