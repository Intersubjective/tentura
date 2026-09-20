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
    required this.alreadyComplete,
  });

  final DateTime? cutoverAt;
  final int convertedReceipts;
  final bool alreadyComplete;
}
