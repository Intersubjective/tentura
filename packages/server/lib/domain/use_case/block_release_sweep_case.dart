import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/_use_case_base.dart';

/// Slow probation release sweep (§6.7 release half) — mode-1 inherited rows only.
@Singleton(order: 2)
final class BlockReleaseSweepCase extends UseCaseBase {
  BlockReleaseSweepCase(
    this._userBlocks, {
    required super.env,
    required super.logger,
  });

  final UserBlockRepositoryPort _userBlocks;

  BlockReleaseSweepCursor? _cursor;

  Future<void> runDue({DateTime? now}) async {
    final started = DateTime.timestamp();
    final budget = env.trustSweepTimeBudget;

    while (!_budgetExceeded(started, budget)) {
      final batch = await _userBlocks.runReleaseSweep(
        limit: env.trustSweepBatchSize,
        afterCursor: _cursor,
      );

      final last = batch.lastExaminedCandidate;
      if (last == null) {
        _cursor = null;
        return;
      }

      _cursor = last;
      if (batch.reachedTail) {
        _cursor = null;
        return;
      }
    }
  }

  bool _budgetExceeded(DateTime started, Duration budget) =>
      DateTime.timestamp().difference(started) >= budget;
}
