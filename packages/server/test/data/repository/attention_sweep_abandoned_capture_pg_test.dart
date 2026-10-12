@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';

import '../../support/attention_capture_fixture.dart';
import '../../support/disposable_pg_target.dart';

/// A clear whose capture was started and then abandoned — the caller went
/// away, or the process died between two capture chunks — leaves a header
/// stuck at `pending` with its whole frozen snapshot stored, and nothing would
/// ever look at it again. `settleAbandonedCaptures` is the sweep that deals
/// with them, by age since the capture was last touched:
///
/// * younger than `staleAfter` — left alone, it may still be in flight;
/// * older than `staleAfter`, younger than `expireAfter` — resumed: the
///   capture is finished and the operation applied, so it is `complete`, every
///   member was captured and cleared, and the header counts them;
/// * older than `expireAfter` — expired: the operation is `expired`, no member
///   is left `pending`, and nothing was cleared on behalf of a capture nobody
///   finished.
///
/// Resumed or expired, the stored snapshot is cleared.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_ABANDONED_CAPTURE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_abandoned',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  const staleAfter = Duration(minutes: 10);
  const expireAfter = Duration(days: 1);
  const memberCount = 4;

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late AttentionSweepRepository repository;
  late List<Map<String, Object?>> snapshot;

  setUpAll(() async {
    if (skipReason != false) return;
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    repository = AttentionSweepRepository(database);
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    if (skipReason != false) return;
    await resetCaptureFixtures(writer, receiptCount: memberCount);
    snapshot = await readCaptureSurface(writer);
    expect(snapshot, hasLength(memberCount));
  });

  group('abandoned capture', () {
    test('that never committed a chunk is resumed to completion', () async {
      await seedPendingCapture(
        writer,
        operationId: 'OPresumecold',
        snapshot: snapshot,
        age: const Duration(hours: 1),
      );

      await _settle(repository, staleAfter, expireAfter);

      await _expectResumed(writer, 'OPresumecold', memberCount);
    });

    test('that stopped part-way is resumed to completion', () async {
      await seedPendingCapture(
        writer,
        operationId: 'OPresumemid',
        snapshot: snapshot,
      );
      await commitCaptureChunk(
        writer,
        operationId: 'OPresumemid',
        snapshot: snapshot,
        start: 0,
        next: 2,
      );
      // The chunk was committed, then nothing happened for an hour.
      await ageCapture(
        writer,
        operationId: 'OPresumemid',
        age: const Duration(hours: 1),
      );

      await _settle(repository, staleAfter, expireAfter);

      await _expectResumed(writer, 'OPresumemid', memberCount);
    });

    test('older than the expiry horizon is expired, not applied', () async {
      await seedPendingCapture(
        writer,
        operationId: 'OPexpirecold',
        snapshot: snapshot,
        age: const Duration(days: 3),
      );

      await _settle(repository, staleAfter, expireAfter);

      await _expectExpired(writer, 'OPexpirecold');
    });

    test(
      'older than the expiry horizon and part-captured is expired',
      () async {
        await seedPendingCapture(
          writer,
          operationId: 'OPexpiremid',
          snapshot: snapshot,
        );
        await commitCaptureChunk(
          writer,
          operationId: 'OPexpiremid',
          snapshot: snapshot,
          start: 0,
          next: 2,
        );
        await ageCapture(
          writer,
          operationId: 'OPexpiremid',
          age: const Duration(days: 3),
        );

        await _settle(repository, staleAfter, expireAfter);

        await _expectExpired(writer, 'OPexpiremid');
      },
    );

    test('is not touched while it is still recent', () async {
      await seedPendingCapture(
        writer,
        operationId: 'OPcapturefresh',
        snapshot: snapshot,
        age: const Duration(minutes: 1),
      );

      await _settle(repository, staleAfter, expireAfter);

      final state = await _state(writer, 'OPcapturefresh');
      expect(
        state.snapshotStored,
        isTrue,
        reason: 'a capture that may still be in flight keeps its snapshot',
      );
      expect(state.status, 'pending');
      expect(state.members, 0);
    });

    test('settling leaves a finished operation as it was', () async {
      await repository.dismissAll(
        accountId: captureViewerId,
        operationId: 'OPcapturedone',
      );
      final before = await _state(writer, 'OPcapturedone');
      expect(before.status, 'complete');
      await ageCapture(
        writer,
        operationId: 'OPcapturedone',
        age: const Duration(days: 3),
      );

      await _settle(repository, staleAfter, expireAfter);

      final after = await _state(writer, 'OPcapturedone');
      expect(after.status, 'complete');
      expect(after.members, memberCount);
    });
  });
}

Future<void> _settle(
  AttentionSweepRepository repository,
  Duration staleAfter,
  Duration expireAfter,
) => repository.settleAbandonedCaptures(
  staleAfter: staleAfter,
  expireAfter: expireAfter,
);

Future<void> _expectResumed(
  Connection writer,
  String operationId,
  int memberCount,
) async {
  final state = await _state(writer, operationId);
  expect(state.snapshotStored, isFalse);
  expect(state.status, 'complete');
  expect(state.members, memberCount);
  expect(state.applied, memberCount);
  expect(state.clearedReceipts, memberCount);
}

Future<void> _expectExpired(Connection writer, String operationId) async {
  final state = await _state(writer, operationId);
  expect(
    state.snapshotStored,
    isFalse,
    reason: 'an expired capture must not keep its frozen membership',
  );
  expect(state.status, 'expired');
  expect(state.pendingMembers, 0, reason: 'expiry decides every member');
  expect(state.applied, 0);
  expect(state.clearedReceipts, 0, reason: 'expiry clears nothing');
}

typedef _OperationState = ({
  String status,
  bool snapshotStored,
  int members,
  int pendingMembers,
  int applied,
  int clearedReceipts,
});

Future<_OperationState> _state(Connection writer, String operationId) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT status, capture_snapshot IS NOT NULL, applied,
       (SELECT count(*) FROM public.attention_clear_operation_member
         WHERE operation_id = @id),
       (SELECT count(*) FROM public.attention_clear_operation_member
         WHERE operation_id = @id AND state = 'pending'),
       (SELECT count(*) FROM public.notification_outbox
         WHERE cleared_at IS NOT NULL)
  FROM public.attention_clear_operation WHERE id = @id
'''),
    parameters: {'id': operationId},
  );
  final row = rows.single;
  return (
    status: row[0]! as String,
    snapshotStored: row[1]! as bool,
    applied: row[2]! as int,
    members: row[3]! as int,
    pendingMembers: row[4]! as int,
    clearedReceipts: row[5]! as int,
  );
}
