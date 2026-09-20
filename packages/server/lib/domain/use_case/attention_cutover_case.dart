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

    if (await _repository.isLegacySeenComplete()) {
      return AttentionCutoverReport(
        cutoverAt: await _repository.readCutoverInstant(),
        convertedReceipts: 0,
        alreadyComplete: true,
      );
    }

    // Before any row mutation, and idempotent: a resumed pass recognises the
    // instant the interrupted one fixed instead of drawing a new line.
    final cutoverAt = await _repository.fixCutoverInstant();

    var converted = 0;
    while (true) {
      final batch = await _repository.convertLegacySeenBatch(
        batchSize: batchSize,
      );
      converted += batch.converted;
      if (batch.scanned < batchSize) break;
    }
    await _repository.markLegacySeenComplete();

    return AttentionCutoverReport(
      cutoverAt: cutoverAt,
      convertedReceipts: converted,
      alreadyComplete: false,
    );
  }
}
