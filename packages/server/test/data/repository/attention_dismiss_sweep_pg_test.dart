@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/use_case/attention_sweep_case.dart';

import '../../support/disposable_pg_target.dart';

/// U09b — `attentionDismissAll`.
///
/// Owner decision A is the product guarantee this unit exists to keep:
/// sweeping an unanswered forward would answer a person by not answering
/// them. So the tests that matter here are the *exclusions*, and an exclusion
/// test that cannot fail is worthless — each one is therefore asserted twice,
/// U09a's way: the row is absent from the real capture, and a deliberately
/// loosened copy of the very SQL the repository runs puts it back.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U09B_SWEEP_TEST_DB',
    defaultNamePrefix: 'tentura_test_u09b_sweep',
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

  group('capture', () {
    test(
      'captures the whole authorized surface, including pages nobody loaded',
      () async {
        // This is the difference from U08: no client hands over this list.
        // Seven receipts and two outcomes, swept in batches of three, is a
        // membership no loaded page ever held.
        for (var index = 0; index < 7; index++) {
          await _insertReceipt(
            writer,
            id: 'Nu09bpage$index',
            beaconId: _forwardedBeaconIds[index % _forwardedBeaconIds.length],
          );
        }
        await _insertInboxItem(writer, beaconId: _watchedBeaconId, status: 1);
        await _insertInboxItem(writer, beaconId: _rejectedBeaconId, status: 2);

        await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09bpages',
          batchSize: 3,
        );

        expect(
          await _memberIds(writer, 'OPu09bpages'),
          hasLength(9),
          reason: 'capture is server-side and covers the whole surface',
        );
        expect(
          await _memberIds(writer, 'OPu09bpages', kind: 'outcome'),
          {_watchedBeaconId, _rejectedBeaconId},
        );
        final header = await writer.execute(
          Sql.named(
            'SELECT surface, account_id '
            'FROM public.attention_clear_operation WHERE id = @id',
          ),
          parameters: {'id': 'OPu09bpages'},
        );
        expect(header.first[0], AttentionSweepRepository.surface);
        expect(header.first[1], _viewerId);
      },
    );

    test('a standalone receipt with no Request is captured too', () async {
      await _insertReceipt(writer, id: 'Nu09bprofile', beaconId: null);

      await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09bprofile',
      );

      expect(
        await _memberIds(writer, 'OPu09bprofile'),
        {'Nu09bprofile'},
        reason: 'For You is not only Requests',
      );
    });

    test('membership is captured once and never extended', () async {
      await _insertReceipt(
        writer,
        id: 'Nu09bonce',
        beaconId: _forwardedBeaconIds.first,
      );

      await sweep.dismissAll(accountId: _viewerId, operationId: 'OPu09bonce');
      await _insertReceipt(
        writer,
        id: 'Nu09bafter',
        beaconId: _forwardedBeaconIds.first,
      );
      await sweep.dismissAll(accountId: _viewerId, operationId: 'OPu09bonce');

      expect(
        await _memberIds(writer, 'OPu09bonce'),
        {'Nu09bonce'},
        reason:
            'a receipt that arrived after the capture is not this operation '
            "'s business, however often the id is replayed",
      );
    });

    test('an unanswered forward is never a member', () async {
      await _insertInboxItem(
        writer,
        beaconId: _forwardedBeaconIds.first,
        status: 0,
      );

      await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09bpinned',
      );

      expect(
        await _memberIds(writer, 'OPu09bpinned'),
        isEmpty,
        reason:
            'it awaits a decision; sweeping it would answer a person by not '
            'answering them (owner decision A)',
      );
      expect(
        await _looseCapture(writer, withoutPinnedExclusion: true),
        contains(_forwardedBeaconIds.first),
        reason:
            'the exclusion is load-bearing: drop `NOT IN eligible_pinned` from '
            'the capture and the unanswered forward becomes a member',
      );
    });

    test('an obligation is never a member', () async {
      await _insertReceipt(
        writer,
        id: 'Nu09boblig',
        beaconId: null,
        requiresAction: true,
      );

      await sweep.dismissAll(accountId: _viewerId, operationId: 'OPu09boblig');

      expect(await _memberIds(writer, 'OPu09boblig'), isEmpty);
      expect(
        await _looseCapture(writer, withoutObligationExclusion: true),
        contains('Nu09boblig'),
        reason:
            'the exclusion is load-bearing: drop `NOT requires_action` and the '
            'obligation becomes a member',
      );
    });

    test('the capture stores the identity undo will check', () async {
      await _insertInboxItem(writer, beaconId: _watchedBeaconId, status: 1);
      await writer.execute(
        Sql.named('''
INSERT INTO public.attention_request_state
  (account_id, beacon_id, outcome_generation, decision_revision)
VALUES (@account, @beaconId, 5, 4)
ON CONFLICT (account_id, beacon_id) DO UPDATE SET
  outcome_generation = EXCLUDED.outcome_generation,
  decision_revision = EXCLUDED.decision_revision
'''),
        parameters: {'account': _viewerId, 'beaconId': _watchedBeaconId},
      );

      await sweep.dismissAll(accountId: _viewerId, operationId: 'OPu09bident');

      final row = await writer.execute(
        'SELECT outcome_generation, decision_revision '
        'FROM public.attention_clear_operation_member '
        "WHERE operation_id = 'OPu09bident'",
      );
      expect(row.first[0], 5);
      expect(
        row.first[1],
        4,
        reason:
            'U09c refuses to undo a member whose stance moved underneath it, '
            'and a Restore moves the revision without moving the generation',
      );
    });

    test(
      'an operation id belonging to another account is denied, and touches '
      'nothing',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nu09bstranger',
          beaconId: _forwardedBeaconIds.first,
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.attention_clear_operation
  (id, account_id, surface, status, applied, skipped, failed)
VALUES ('OPu09bstranger', @account, 'activity', 'pending', 0, 0, 0)
'''),
          parameters: {'account': _strangerId},
        );

        final result = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09bstranger',
        );

        expect(result.status, AttentionClearStatus.denied);
        expect(result.appliedCount, 0);
        expect(await _memberIds(writer, 'OPu09bstranger'), isEmpty);
        expect(await _clearedAt(writer, 'Nu09bstranger'), isNull);
      },
    );
  }, skip: skipReason);

  group('apply', () {
    test('one operation spans both axes', () async {
      await _insertReceipt(
        writer,
        id: 'Nu09bboth',
        beaconId: _forwardedBeaconIds.first,
      );
      await _insertInboxItem(writer, beaconId: _rejectedBeaconId, status: 2);

      final result = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09bboth',
      );

      expect(result.appliedReceiptIds, ['Nu09bboth']);
      expect(result.appliedOutcomeBeaconIds, [_rejectedBeaconId]);
      expect(result.status, AttentionClearStatus.complete);

      final receipt = await writer.execute(
        Sql.named(
          'SELECT clear_reason, cleared_by_operation_id, cleared_at, seen_at '
          'FROM public.notification_outbox WHERE id = @id',
        ),
        parameters: {'id': 'Nu09bboth'},
      );
      expect(receipt.first[0], 'sweep');
      expect(receipt.first[1], 'OPu09bboth');
      expect(receipt.first[2], isNotNull);
      expect(
        receipt.first[3],
        isNull,
        reason:
            'U10 owns the indicators: a sweep clears the optional axis and '
            'never the read axis, so nothing here may assert that the '
            'surface went to zero',
      );
      expect(await _tombstoneDismissedAt(writer, _rejectedBeaconId), isNotNull);
    });

    test('sweeps every captured page, not just the first', () async {
      for (var index = 0; index < 7; index++) {
        await _insertReceipt(
          writer,
          id: 'Nu09bsweep$index',
          beaconId: _forwardedBeaconIds[index % _forwardedBeaconIds.length],
        );
      }
      await _insertInboxItem(writer, beaconId: _watchedBeaconId, status: 1);
      await _insertInboxItem(writer, beaconId: _rejectedBeaconId, status: 2);

      final result = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09bmany',
        batchSize: 3,
      );

      expect(result.appliedCount, 9, reason: 'three pages and a remainder');
      expect(result.status, AttentionClearStatus.complete);
      expect(result.pending, isEmpty);
      final header = await _header(writer, 'OPu09bmany');
      expect(header, ['complete', 9, 0, 0]);
    });

    test('a bounded call reports what is still pending', () async {
      for (var index = 0; index < 3; index++) {
        await _insertReceipt(
          writer,
          id: 'Nu09bbound$index',
          beaconId: _forwardedBeaconIds.first,
        );
      }

      final first = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09bbound',
        batchSize: 1,
        maxBatches: 1,
      );

      expect(first.appliedCount, 1);
      expect(first.pending, hasLength(2));
      expect(
        first.status,
        AttentionClearStatus.partial,
        reason: 'a sweep with work left is not complete and must not say so',
      );

      final second = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09bbound',
        batchSize: 1,
      );

      expect(second.appliedCount, 3);
      expect(second.pending, isEmpty);
      expect(second.status, AttentionClearStatus.complete);
    });

    test(
      'an obligation is still uncleared after the surface is swept',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nu09bapplyoblig',
          beaconId: null,
          requiresAction: true,
        );
        await _insertReceipt(
          writer,
          id: 'Nu09bapplyopt',
          beaconId: _forwardedBeaconIds.first,
        );

        final result = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09bapplyoblig',
        );

        expect(result.appliedReceiptIds, ['Nu09bapplyopt']);
        expect(await _clearedAt(writer, 'Nu09bapplyoblig'), isNull);
      },
    );
  }, skip: skipReason);

  group('races, each with its outcome stated in advance', () {
    test(
      'a forward answered again mid-sweep is skipped and reported, never swept',
      () async {
        // Captured as a `notInterested` outcome — a dated trace of the
        // viewer's own decision, carrying its own ×. Then they press Restore,
        // and the Request is back in the pinned zone awaiting an answer.
        // Sweeping it now would answer a person by not answering them.
        await _insertReceipt(
          writer,
          id: 'Nu09brestore',
          beaconId: _forwardedBeaconIds.first,
        );
        await _insertInboxItem(writer, beaconId: _rejectedBeaconId, status: 2);

        final first = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09brestore',
          batchSize: 1,
          maxBatches: 1,
        );
        expect(first.appliedReceiptIds, ['Nu09brestore']);
        expect(first.pending.single.id, _rejectedBeaconId);

        // Restore, exactly as the client does it: a bare UPDATE.
        await writer.execute(
          Sql.named(
            'UPDATE public.inbox_item SET status = 0 '
            'WHERE user_id = @userId AND beacon_id = @beaconId',
          ),
          parameters: {'userId': _viewerId, 'beaconId': _rejectedBeaconId},
        );

        final second = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09brestore',
        );

        expect(second.appliedOutcomeBeaconIds, isEmpty);
        expect(
          second.skipped.single.reason,
          AttentionSweepSkipReason.awaitingDecision,
          reason:
              "the sweep's own predicate refused it before the database had "
              'to — the point of not relying on the last line of defence',
        );
        expect(
          second.failed,
          isEmpty,
          reason:
              'a refusal by m0185 would surface here as a failed member; '
              'nothing reached the trigger',
        );
        expect(second.status, AttentionClearStatus.partial);
        expect(await _tombstoneDismissedAt(writer, _rejectedBeaconId), isNull);
      },
    );

    test(
      'm0185 refuses the same row at the row level, so both lines hold',
      () async {
        // The predicate is the first line and this is the second, asserted by
        // trigger name: a test that only observed "the write failed" would
        // keep passing if the refusal moved somewhere unrelated.
        await expectLater(
          writer.execute(
            Sql.named(
              'UPDATE public.inbox_item SET tombstone_dismissed_at = now() '
              'WHERE user_id = @userId AND beacon_id = @beaconId',
            ),
            parameters: {
              'userId': _viewerId,
              'beaconId': _forwardedBeaconIds.first,
            },
          ),
          throwsA(
            isA<ServerException>().having(
              (error) => error.message,
              'message',
              contains('unanswered forward cannot be dismissed'),
            ),
          ),
        );
      },
    );

    test('a forward that arrives mid-sweep is not swept up', () async {
      await _insertReceipt(
        writer,
        id: 'Nu09barrivea',
        beaconId: _forwardedBeaconIds.first,
      );
      await _insertReceipt(
        writer,
        id: 'Nu09barriveb',
        beaconId: _forwardedBeaconIds.first,
      );

      await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09barrive',
        batchSize: 1,
        maxBatches: 1,
      );

      // Somebody forwards a Request to the viewer while the sweep runs.
      await _forwardNewRequest(
        writer,
        beaconId: 'Bu09blate',
        forwardId: 'Fu09blate',
      );
      await _insertReceipt(writer, id: 'Nu09blate', beaconId: 'Bu09blate');

      final result = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09barrive',
      );

      expect(result.appliedReceiptIds, ['Nu09barrivea', 'Nu09barriveb']);
      expect(await _clearedAt(writer, 'Nu09blate'), isNull);
      expect(await _tombstoneDismissedAt(writer, 'Bu09blate'), isNull);
      expect(
        await _memberIds(writer, 'OPu09barrive'),
        {'Nu09barrivea', 'Nu09barriveb'},
        reason: 'a resumed operation never extends its membership',
      );
    });

    test(
      'a member that became ineligible after capture is skipped, not cleared',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nu09bstalea',
          beaconId: _forwardedBeaconIds.first,
        );
        await _insertReceipt(
          writer,
          id: 'Nu09bstaleb',
          beaconId: _forwardedBeaconIds.first,
        );

        await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09bstale',
          batchSize: 1,
          maxBatches: 1,
        );
        // Another gesture got there first — an explicit × on another device.
        await writer.execute(
          Sql.named(
            'UPDATE public.notification_outbox '
            "SET cleared_at = now(), clear_reason = 'explicit' "
            'WHERE id = @id',
          ),
          parameters: {'id': 'Nu09bstaleb'},
        );

        final result = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09bstale',
        );

        expect(result.appliedReceiptIds, ['Nu09bstalea']);
        expect(result.skipped.single.id, 'Nu09bstaleb');
        expect(
          result.skipped.single.reason,
          AttentionSweepSkipReason.alreadyCleared,
        );
        expect(result.status, AttentionClearStatus.partial);
        final reason = await writer.execute(
          Sql.named(
            'SELECT clear_reason FROM public.notification_outbox '
            'WHERE id = @id',
          ),
          parameters: {'id': 'Nu09bstaleb'},
        );
        expect(
          reason.first.first,
          'explicit',
          reason: 'the sweep did not re-stamp a receipt it did not clear',
        );
      },
    );

    test(
      'a Request that became My Desk work mid-sweep is skipped and reported',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nu09bdeska',
          beaconId: _forwardedBeaconIds.first,
        );
        await _insertReceipt(
          writer,
          id: 'Nu09bdeskb',
          beaconId: _forwardedBeaconIds[1],
        );

        await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09bdesk',
          batchSize: 1,
          maxBatches: 1,
        );
        // A live obligation on the second Request puts it in the
        // responsibility scope: it is not dismissible from For You any more.
        await _insertReceipt(
          writer,
          id: 'Nu09bdeskoblig',
          beaconId: _forwardedBeaconIds[1],
          requiresAction: true,
        );

        final result = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPu09bdesk',
        );

        expect(result.appliedReceiptIds, ['Nu09bdeska']);
        expect(
          result.skipped.single.reason,
          AttentionSweepSkipReason.responsibilityGained,
        );
        expect(await _clearedAt(writer, 'Nu09bdeskb'), isNull);
      },
    );

    test('an outcome decided underneath the sweep is skipped', () async {
      await _insertReceipt(
        writer,
        id: 'Nu09bgen',
        beaconId: _forwardedBeaconIds.first,
      );
      await _insertInboxItem(writer, beaconId: _watchedBeaconId, status: 1);

      await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09bgen',
        batchSize: 1,
        maxBatches: 1,
      );
      // The Request's identity moves underneath the operation, as a decision
      // made elsewhere moves it. The outcome row the sweep captured is not
      // the row in front of the person now.
      await writer.execute(
        Sql.named(
          'UPDATE public.attention_request_state '
          'SET decision_revision = decision_revision + 5 '
          'WHERE account_id = @account AND beacon_id = @beaconId',
        ),
        parameters: {'account': _viewerId, 'beaconId': _watchedBeaconId},
      );

      final result = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09bgen',
      );

      expect(result.appliedOutcomeBeaconIds, isEmpty);
      expect(result.appliedReceiptIds, ['Nu09bgen']);
      expect(
        result.skipped.single.reason,
        AttentionSweepSkipReason.decisionChanged,
      );
      expect(await _tombstoneDismissedAt(writer, _watchedBeaconId), isNull);
    });

    test('a replayed operation id has exactly one effect', () async {
      await _insertReceipt(
        writer,
        id: 'Nu09breplay',
        beaconId: _forwardedBeaconIds.first,
      );
      await _insertInboxItem(writer, beaconId: _rejectedBeaconId, status: 2);

      final first = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09breplay',
      );
      final clearedAt = await _clearedAt(writer, 'Nu09breplay');
      final dismissedAt = await _tombstoneDismissedAt(
        writer,
        _rejectedBeaconId,
      );
      await _insertReceipt(
        writer,
        id: 'Nu09breplaylate',
        beaconId: _forwardedBeaconIds.first,
      );

      final second = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPu09breplay',
      );

      expect(second.appliedReceiptIds, first.appliedReceiptIds);
      expect(second.appliedOutcomeBeaconIds, first.appliedOutcomeBeaconIds);
      expect(second.status, first.status);
      expect(await _clearedAt(writer, 'Nu09breplay'), clearedAt);
      expect(
        await _tombstoneDismissedAt(writer, _rejectedBeaconId),
        dismissedAt,
      );
      expect(await _clearedAt(writer, 'Nu09breplaylate'), isNull);
      expect(await _countOperations(writer, 'OPu09breplay'), 1);
      expect(await _memberIds(writer, 'OPu09breplay'), hasLength(2));
    });

    test(
      'a concurrently replayed operation id has exactly one effect',
      () async {
        for (var index = 0; index < 4; index++) {
          await _insertReceipt(
            writer,
            id: 'Nu09bconc$index',
            beaconId: _forwardedBeaconIds.first,
          );
        }
        await _insertInboxItem(writer, beaconId: _rejectedBeaconId, status: 2);

        // A second connection, so the two calls really do race in Postgres
        // rather than being serialized by one drift executor.
        final rival = openDisposablePgDatabase(target);
        addTearDown(rival.close);
        final rivalSweep = AttentionSweepCase(AttentionSweepRepository(rival));

        final results = await Future.wait([
          sweep.dismissAll(
            accountId: _viewerId,
            operationId: 'OPu09bconc',
            batchSize: 1,
          ),
          rivalSweep.dismissAll(
            accountId: _viewerId,
            operationId: 'OPu09bconc',
            batchSize: 1,
          ),
        ]);

        expect(results.first.appliedCount, 5);
        expect(
          results.last.appliedReceiptIds,
          results.first.appliedReceiptIds,
          reason: 'both callers report the operation, not what they did',
        );
        expect(results.first.status, results.last.status);
        expect(results.first.status, AttentionClearStatus.complete);
        expect(await _countOperations(writer, 'OPu09bconc'), 1);
        expect(await _memberIds(writer, 'OPu09bconc'), hasLength(5));
        final header = await _header(writer, 'OPu09bconc');
        expect(header, ['complete', 5, 0, 0]);
      },
    );
  }, skip: skipReason);
}

const _viewerId = 'Uu09bsweep01';
const _authorId = 'Uu09bsweep02';
const _strangerId = 'Uu09bsweep03';
const _ownedBeaconId = 'Bu09bown';
const _watchedBeaconId = 'Bu09bfwd1';
const _rejectedBeaconId = 'Bu09bfwd2';
const _forwardedBeaconIds = [
  'Bu09bfwd1',
  'Bu09bfwd2',
  'Bu09bfwd3',
];

/// Runs the repository's own capture SQL with one exclusion deleted — the
/// exact shape a careless refactor leaves behind. If the loosened copy does
/// not admit the row, the exclusion under test proves nothing.
Future<Set<String>> _looseCapture(
  Connection writer, {
  bool withoutPinnedExclusion = false,
  bool withoutObligationExclusion = false,
}) async {
  var sql = AttentionSweepRepository.captureSql;
  if (withoutPinnedExclusion) {
    sql = sql.replaceAll(
      'AND ii.beacon_id NOT IN (SELECT beacon_id FROM eligible_pinned)',
      '',
    );
  }
  if (withoutObligationExclusion) {
    sql = sql.replaceAll('AND NOT v.requires_action', '');
  }
  final rows = await writer.execute(sql, parameters: [_viewerId]);
  return {for (final row in rows) row[1]! as String};
}

Future<Set<String>> _memberIds(
  Connection writer,
  String operationId, {
  String? kind,
}) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT COALESCE(receipt_id, outcome_beacon_id)
  FROM public.attention_clear_operation_member
 WHERE operation_id = @operationId
   AND (@kind::text IS NULL
        OR (@kind = 'receipt' AND receipt_id IS NOT NULL)
        OR (@kind = 'outcome' AND outcome_beacon_id IS NOT NULL))
'''),
    parameters: {'operationId': operationId, 'kind': kind},
  );
  return {for (final row in rows) row.first! as String};
}

Future<Object?> _clearedAt(Connection writer, String receiptId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT cleared_at FROM public.notification_outbox WHERE id = @id',
    ),
    parameters: {'id': receiptId},
  );
  return rows.first.first;
}

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
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@ownedId, @viewerId, 'Owned', 'Owned request', 0)
'''),
    parameters: {'ownedId': _ownedBeaconId, 'viewerId': _viewerId},
  );
  for (final beaconId in _forwardedBeaconIds) {
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
        'id': 'Fu09b$beaconId',
        'beaconId': beaconId,
        'senderId': _authorId,
        'recipientId': _viewerId,
      },
    );
  }
}

/// Forwarding already creates the inbox row (`inbox_item_on_forward_insert`),
/// so the fixture sets a stance on the row that is there.
Future<void> _insertInboxItem(
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
  bool requiresAction = false,
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
  @requiresAction, @threadKey
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
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$_viewerId' : null,
  },
);

Future<Object?> _tombstoneDismissedAt(
  Connection writer,
  String beaconId,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT tombstone_dismissed_at FROM public.inbox_item '
      'WHERE user_id = @userId AND beacon_id = @beaconId',
    ),
    parameters: {'userId': _viewerId, 'beaconId': beaconId},
  );
  return rows.isEmpty ? null : rows.first.first;
}

Future<List<Object?>> _header(Connection writer, String operationId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT status, applied, skipped, failed '
      'FROM public.attention_clear_operation WHERE id = @id',
    ),
    parameters: {'id': operationId},
  );
  return rows.first.toList();
}

Future<int> _countOperations(Connection writer, String operationId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*) FROM public.attention_clear_operation WHERE id = @id',
    ),
    parameters: {'id': operationId},
  );
  return rows.first.first! as int;
}

/// A Request forwarded to the viewer after the sweep captured its membership.
Future<void> _forwardNewRequest(
  Connection writer, {
  required String beaconId,
  required String forwardId,
}) async {
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon (id, user_id, title, description, status) '
      "VALUES (@id, @authorId, 'Late', 'Arrived mid-sweep', 0)",
    ),
    parameters: {'id': beaconId, 'authorId': _authorId},
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon_forward_edge '
      '(id, beacon_id, sender_id, recipient_id) '
      'VALUES (@id, @beaconId, @senderId, @recipientId)',
    ),
    parameters: {
      'id': forwardId,
      'beaconId': beaconId,
      'senderId': _authorId,
      'recipientId': _viewerId,
    },
  );
}
