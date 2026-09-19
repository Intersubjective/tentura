import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/attention/attention_undo_models.dart';

/// Storage side of U09b's *Dismiss all*.
///
/// One method, because capture and apply are not separately callable: a client
/// has no say in what a surface-wide sweep contains, and letting it hand back
/// a membership would reintroduce exactly the "only what is loaded" bug the
/// server capture exists to avoid. The two phases are still distinct inside —
/// the first call captures, every call applies what is still pending.
abstract interface class AttentionSweepPort {
  /// Captures (once) and applies the dismissible surface of [accountId] under
  /// [operationId].
  ///
  /// Idempotent and resumable by [operationId]: the first call records the
  /// membership, and every later call — including a concurrent one, including
  /// one that arrives after a timeout — decides only members still pending and
  /// reports the same answer. Membership is never extended.
  ///
  /// [maxBatches] bounds the work of one call; the caller resumes by invoking
  /// the same [operationId] again.
  Future<AttentionSweepResult> dismissAll({
    required String accountId,
    required String operationId,
    int batchSize,
    int? maxBatches,
  });

  /// Reverses, within the window, exactly what [operationId] applied.
  ///
  /// Bounded by `attention_clear_operation.undo_deadline` against the server's
  /// own clock, and conservative in one direction: a member whose object moved
  /// since the sweep is refused rather than restored, because later intent
  /// wins. Partial by design — every member either comes back or carries a
  /// typed reason why it did not.
  ///
  /// It restores only members this operation actually *applied*. A bounded
  /// sweep's still-pending members are reported, never restored and never
  /// completed: undo is not a second half of the sweep.
  Future<AttentionUndoResult> undo({
    required String accountId,
    required String operationId,
    required String undoToken,
  });
}
