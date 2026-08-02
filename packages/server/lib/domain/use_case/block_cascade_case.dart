import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/_use_case_base.dart';

/// Async cascade materialization worker (§6.7 materialization half).
@Singleton(order: 2)
final class BlockCascadeCase extends UseCaseBase {
  BlockCascadeCase(
    this._userBlocks, {
    required super.env,
    required super.logger,
  });

  final UserBlockRepositoryPort _userBlocks;

  /// Intents claimed per [runDue] sweep — small enough to share the time budget
  /// across several cascades without starving the task-worker loop.
  static const _claimBatchSize = 10;

  Future<void> runDue({DateTime? now}) async {
    final started = DateTime.timestamp();
    final budget = env.trustSweepTimeBudget;

    while (!_budgetExceeded(started, budget)) {
      final intents = await _userBlocks.claimPendingCascades(
        limit: _claimBatchSize,
      );
      if (intents.isEmpty) return;

      for (final intent in intents) {
        if (_budgetExceeded(started, budget)) return;
        await _drainIntent(
          blockerId: intent.blockerId,
          blockedId: intent.blockedId,
        );
      }
    }
  }

  Future<void> _drainIntent({
    required String blockerId,
    required String blockedId,
  }) async {
    while (true) {
      final inserted = await _userBlocks.materializeCascadeBatch(
        blockerId: blockerId,
        blockedId: blockedId,
        limit: env.blockCascadeBatchSize,
      );
      if (inserted == 0) break;
    }
  }

  bool _budgetExceeded(DateTime started, Duration budget) =>
      DateTime.timestamp().difference(started) >= budget;
}
