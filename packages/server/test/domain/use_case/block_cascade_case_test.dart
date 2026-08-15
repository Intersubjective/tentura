import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/user_block_entity.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/block_cascade_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  test('runDue drains materializeCascadeBatch until zero', () async {
    final repo = _RecordingUserBlockRepository();
    repo.pendingIntents.add(
      UserBlockIntentEntity(
        blockerId: 'A',
        blockedId: 'B',
        cascadeMode: 1,
        cascadeStatus: 0,
        materializedCount: 0,
        createdAt: DateTime.utc(2026),
      ),
    );
    repo.batchReturns.addAll([2, 1, 0]);

    final env = Env.test();
    final job = BlockCascadeCase(
      repo,
      env: env,
      logger: Logger('block_cascade_case_test'),
    );

    await job.runDue();

    expect(repo.materializeCalls, 3);
    expect(repo.batchReturns, isEmpty);
  });

  test('runDue stops when claimPendingCascades returns empty', () async {
    final repo = _RecordingUserBlockRepository();
    // Mimics production after mode-0 filter: nothing to claim.
    final env = Env.test();
    final job = BlockCascadeCase(
      repo,
      env: env,
      logger: Logger('block_cascade_case_test'),
    );

    await job.runDue();

    expect(repo.claimCalls, 1);
    expect(repo.materializeCalls, 0);
  });
}

final class _RecordingUserBlockRepository implements UserBlockRepositoryPort {
  final List<UserBlockIntentEntity> pendingIntents = [];
  final List<int> batchReturns = [];
  int materializeCalls = 0;
  int claimCalls = 0;

  @override
  Future<List<UserBlockIntentEntity>> claimPendingCascades({
    required int limit,
  }) async {
    claimCalls++;
    if (pendingIntents.isEmpty) return [];
    final claimed = pendingIntents.take(limit).toList(growable: false);
    pendingIntents.removeRange(0, claimed.length);
    return claimed;
  }

  @override
  Future<int> materializeCascadeBatch({
    required String blockerId,
    required String blockedId,
    required int limit,
  }) async {
    materializeCalls++;
    if (batchReturns.isEmpty) return 0;
    return batchReturns.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
