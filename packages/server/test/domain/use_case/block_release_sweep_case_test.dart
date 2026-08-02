import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/block_release_sweep_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  test('runDue advances cursor across batches and resets at tail', () async {
    final repo = _RecordingUserBlockRepository();
    repo.batches.addAll([
      (
        deletedCount: 0,
        lastExaminedCandidate: (
          blockerId: 'A',
          blockedId: 'P1',
          originId: 'B',
        ),
        reachedTail: false,
      ),
      (
        deletedCount: 0,
        lastExaminedCandidate: (
          blockerId: 'A',
          blockedId: 'P2',
          originId: 'B',
        ),
        reachedTail: true,
      ),
    ]);

    final env = Env.test();
    final job = BlockReleaseSweepCase(
      repo,
      env: env,
      logger: Logger('block_release_sweep_case_test'),
    );

    await job.runDue();
    expect(repo.cursors, [
      null,
      (blockerId: 'A', blockedId: 'P1', originId: 'B'),
    ]);
    expect(repo.calls, 2);

    await job.runDue();
    expect(repo.calls, 3);
    expect(repo.cursors.last, isNull);
  });
}

final class _RecordingUserBlockRepository implements UserBlockRepositoryPort {
  final List<BlockReleaseSweepBatch> batches = [];
  final List<BlockReleaseSweepCursor?> cursors = [];
  var calls = 0;

  @override
  Future<BlockReleaseSweepBatch> runReleaseSweep({
    required int limit,
    BlockReleaseSweepCursor? afterCursor,
  }) async {
    calls++;
    cursors.add(afterCursor);
    if (batches.isEmpty) {
      return (
        deletedCount: 0,
        lastExaminedCandidate: null,
        reachedTail: true,
      );
    }
    return batches.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
