import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_cutover_models.dart';
import 'package:tentura_server/domain/port/attention_cutover_port.dart';

/// U18a — the cutover backfill, D19's one write to existing rows.
///
/// It converts optional receipts the user has already seen into cleared ones
/// (`clear_reason = 'legacy_seen'`, no operation id: they were never an
/// explicit sweep, so they are not undoable and belong to no sweep's
/// accounting). Unseen optional receipts stay active — a receipt the user
/// never saw that this pass cleared is attention silently lost, the one
/// irreversible way to get this unit wrong.
///
/// It writes state and nothing else: no channel job, no email, no push. D19 is
/// explicit that the backfill does not replay delivery.
@Singleton(order: 3)
class AttentionCutoverCase {
  const AttentionCutoverCase(this._repository);

  final AttentionCutoverPort _repository;

  /// Runs the backfill, resuming a previous pass if one was interrupted.
  ///
  /// [batchSize] exists so an interruption can be injected between two real
  /// batches; production takes the default.
  Future<AttentionCutoverReport> cutoverBackfillIfNeeded({
    int batchSize = 500,
  }) async {
    if (batchSize < 1) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be at least 1');
    }

    // Each phase is asked separately, because each can be interrupted while
    // the others have not started (m0193 gives each its own cursor). A single
    // "done" flag would let a crash between two phases look like a finished
    // backfill.
    final legacySeenDone = await _repository.isLegacySeenComplete();
    final obligationKeysDone = await _repository.isObligationKeyComplete();
    final placementDone = await _repository.isPlacementComplete();
    if (legacySeenDone && obligationKeysDone && placementDone) {
      return AttentionCutoverReport(
        cutoverAt: await _repository.readCutoverInstant(),
        convertedReceipts: 0,
        keyedObligations: 0,
        demotedPlacements: 0,
        alreadyComplete: true,
      );
    }

    // Before any row mutation, and idempotent: a resumed pass recognises the
    // instant the interrupted one fixed instead of drawing a new line.
    final cutoverAt = await _repository.fixCutoverInstant();

    final converted = legacySeenDone
        ? 0
        : await _runPhase(
            batchSize: batchSize,
            runBatch: _repository.convertLegacySeenBatch,
            markComplete: _repository.markLegacySeenComplete,
          );
    final keyed = obligationKeysDone
        ? 0
        : await _runPhase(
            batchSize: batchSize,
            runBatch: _repository.keyLegacyObligationBatch,
            markComplete: _repository.markObligationKeyComplete,
          );
    final demoted = placementDone
        ? 0
        : await _runPhase(
            batchSize: batchSize,
            runBatch: _repository.demoteLegacyPlacementBatch,
            markComplete: _repository.markPlacementComplete,
          );

    return AttentionCutoverReport(
      cutoverAt: cutoverAt,
      convertedReceipts: converted,
      keyedObligations: keyed,
      demotedPlacements: demoted,
      alreadyComplete: false,
    );
  }

  /// One phase: batches until a short one, then the completion mark.
  ///
  /// Termination is `scanned`, never `converted`. U18b's gates leave rows
  /// alone on purpose — a batch of fifty undecidable obligations converts
  /// nothing and has still made progress — so a loop that stopped on a
  /// converted count of zero would stop at the first row it could not prove.
  Future<int> _runPhase({
    required int batchSize,
    required Future<AttentionCutoverBatch> Function({required int batchSize})
    runBatch,
    required Future<void> Function() markComplete,
  }) async {
    var converted = 0;
    while (true) {
      final batch = await runBatch(batchSize: batchSize);
      converted += batch.converted;
      if (batch.scanned < batchSize) break;
    }
    await markComplete();
    return converted;
  }
}
