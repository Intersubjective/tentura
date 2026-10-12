@Tags(['pg'])
library;

import 'dart:async';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/use_case/attention_sweep_case.dart';

import '../../support/attention_capture_fixture.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';

/// Two Dismiss-all calls for one operation id while a real capture is slow.
///
/// How long a capture takes is a function of machine load, so a caller that
/// finds somebody else capturing must not decide anything from how long it
/// has itself been waiting. A capture that keeps committing chunks is alive,
/// however long it takes in total; only one that has stopped making progress
/// is the abandoned capture the settle job deals with. A waiter that answers
/// `pending` while the capture is still advancing has handed its caller a
/// wall-clock guess instead of the operation's state.
///
/// Both calls here run the real [AttentionSweepCase] against the real capture
/// SQL; the only artificial thing is that the first caller's chunk commits are
/// slowed down, which is what a loaded database does to them.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_SLOW_CAPTURE_WAIT_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_slow_capture',
  );
  // In REQUIRED mode (TENTURA_PG_TESTS_REQUIRED=1) an unreachable Postgres
  // fails the run instead of silently skipping this group.
  final skipReason = await pgSkipReason(target) ?? false;

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;

  setUpAll(() async {
    if (skipReason != false) return;
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  group('second call on an operation whose capture is slow but advancing', () {
    test(
      'waits for the capture to finish and answers with the finished '
      'operation, identities included',
      () async {
        const operationId = 'OPslowcapture';
        const receiptCount = 5;
        const outcomeGeneration = 5;
        const decisionRevision = 4;

        await resetCaptureFixtures(writer, receiptCount: receiptCount);
        // The forwarded Request becomes a decided outcome (watching) with a
        // known identity, next to the receipts.
        await writer.execute(
          Sql.named(
            'UPDATE public.inbox_item SET status = 1 '
            'WHERE user_id = @account AND beacon_id = @beaconId',
          ),
          parameters: {
            'account': captureViewerId,
            'beaconId': captureBeaconId,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.attention_request_state
  (account_id, beacon_id, outcome_generation, decision_revision)
VALUES (@account, @beaconId, @generation, @revision)
ON CONFLICT (account_id, beacon_id) DO UPDATE SET
  outcome_generation = EXCLUDED.outcome_generation,
  decision_revision = EXCLUDED.decision_revision
'''),
          parameters: {
            'account': captureViewerId,
            'beaconId': captureBeaconId,
            'generation': outcomeGeneration,
            'revision': decisionRevision,
          },
        );
        final surface = await readCaptureSurface(writer);
        final memberCount = surface.length;
        expect(memberCount, receiptCount + 1);

        // First caller: one member per chunk, every chunk commit slowed.
        final slow = _SlowCaptureChunkInserts(
          perChunk: const Duration(seconds: 3),
        );
        final slowDb = TenturaDb.forTest(
          database: PgDatabase(
            endpoint: target.databaseEnv.pgEndpoint,
            settings: target.databaseEnv.pgEndpointSettings,
            enableMigrations: false,
          ).interceptWith(slow),
        );
        addTearDown(slowDb.close);
        final firstCall =
            AttentionSweepCase(
              AttentionSweepRepository(slowDb),
            ).dismissAll(
              accountId: captureViewerId,
              operationId: operationId,
              batchSize: 1,
            );

        // The second caller arrives while the first is inside a chunk commit:
        // the capture exists and is advancing, and the second caller's own
        // claim on the same chunk is queued behind the first's.
        await slow.insideChunk.future.timeout(
          kStableStateWait,
          onTimeout: () => fail('the first caller never began committing'),
        );
        final arrival = await _captureProgress(writer, operationId);
        expect(
          arrival.open,
          isTrue,
          reason: 'the second call must arrive while the capture is open',
        );
        expect(arrival.cursor, lessThan(memberCount));

        var secondAnswered = false;
        final secondCall =
            AttentionSweepCase(AttentionSweepRepository(database))
                .dismissAll(
                  accountId: captureViewerId,
                  operationId: operationId,
                  batchSize: 1,
                )
                .whenComplete(() => secondAnswered = true);

        // Observable proof that the capture is advancing while the second
        // call is outstanding: a chunk commits after the second call arrived
        // and the second call has still not answered. Both are state this
        // test holds until it has seen them, not timing.
        final advanced = await _waitForCursorBeyond(
          writer,
          operationId,
          beyond: arrival.cursor,
        ).timeout(kStableStateWait);
        expect(
          secondAnswered,
          isFalse,
          reason:
              'the second call answered before the capture had advanced even '
              'one chunk past where it arrived',
        );
        expect(advanced.open, isTrue);

        final second = await secondCall.timeout(kCompletionWait);
        final atAnswer = await _captureProgress(writer, operationId);
        final first = await firstCall.timeout(kCompletionWait);

        expect(
          atAnswer.open,
          isFalse,
          reason:
              'the capture was still open (cursor ${atAnswer.cursor} of '
              '$memberCount) when the second call answered '
              '(${second.status.name}); it gave up on a capture that was '
              'making progress',
        );
        expect(atAnswer.cursor, memberCount);
        for (final result in [first, second]) {
          expect(result.status, AttentionClearStatus.complete);
          expect(result.appliedCount, memberCount);
          expect(result.pending, isEmpty);
        }

        final stored = await writer.execute(
          Sql.named(
            'SELECT outcome_generation, decision_revision '
            'FROM public.attention_clear_operation_member '
            'WHERE operation_id = @id AND outcome_beacon_id IS NOT NULL',
          ),
          parameters: {'id': operationId},
        );
        expect(stored, hasLength(1));
        expect(stored.first[0], outcomeGeneration);
        expect(stored.first[1], decisionRevision);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, skip: skipReason);
}

typedef _CaptureProgress = ({bool open, int cursor});

/// The operation header's capture state: whether the frozen snapshot is still
/// stored (capture open) and how far the cursor has advanced.
Future<_CaptureProgress> _captureProgress(
  Connection writer,
  String operationId,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT capture_snapshot IS NOT NULL, capture_cursor '
      'FROM public.attention_clear_operation WHERE id = @id',
    ),
    parameters: {'id': operationId},
  );
  return (open: rows.first[0]! as bool, cursor: rows.first[1]! as int);
}

Future<_CaptureProgress> _waitForCursorBeyond(
  Connection writer,
  String operationId, {
  required int beyond,
}) async {
  while (true) {
    final progress = await _captureProgress(writer, operationId);
    if (progress.cursor > beyond) return progress;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Slows every capture chunk's member insert, which runs inside the chunk's
/// transaction right after the cursor claim — so the header row stays locked
/// for the whole delay and a concurrent claim queues up behind it.
final class _SlowCaptureChunkInserts extends QueryInterceptor {
  _SlowCaptureChunkInserts({required this.perChunk});

  final Duration perChunk;
  final insideChunk = Completer<void>();

  Future<T> _slow<T>(String statement, Future<T> Function() run) async {
    if (statement.contains(
      'INSERT INTO public.attention_clear_operation_member',
    )) {
      if (!insideChunk.isCompleted) insideChunk.complete();
      await Future<void>.delayed(perChunk);
    }
    return run();
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _slow(statement, () => super.runInsert(executor, statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _slow(statement, () => super.runUpdate(executor, statement, args));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _slow(statement, () => super.runCustom(executor, statement, args));
}
