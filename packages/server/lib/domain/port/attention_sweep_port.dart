import 'package:tentura_server/domain/attention/attention_sweep_models.dart';

/// Storage side of U09b's *Dismiss all*.
///
/// One method, because capture and apply are not separately callable: a client
/// has no say in what a surface-wide sweep contains, and letting it hand back
/// a membership would reintroduce exactly the "only what is loaded" bug the
/// server capture exists to avoid. The two phases are still distinct inside —
/// the first call captures, every call applies what is still pending.
// ignore: one_member_abstracts — a port, not a function: U09c adds undo here.
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
}
