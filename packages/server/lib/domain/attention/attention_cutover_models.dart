/// What one `legacy_seen` batch did.
///
/// [scanned] is how many candidate receipts the batch claimed, [converted] how
/// many the guarded UPDATE actually changed. They differ only when another
/// writer cleared a row between the two halves of the same statement, which is
/// exactly the case the NULL guard exists for: the backfill loses that race on
/// purpose and reports it honestly rather than re-stamping `cleared_at`.
final class AttentionCutoverBatch {
  const AttentionCutoverBatch({
    required this.scanned,
    required this.converted,
  });

  final int scanned;
  final int converted;
}

/// What a whole backfill pass did.
///
/// [convertedReceipts] counts only this pass. A resumed backfill therefore
/// reports fewer conversions than the pass it finishes — the sum across passes
/// is the total, and [alreadyComplete] marks the pass that found nothing left
/// to do at all.
final class AttentionCutoverReport {
  const AttentionCutoverReport({
    required this.cutoverAt,
    required this.convertedReceipts,
    required this.keyedObligations,
    required this.demotedPlacements,
    required this.alreadyComplete,
  });

  final DateTime? cutoverAt;
  final int convertedReceipts;

  /// U18b gate 1 — live obligations that gained a `logical_task_key`.
  ///
  /// Deliberately not "obligations repaired": the rows this pass leaves alone
  /// are not failures, they are rows whose identity is not provable, and they
  /// stay counted in `unrepairableObligationCount` where the user sees them.
  final int keyedObligations;

  /// U18b gate 2 — pre-m0189 receipts demoted to `timeline_only`.
  final int demotedPlacements;
  final bool alreadyComplete;
}
