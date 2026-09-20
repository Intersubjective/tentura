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

  /// Whether U18b gate 1 has already run out of candidates.
  Future<bool> isObligationKeyComplete();

  /// Gives a `logical_task_key` to at most [batchSize] live obligations whose
  /// identity is **provable from stored facts**, and leaves the rest.
  ///
  /// `scanned` counts every legacy live unkeyed obligation the batch looked
  /// at; `converted` counts only the ones keyed. The difference is not an
  /// error rate — it is the population `unrepairableObligationCount` keeps
  /// reporting, which is the honest answer while the facts stay missing.
  Future<AttentionCutoverBatch> keyLegacyObligationBatch({
    required int batchSize,
  });

  /// Marks gate 1 finished. Guarded: it never re-stamps.
  Future<void> markObligationKeyComplete();

  /// Whether U18b gate 2 has already run out of candidates.
  Future<bool> isPlacementComplete();

  /// Demotes at most [batchSize] pre-m0189 receipts that are **provably** of a
  /// timeline-only event family to `placement = 'timeline_only'`.
  ///
  /// Only the decidable subset is ever a candidate here, so `scanned` and
  /// `converted` differ only when another writer moved a row first.
  Future<AttentionCutoverBatch> demoteLegacyPlacementBatch({
    required int batchSize,
  });

  /// Marks gate 2 finished. Guarded: it never re-stamps.
  Future<void> markPlacementComplete();
}
