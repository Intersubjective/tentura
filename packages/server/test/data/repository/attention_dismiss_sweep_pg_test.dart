@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
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
          "SELECT surface, account_id FROM public.attention_clear_operation "
          "WHERE id = 'OPu09bpages'",
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
