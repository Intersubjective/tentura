import 'package:tentura_server/domain/attention/attention_cutover_models.dart';

/// Storage side of the U18a cutover backfill.
///
/// The loop is deliberately **not** here: the case owns it and this port hands
/// out one batch at a time. That split is what lets a test interrupt the
/// backfill for real — between two batches, in the caller — rather than
/// through a failure hook threaded into production code for the test's
/// benefit.
abstract class AttentionCutoverPort {
  /// Writes the cutover instant if it is not written yet and returns it.
  ///
  /// Idempotent, and it must be called before any receipt is mutated: the
  /// boundary is what decides which receipts are legacy, so a pass that
  /// converted rows first would be converting them against no boundary at all.
  Future<DateTime> fixCutoverInstant();

  /// The instant, or `null` before the first pass ever ran.
  Future<DateTime?> readCutoverInstant();

  /// Whether the `legacy_seen` phase has already run out of candidates.
  Future<bool> isLegacySeenComplete();

  /// Converts at most [batchSize] legacy seen optional receipts and commits
  /// the cursor with them.
  Future<AttentionCutoverBatch> convertLegacySeenBatch({
    required int batchSize,
  });

  /// Marks the `legacy_seen` phase finished. Guarded: it never re-stamps.
  Future<void> markLegacySeenComplete();
}
