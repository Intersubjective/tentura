@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_undo_models.dart';
import 'package:tentura_server/domain/use_case/attention_sweep_case.dart';

import '../../support/disposable_pg_target.dart';

/// U09c — `attentionUndo`.
///
/// Undo is the one command here that can put back something somebody has
/// since decided differently, so the tests that matter are the **refusals**,
/// and they are written as pairs: the same scenario where undo must restore
/// and where it must refuse, so the boundary is pinned from both sides.
///
/// A refusal test that cannot fail is the defect that lets undo resurrect
/// somebody else's decision, so each guard is also proved load-bearing
/// U09a/U09b's way — the exact SQL the repository runs, with that one clause
/// deleted, is run against the same state and *does* restore the row.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U09C_UNDO_TEST_DB',
    defaultNamePrefix: 'tentura_test_u09c_undo',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late AttentionSweepCase sweep;

  setUpAll(() async {
    if (skipReason != false) return;
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    sweep = AttentionSweepCase(AttentionSweepRepository(database));
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    if (skipReason != false) return;
    await _resetFixtures(writer);
  });

  /// Sweeps the whole surface and hands back the token the server issued.
  Future<(String operationId, String undoToken)> sweepAll(String id) async {
    final result = await sweep.dismissAll(
      accountId: _viewerId,
      operationId: id,
    );
    expect(
      result.undoToken,
      isNotNull,
      reason: 'this fixture is supposed to have cleared something',
    );
    return (id, result.undoToken!);
  }

  group('restore', () {
    test('restores both axes of its own operation', () async {
      await _insertReceipt(writer, id: 'Nu09crestore', beaconId: _beaconA);
      await _setStance(writer, beaconId: _beaconB, status: 2);
      final (operationId, token) = await sweepAll('OPu09crestore');
      expect(await _clearedBy(writer, 'Nu09crestore'), operationId);
      expect(await _tombstone(writer, _beaconB), isNotNull);

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(undone.status, AttentionUndoStatus.complete);
      expect(undone.refusal, isNull);
      expect(undone.restoredReceiptIds, ['Nu09crestore']);
      expect(undone.restoredOutcomeBeaconIds, [_beaconB]);
      expect(undone.skipped, isEmpty);
      expect(undone.failed, isEmpty);
      expect(
        await _clearRow(writer, 'Nu09crestore'),
        [null, null, null],
        reason:
            'all three clear facts come back together, or the receipt is in a '
            'state the clear-facts CHECK does not admit',
      );
      expect(await _tombstone(writer, _beaconB), isNull);
    });

    test('restores only members of that operation', () async {
      await _insertReceipt(writer, id: 'Nu09cmine', beaconId: _beaconA);
      final (operationId, token) = await sweepAll('OPu09cmine');
      // A second receipt, cleared by somebody else's gesture entirely.
      await _insertReceipt(writer, id: 'Nu09ctheirs', beaconId: _beaconA);
      await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09cother',
      );
      expect(await _clearedBy(writer, 'Nu09ctheirs'), 'OPu09cother');

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(undone.restoredReceiptIds, ['Nu09cmine']);
      expect(
        await _clearedBy(writer, 'Nu09ctheirs'),
        'OPu09cother',
        reason: "undoing one operation must not touch another's work",
      );
    });

    test('a second undo is idempotent, not an error', () async {
      await _insertReceipt(writer, id: 'Nu09ctwice', beaconId: _beaconA);
      final (operationId, token) = await sweepAll('OPu09ctwice');
      await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      final again = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(again.restoredReceiptIds, isEmpty);
      expect(again.status, AttentionUndoStatus.stale);
      expect(
        again.skipped.single.reason,
        AttentionUndoSkipReason.alreadyRestored,
      );
      expect(await _clearedBy(writer, 'Nu09ctwice'), isNull);
    });
  }, skip: skipReason);

  group('the window', () {
    test('just inside the window restores', () async {
      await _insertReceipt(writer, id: 'Nu09cinside', beaconId: _beaconA);
      final (operationId, token) = await sweepAll('OPu09cinside');
      await _moveDeadline(writer, operationId, "now() + interval '10 seconds'");

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(undone.refusal, isNull);
      expect(undone.restoredReceiptIds, ['Nu09cinside']);
    });

    test('just outside the window refuses, and says so by name', () async {
      await _insertReceipt(writer, id: 'Nu09coutside', beaconId: _beaconA);
      final (operationId, token) = await sweepAll('OPu09coutside');
      await _moveDeadline(writer, operationId, "now() - interval '1 second'");

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(
        undone.refusal,
        AttentionUndoRefusal.expired,
        reason: 'expired is the one refusal a person actually sees; it is '
            'never an untyped failure',
      );
      expect(undone.status, AttentionUndoStatus.denied);
      expect(undone.restoredReceiptIds, isEmpty);
      expect(
        await _clearedBy(writer, 'Nu09coutside'),
        operationId,
        reason: 'an expired undo changes nothing at all',
      );
    });

    test('an operation that cleared nothing has no window', () async {
      // No dismissible row at all: the sweep applies nothing, so no window
      // opens and there is nothing to offer.
      final swept = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09cnothing',
      );
      expect(swept.undoToken, isNull);

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: 'OPu09cnothing',
        undoToken: const AttentionUndoToken(
          accountId: _viewerId,
          operationId: 'OPu09cnothing',
        ).encode(),
      );

      expect(undone.refusal, AttentionUndoRefusal.neverApplied);
      expect(undone.status, AttentionUndoStatus.denied);
    });

    test(
      "somebody else's operation and a missing one answer identically",
      () async {
        await _insertReceipt(writer, id: 'Nu09cforeign', beaconId: _beaconA);
        final (operationId, _) = await sweepAll('OPu09cforeign');

        final foreign = await sweep.undo(
          accountId: _strangerId,
          operationId: operationId,
          undoToken: const AttentionUndoToken(
            accountId: _strangerId,
            operationId: 'OPu09cforeign',
          ).encode(),
        );
        final missing = await sweep.undo(
          accountId: _strangerId,
          operationId: 'OPu09cnosuch',
          undoToken: const AttentionUndoToken(
            accountId: _strangerId,
            operationId: 'OPu09cnosuch',
          ).encode(),
        );

        expect(foreign.refusal, AttentionUndoRefusal.notFound);
        expect(missing.refusal, AttentionUndoRefusal.notFound);
        expect(
          await _clearedBy(writer, 'Nu09cforeign'),
          operationId,
          reason: 'a stranger cannot undo, and learns nothing by trying',
        );
      },
    );

    test('a token bound to another operation buys nothing', () async {
      await _insertReceipt(writer, id: 'Nu09cwrongtok', beaconId: _beaconA);
      final (operationId, _) = await sweepAll('OPu09cwrongtok');

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: const AttentionUndoToken(
          accountId: _viewerId,
          operationId: 'OPu09celsewhere',
        ).encode(),
      );

      expect(undone.refusal, AttentionUndoRefusal.notFound);
      expect(await _clearedBy(writer, 'Nu09cwrongtok'), operationId);
    });

    test('a malformed token never reaches the database', () {
      expect(
        () => sweep.undo(
          accountId: _viewerId,
          operationId: 'OPu09cgarbage',
          undoToken: 'not-a-token',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  }, skip: skipReason);

  // Each pair is the same scenario twice: once where nothing moved and undo
  // must restore, once where something moved and undo must refuse *that*
  // member rather than putting the old state on top of the new one.
  group('later intent wins', () {
    test('restores a receipt whose Request nobody touched', () async {
      await _insertReceipt(writer, id: 'Nu09cquiet', beaconId: _beaconA);
      final (operationId, token) = await sweepAll('OPu09cquiet');

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(undone.restoredReceiptIds, ['Nu09cquiet']);
    });

    test('refuses a receipt whose Request was decided after the sweep', () async {
      await _insertReceipt(writer, id: 'Nu09cdecided', beaconId: _beaconA);
      final (operationId, token) = await sweepAll('OPu09cdecided');
      // The viewer answered the forward after dismissing everything. The
      // decision is the later intent; the dismissed receipt is not put back
      // underneath it.
      await _setStance(writer, beaconId: _beaconA, status: 1);

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(undone.restoredReceiptIds, isEmpty);
      expect(
        undone.skipped.single.reason,
        AttentionUndoSkipReason.decisionChanged,
      );
      expect(await _clearedBy(writer, 'Nu09cdecided'), operationId);
    });

    test('restores an outcome nobody touched', () async {
      await _setStance(writer, beaconId: _beaconB, status: 2);
      final (operationId, token) = await sweepAll('OPu09coutquiet');

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(undone.restoredOutcomeBeaconIds, [_beaconB]);
      expect(await _tombstone(writer, _beaconB), isNull);
    });

    test('refuses an outcome the viewer re-pinned after the sweep', () async {
      await _setStance(writer, beaconId: _beaconB, status: 2);
      final (operationId, token) = await sweepAll('OPu09crepin');
      expect(await _tombstone(writer, _beaconB), isNotNull);
      // Restore, exactly as the client does it: a bare UPDATE through Hasura.
      // It re-pins the forward, which is a decision — undo must not bury it
      // under the tombstone the sweep hid.
      await _setStance(writer, beaconId: _beaconB, status: 0);

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(undone.restoredOutcomeBeaconIds, isEmpty);
      expect(
        undone.skipped.single.reason,
        AttentionUndoSkipReason.decisionChanged,
      );
      expect(
        await _tombstone(writer, _beaconB),
        isNotNull,
        reason: 'the sweep stands; the re-pin stands. Undo changes neither.',
      );
    });

    test(
      'refuses a receipt another operation cleared in the meantime',
      () async {
        await _insertReceipt(writer, id: 'Nu09cstolen', beaconId: _beaconA);
        final (operationId, token) = await sweepAll('OPu09cstolen');
        // Another device's gesture now owns this receipt's cleared state.
        await writer.execute(
          Sql.named('''
INSERT INTO public.attention_clear_operation
  (id, account_id, surface, status, applied, skipped, failed)
VALUES ('OPu09cdevice2', @viewer, 'activity', 'complete', 1, 0, 0)
'''),
          parameters: {'viewer': _viewerId},
        );
        await writer.execute(
          Sql.named(
            'UPDATE public.notification_outbox '
            "SET cleared_by_operation_id = 'OPu09cdevice2' WHERE id = @id",
          ),
          parameters: {'id': 'Nu09cstolen'},
        );

        final undone = await sweep.undo(
          accountId: _viewerId,
          operationId: operationId,
          undoToken: token,
        );

        expect(
          undone.skipped.single.reason,
          AttentionUndoSkipReason.clearedByAnotherOperation,
        );
        expect(await _clearedBy(writer, 'Nu09cstolen'), 'OPu09cdevice2');
      },
    );

    test('refuses an outcome whose row the viewer can no longer see', () async {
      await _setStance(writer, beaconId: _beaconB, status: 2);
      final (operationId, token) = await sweepAll('OPu09cgone');
      await writer.execute(
        Sql.named(
          'DELETE FROM public.inbox_item '
          'WHERE user_id = @user AND beacon_id = @beacon',
        ),
        parameters: {'user': _viewerId, 'beacon': _beaconB},
      );

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: operationId,
        undoToken: token,
      );

      expect(undone.restoredOutcomeBeaconIds, isEmpty);
      expect(
        undone.skipped.single.reason,
        AttentionUndoSkipReason.notAuthorized,
        reason:
            'a vanished row and a lost authorization deliberately share one '
            'answer, so undo discloses neither',
      );
    });
  }, skip: skipReason);

  group('a partially applied sweep', () {
    test(
      'undo restores what was applied and never completes the rest',
      () async {
        for (var index = 0; index < 3; index++) {
          await _insertReceipt(
            writer,
            id: 'Nu09cpartial$index',
            beaconId: _beaconIds[index],
          );
        }
        final bounded = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09cpartial',
          batchSize: 1,
          maxBatches: 1,
        );
        expect(bounded.status, AttentionClearStatus.partial);
        expect(bounded.appliedCount, 1);
        expect(bounded.pending, hasLength(2));
        final appliedId = bounded.appliedReceiptIds.single;
        final pendingIds = {
          for (final member in bounded.pending) member.id,
        };

        final undone = await sweep.undo(
          accountId: _viewerId,
          operationId: 'OPu09cpartial',
          undoToken: bounded.undoToken!,
        );

        expect(undone.restoredReceiptIds, [appliedId]);
        expect(undone.status, AttentionUndoStatus.partial);
        expect(
          {for (final member in undone.skipped) member.id},
          pendingIds,
          reason: 'members that were never applied are reported, not restored',
        );
        expect(
          undone.skipped.map((member) => member.reason).toSet(),
          {AttentionUndoSkipReason.notApplied},
        );
        for (final id in pendingIds) {
          expect(
            await _clearedBy(writer, id),
            isNull,
            reason: 'undo must not finish a sweep it was asked to reverse',
          );
          expect(await _memberState(writer, 'OPu09cpartial', id), 'pending');
        }
        expect(
          await _headerStatus(writer, 'OPu09cpartial'),
          isNot('complete'),
          reason: 'the operation is still unfinished, and still says so',
        );
      },
    );

    test('a member the sweep skipped is never restored by undo', () async {
      // An unanswered forward is captured by nothing, so the skipped member
      // here is one that went ineligible between capture and apply.
      await _insertReceipt(writer, id: 'Nu09cskipapp', beaconId: _beaconA);
      await _insertReceipt(writer, id: 'Nu09cskipgone', beaconId: _beaconC);
      final bounded = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09cskip',
        batchSize: 1,
        maxBatches: 1,
      );
      // Whichever one is still pending gets cleared by another gesture, so
      // the resume skips it as `already_cleared`.
      final stillPending = bounded.pending.single.id;
      await writer.execute(
        Sql.named('''
UPDATE public.notification_outbox
   SET cleared_at = now(), clear_reason = 'explicit'
 WHERE id = @id
'''),
        parameters: {'id': stillPending},
      );
      final resumed = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09cskip',
      );
      expect(resumed.skipped.single.id, stillPending);

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: 'OPu09cskip',
        undoToken: resumed.undoToken!,
      );

      expect(
        undone.skipped.single.id,
        stillPending,
        reason: 'the sweep did not clear it, so undo has nothing to reverse',
      );
      expect(
        undone.skipped.single.reason,
        AttentionUndoSkipReason.notApplied,
      );
      expect(
        await _clearReason(writer, stillPending),
        'explicit',
        reason: "another gesture's clear is not reversed by this undo",
      );
    });
  }, skip: skipReason);

  // Addition 3 — prove the refusals can fail. Each test loosens exactly one
  // clause out of the SQL the repository really runs and shows the row would
  // have come back. A refusal test that cannot fail is the defect that lets
  // undo resurrect somebody else's decision.
  group('the guards are load-bearing', () {
    test('the cleared-by-this-operation guard is load-bearing', () async {
      await _insertReceipt(writer, id: 'Nu09cguard1', beaconId: _beaconA);
      final (operationId, _) = await sweepAll('OPu09cguard1');
      await writer.execute(
        Sql.named('''
INSERT INTO public.attention_clear_operation
  (id, account_id, surface, status, applied, skipped, failed)
VALUES ('OPu09cguard1b', @viewer, 'activity', 'complete', 1, 0, 0)
'''),
        parameters: {'viewer': _viewerId},
      );
      await writer.execute(
        Sql.named(
          'UPDATE public.notification_outbox '
          "SET cleared_by_operation_id = 'OPu09cguard1b' WHERE id = @id",
        ),
        parameters: {'id': 'Nu09cguard1'},
      );

      final restored = await _runLoosened(
        writer,
        AttentionSweepRepository.undoReceiptSql,
        without: AttentionSweepRepository.undoReceiptOperationGuard,
        operationId: operationId,
        memberId: 'Nu09cguard1',
      );

      expect(
        restored,
        ['Nu09cguard1'],
        reason:
            'delete that one clause and undo reverses another device\'s clear',
      );
    });

    test('the receipt counters guard is load-bearing', () async {
      await _insertReceipt(writer, id: 'Nu09cguard2', beaconId: _beaconA);
      final (operationId, _) = await sweepAll('OPu09cguard2');
      await _setStance(writer, beaconId: _beaconA, status: 1);

      final restored = await _runLoosened(
        writer,
        AttentionSweepRepository.undoReceiptSql,
        without: AttentionSweepRepository.undoReceiptCountersGuard,
        operationId: operationId,
        memberId: 'Nu09cguard2',
      );

      expect(
        restored,
        ['Nu09cguard2'],
        reason: 'delete it and a decided Request gets its dismissed receipts '
            'back on top of the decision',
      );
    });

    test('the outcome counters guard is load-bearing', () async {
      await _setStance(writer, beaconId: _beaconB, status: 2);
      final (operationId, _) = await sweepAll('OPu09cguard3');
      await _setStance(writer, beaconId: _beaconB, status: 0);

      final restored = await _runLoosened(
        writer,
        AttentionSweepRepository.undoOutcomeSql,
        without: AttentionSweepRepository.undoOutcomeCountersGuard,
        operationId: operationId,
        memberId: _beaconB,
      );

      expect(
        restored,
        [_beaconB],
        reason: 'delete it and undo hides a forward the viewer just re-pinned',
      );
    });

    test('the applied-state guard is load-bearing', () async {
      await _insertReceipt(writer, id: 'Nu09cguard4', beaconId: _beaconA);
      await _insertReceipt(writer, id: 'Nu09cguard4b', beaconId: _beaconC);
      final bounded = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09cguard4',
        batchSize: 1,
        maxBatches: 1,
      );
      final pendingId = bounded.pending.single.id;
      // A pending member whose receipt nonetheless carries this operation's
      // clear — unreachable by the sweep, which is the point: the guard is
      // what keeps undo from "restoring" work that was never done.
      await writer.execute(
        Sql.named('''
UPDATE public.notification_outbox
   SET cleared_at = now(), clear_reason = 'sweep',
       cleared_by_operation_id = 'OPu09cguard4'
 WHERE id = @id
'''),
        parameters: {'id': pendingId},
      );

      final restored = await _runLoosened(
        writer,
        AttentionSweepRepository.undoReceiptSql,
        without: AttentionSweepRepository.undoAppliedStateGuard,
        operationId: 'OPu09cguard4',
        memberId: pendingId,
      );

      expect(restored, [pendingId]);
    });

    test('the outcome readability guard is load-bearing', () async {
      await _setStance(writer, beaconId: _beaconB, status: 2);
      final (operationId, _) = await sweepAll('OPu09cguard5');
      await writer.execute(
        Sql.named('DELETE FROM public.beacon_forward_edge WHERE beacon_id = @id'),
        parameters: {'id': _beaconB},
      );

      final restored = await _runLoosened(
        writer,
        AttentionSweepRepository.undoOutcomeSql,
        without: AttentionSweepRepository.undoOutcomeReadabilityGuard,
        operationId: operationId,
        memberId: _beaconB,
      );

      expect(
        restored,
        [_beaconB],
        reason: 'delete it and undo puts back a row the viewer may not read',
      );
    });
  }, skip: skipReason);
}

const _viewerId = 'Uu09cundo01';
const _authorId = 'Uu09cundo02';
const _strangerId = 'Uu09cundo03';
const _beaconA = 'Bu09cfwd1';
const _beaconB = 'Bu09cfwd2';
const _beaconC = 'Bu09cfwd3';
const _beaconIds = [_beaconA, _beaconB, _beaconC];

/// Runs the repository's own undo SQL with exactly one guard deleted — the
/// shape a careless refactor leaves behind — and returns what it restored.
Future<List<String>> _runLoosened(
  Connection writer,
  String sql, {
  required String without,
  required String operationId,
  required String memberId,
}) async {
  expect(
    sql,
    contains(without),
    reason: 'the guard under test must be the text the repository runs',
  );
  final loosened = sql.replaceAll(without, '');
  final rows = await writer.execute(
    loosened,
    parameters: [_viewerId, operationId, memberId],
  );
  return [for (final row in rows) row.first! as String];
}

Future<Object?> _clearedBy(Connection writer, String receiptId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT cleared_by_operation_id FROM public.notification_outbox '
      'WHERE id = @id',
    ),
    parameters: {'id': receiptId},
  );
  return rows.isEmpty ? null : rows.first.first;
}

Future<Object?> _clearReason(Connection writer, String receiptId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT clear_reason FROM public.notification_outbox WHERE id = @id',
    ),
    parameters: {'id': receiptId},
  );
  return rows.isEmpty ? null : rows.first.first;
}

Future<List<Object?>> _clearRow(Connection writer, String receiptId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT cleared_at, clear_reason, cleared_by_operation_id '
      'FROM public.notification_outbox WHERE id = @id',
    ),
    parameters: {'id': receiptId},
  );
  return rows.first.toList();
}

Future<Object?> _tombstone(Connection writer, String beaconId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT tombstone_dismissed_at FROM public.inbox_item '
      'WHERE user_id = @user AND beacon_id = @beacon',
    ),
    parameters: {'user': _viewerId, 'beacon': beaconId},
  );
  return rows.isEmpty ? null : rows.first.first;
}

Future<Object?> _memberState(
  Connection writer,
  String operationId,
  String memberId,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT state FROM public.attention_clear_operation_member
 WHERE operation_id = @operationId
   AND (receipt_id = @memberId OR outcome_beacon_id = @memberId)
'''),
    parameters: {'operationId': operationId, 'memberId': memberId},
  );
  return rows.isEmpty ? null : rows.first.first;
}

Future<Object?> _headerStatus(Connection writer, String operationId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT status FROM public.attention_clear_operation WHERE id = @id',
    ),
    parameters: {'id': operationId},
  );
  return rows.isEmpty ? null : rows.first.first;
}

Future<void> _moveDeadline(
  Connection writer,
  String operationId,
  String expression,
) => writer.execute(
  Sql.named(
    'UPDATE public.attention_clear_operation '
    'SET undo_deadline = $expression WHERE id = @id',
  ),
  parameters: {'id': operationId},
);

/// Forwarding already creates the inbox row (`inbox_item_on_forward_insert`),
/// so a stance is set on the row that is there — which is also how the client
/// really does it, through a bare Hasura `UPDATE`.
Future<void> _setStance(
  Connection writer, {
  required String beaconId,
  required int status,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@userId, @beaconId, @status, 1, now(), '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = EXCLUDED.status
'''),
  parameters: {'userId': _viewerId, 'beaconId': beaconId, 'status': status},
);

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String? beaconId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey, now(),
  @beaconId, @sourceEventKey,
  @destinationKind, @presentationKey, '{"eventType":"fixture"}'::jsonb,
  'standard', @accessPolicy,
  false, NULL
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'destinationKind': beaconId == null ? 'profile' : 'beacon',
    'presentationKey': beaconId == null
        ? 'mutual_connection_formed'
        : 'request_status_changed',
    'accessPolicy': beaconId == null ? 'profile' : 'beacon_content',
  },
);

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.inbox_item,
  public.beacon_forward_edge,
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _authorId, _strangerId]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  for (final beaconId in _beaconIds) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, 'Forwarded', 'Forwarded request', 0)
'''),
      parameters: {'id': beaconId, 'authorId': _authorId},
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @beaconId, @senderId, @recipientId)
'''),
      parameters: {
        'id': 'Fu09c$beaconId',
        'beaconId': beaconId,
        'senderId': _authorId,
        'recipientId': _viewerId,
      },
    );
  }
}
