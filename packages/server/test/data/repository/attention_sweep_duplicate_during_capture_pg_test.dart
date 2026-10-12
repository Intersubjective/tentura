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

import '../../support/attention_capture_fixture.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';

/// A second call with an operation id whose capture is still being committed.
///
/// Capture is committed in bounded chunks, so between two chunks nobody holds
/// a lock on the operation. A duplicate that read the capture cursor, and then
/// finds the cursor moved under it, must not take that as proof the capture is
/// over: it either waits for the capture to finish or answers with a
/// non-terminal state, and it never reports a terminal answer (least of all
/// `partial`) for a membership that is still being written.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_DUPLICATE_CAPTURE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_dup_capture',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

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

  group('duplicate call while capture is still being committed', () {
    test(
      'waits for the capture or answers pending, never a terminal status',
      () async {
        const operationId = 'OPdupcapture';
        const memberCount = 6;
        // The call that started the capture commits two members per chunk;
        // the duplicate uses three. Batch size is a per-call argument, so two
        // callers of one operation need not agree on it.
        const firstCallerChunk = 2;
        const duplicateChunk = 3;

        await resetCaptureFixtures(writer, receiptCount: memberCount);
        final snapshot = await readCaptureSurface(writer);
        expect(snapshot, hasLength(memberCount));
        await seedPendingCapture(
          writer,
          operationId: operationId,
          snapshot: snapshot,
        );

        // The duplicate is held right after it has read the capture header, so
        // what it knows about the cursor is stale by the time it acts on it.
        final gate = _HoldAfterCaptureStateRead();
        final duplicateDb = TenturaDb.forTest(
          database: PgDatabase(
            endpoint: target.databaseEnv.pgEndpoint,
            settings: target.databaseEnv.pgEndpointSettings,
            enableMigrations: false,
          ).interceptWith(gate),
        );
        addTearDown(duplicateDb.close);
        final probe = openDisposablePgDatabase(target);
        addTearDown(probe.close);

        // Set, with no await in between, just before the first caller goes
        // on to commit the rest of the capture. An answer that resolves while
        // this is still false was computed while the capture was open.
        var captureResumed = false;
        var answeredWhileCaptureOpen = false;
        final duplicateCall = AttentionSweepRepository(duplicateDb)
            .dismissAll(
              accountId: captureViewerId,
              operationId: operationId,
              batchSize: duplicateChunk,
            )
            .then((result) {
              answeredWhileCaptureOpen = !captureResumed;
              return result;
            });
        // The race only exists if the duplicate looks at the capture state
        // before acting on it; a duplicate that never does is not exercising
        // the stale read this test is about, so that is a failure, not a skip.
        await gate.reached.future.timeout(
          kStableStateWait,
          onTimeout: () => fail(
            'the duplicate never read the capture state outside a transaction',
          ),
        );

        // The first caller commits its first chunk and then goes quiet between
        // chunks, with no lock held on the operation.
        await writer.runTx((transaction) async {
          await commitCaptureChunk(
            transaction,
            operationId: operationId,
            snapshot: snapshot,
            start: 0,
            next: firstCallerChunk,
          );
        });
        gate.release.complete();

        // A duplicate that gave up on the capture answers inside this window;
        // one that waits is still parked when it ends.
        await Future.any<void>([
          duplicateCall,
          Future<void>.delayed(const Duration(milliseconds: 1500)),
        ]);
        captureResumed = true;

        for (
          var start = firstCallerChunk;
          start < snapshot.length;
          start += firstCallerChunk
        ) {
          await commitCaptureChunk(
            writer,
            operationId: operationId,
            snapshot: snapshot,
            start: start,
            next: start + firstCallerChunk,
          );
        }

        final result = await duplicateCall.timeout(kCompletionWait);

        expect(
          result.status,
          isNot(AttentionClearStatus.partial),
          reason: 'a duplicate during capture must not report partial',
        );
        if (answeredWhileCaptureOpen) {
          // The duplicate did not wait, so it answered while the snapshot was
          // stored and only a third of the members existed. The only
          // acceptable answer is a non-terminal in-flight one.
          expect(
            result.status.name,
            'pending',
            reason:
                'an answer given before the capture is complete must say the '
                'operation is still pending, not complete/stale/partial',
          );
          expect(result.appliedCount, 0);
        } else {
          // The duplicate waited, or answered once the capture was being
          // finished: either still pending, or the finished membership.
          expect(
            result.status.name == 'pending' ||
                (result.status == AttentionClearStatus.complete &&
                    result.appliedCount == memberCount &&
                    result.pending.isEmpty),
            isTrue,
            reason:
                'got ${result.status.name} with ${result.appliedCount} applied',
          );
        }

        // Once the capture is over the same operation id resolves normally.
        final settled = await AttentionSweepRepository(database).dismissAll(
          accountId: captureViewerId,
          operationId: operationId,
          batchSize: duplicateChunk,
        );
        expect(settled.status, AttentionClearStatus.complete);
        expect(settled.appliedCount, memberCount);
        final state = await _captureState(probe, operationId);
        expect(state.snapshotCleared, isTrue);
        expect(state.members, memberCount);
      },
    );
  });
}

/// Lets the caller read the operation's capture state, then parks it until the
/// test releases it. Only the read outside a transaction is held, so a caller
/// that takes the header under a lock is never parked while holding it.
final class _HoldAfterCaptureStateRead extends QueryInterceptor {
  final reached = Completer<void>();
  final release = Completer<void>();
  var _fired = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    if (!_fired &&
        executor is! TransactionExecutor &&
        statement.contains('capture_')) {
      _fired = true;
      reached.complete();
      await release.future;
    }
    return rows;
  }
}

typedef _CaptureState = ({bool snapshotCleared, int members});

Future<_CaptureState> _captureState(TenturaDb db, String operationId) async {
  final row = await db
      .customSelect(
        r'''
SELECT (SELECT capture_snapshot IS NULL
          FROM public.attention_clear_operation WHERE id = $1) AS cleared,
       (SELECT count(*) FROM public.attention_clear_operation_member
         WHERE operation_id = $1) AS members
''',
        variables: [Variable<String>(operationId)],
      )
      .getSingle();
  return (
    snapshotCleared: row.read<bool?>('cleared') ?? false,
    members: row.read<int>('members'),
  );
}
