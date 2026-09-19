@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/attention_dismissible_sql.dart';

import '../../support/disposable_pg_target.dart';

/// U09a step 2 — the shared "rows that carry their own ×" predicate.
///
/// Owner decision A's safety margin is an *exclusion*, so the tests that
/// matter are the negative ones. Each exclusion is asserted twice: the row is
/// absent from the dismissible set, and a deliberately loosened copy of the
/// same predicate — the exact shape a future refactor would produce — puts it
/// back. Without that second half, deleting the exclusion would leave this
/// file green.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U09A_PREDICATE_TEST_DB',
    defaultNamePrefix: 'tentura_test_u09a_predicate',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;

  setUpAll(() async {
    if (skipReason != false) return;
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    if (skipReason != false) return;
    await _resetFixtures(writer);
  });

  group('Set R — dismissible optional receipts', () {
    test(
      'an optional receipt on a forwarded Request carries its own ×',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nu09apra',
          beaconId: _forwardedBeaconId,
        );

        expect(await _dismissibleReceipts(writer), ['Nu09apra']);
      },
    );

    test('an obligation never does', () async {
      // Deliberately a Request-less obligation: an obligation *on* a Request
      // is excluded twice over (see the next test), which would hide whether
      // `NOT requires_action` is doing any work at all.
      await _insertReceipt(
        writer,
        id: 'Nu09aproblig',
        beaconId: null,
        requiresAction: true,
      );

      expect(
        await _dismissibleReceipts(writer),
        isEmpty,
        reason: 'an obligation has no × and is never swept (D06, D07)',
      );
      expect(
        await _dismissibleReceipts(writer, withoutObligationExclusion: true),
        ['Nu09aproblig'],
        reason:
            'the exclusion is load-bearing: drop `NOT requires_action` and the '
            'obligation becomes a sweep member',
      );
    });

    test('an obligation on a Request is excluded twice over', () async {
      await _insertReceipt(
        writer,
        id: 'Nu09aproblig2',
        beaconId: _obligationBeaconId,
        requiresAction: true,
      );

      expect(await _dismissibleReceipts(writer), isEmpty);
      expect(
        await _dismissibleReceipts(writer, withoutObligationExclusion: true),
        isEmpty,
        reason:
            'the live obligation put the Request in the responsibility scope, '
            'so the surface filter refuses it even without the obligation '
            'exclusion — defence in depth, not redundancy',
      );
    });

    test('an already cleared receipt is not swept twice', () async {
      await _insertReceipt(
        writer,
        id: 'Nu09aprcleared',
        beaconId: _forwardedBeaconId,
      );
      await writer.execute(
        "UPDATE public.notification_outbox "
        "SET cleared_at = now(), clear_reason = 'explicit' "
        "WHERE id = 'Nu09aprcleared'",
      );

      expect(await _dismissibleReceipts(writer), isEmpty);
    });

    test(
      'a receipt on a Request the viewer is responsible for is not on this surface',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nu09aprown',
          beaconId: _ownedBeaconId,
        );

        expect(
          await _dismissibleReceipts(writer),
          isEmpty,
          reason: 'the viewer authored it: that Request is My Desk work',
        );
      },
    );

    test(
      'the optional children of an unanswered forward stay dismissible',
      () async {
        // The margin is precise: the *forward row* awaits a decision, the
        // Request's optional events on the same card do not.
        await _insertInboxItem(writer, beaconId: _forwardedBeaconId, status: 0);
        await _insertReceipt(
          writer,
          id: 'Nu09aprchild',
          beaconId: _forwardedBeaconId,
        );

        expect(await _dismissibleReceipts(writer), ['Nu09aprchild']);
        expect(await _dismissibleOutcomes(writer), isEmpty);
      },
    );
  }, skip: skipReason);

  group('Set O — dismissible outcome rows', () {
    for (final kind in const [
      (status: 1, name: 'watching'),
      (status: 2, name: 'notInterested'),
    ]) {
      test('a ${kind.name} outcome carries its own ×', () async {
        await _insertInboxItem(
          writer,
          beaconId: _forwardedBeaconId,
          status: kind.status,
        );

        expect(await _dismissibleOutcomes(writer), [_forwardedBeaconId]);
      });
    }

    test('an unanswered forward never does', () async {
      await _insertInboxItem(writer, beaconId: _forwardedBeaconId, status: 0);

      expect(
        await _dismissibleOutcomes(writer),
        isEmpty,
        reason:
            'it awaits a decision; sweeping it would answer a person by not '
            'answering them (owner decision A)',
      );
      expect(
        await _dismissibleOutcomes(writer, withoutPinnedExclusion: true),
        contains(_forwardedBeaconId),
        reason:
            'the exclusion is load-bearing: drop `NOT IN eligible_pinned` and '
            'the unanswered forward becomes a sweep member',
      );
    });

    test('a helping outcome does — the viewer already answered', () async {
      // `status = 0` inside the responsibility scope is "You're helping"
      // (owner decision B), not an unanswered forward: a presentational trace
      // of the viewer's own past action, with a ×.
      await _insertInboxItem(writer, beaconId: _ownedBeaconId, status: 0);

      expect(await _dismissibleOutcomes(writer), [_ownedBeaconId]);
    });

    test('an already dismissed outcome is not swept twice', () async {
      await _insertInboxItem(writer, beaconId: _forwardedBeaconId, status: 1);
      await writer.execute(
        'UPDATE public.inbox_item SET tombstone_dismissed_at = now() '
        "WHERE user_id = '$_viewerId'",
      );

      expect(await _dismissibleOutcomes(writer), isEmpty);
    });

    test('the outcome carries the identity undo will check', () async {
      await _insertInboxItem(writer, beaconId: _forwardedBeaconId, status: 1);
      await writer.execute(
        Sql.named('''
INSERT INTO public.attention_request_state
  (account_id, beacon_id, outcome_generation, decision_revision)
VALUES (@account, @beaconId, 7, 3)
ON CONFLICT (account_id, beacon_id) DO UPDATE SET
  outcome_generation = EXCLUDED.outcome_generation,
  decision_revision = EXCLUDED.decision_revision
'''),
        parameters: {'account': _viewerId, 'beaconId': _forwardedBeaconId},
      );

      final rows = await writer.execute(
        '''
WITH ${AttentionDismissibleSql.cte}
SELECT outcome_generation, decision_revision
  FROM activity_outcome_dismissible
''',
        parameters: [_viewerId],
      );
      expect(rows.first[0], 7);
      expect(rows.first[1], 3);
    });
  }, skip: skipReason);
}

const _viewerId = 'Uu09apred01';
const _authorId = 'Uu09apred02';
const _ownedBeaconId = 'Bu09apredown';
const _forwardedBeaconId = 'Bu09apredfwd';
const _obligationBeaconId = 'Bu09apredobl';

Future<List<String>> _dismissibleReceipts(
  Connection writer, {
  bool withoutObligationExclusion = false,
}) async {
  var receipts = AttentionDismissibleSql.dismissibleReceipts;
  if (withoutObligationExclusion) {
    receipts = receipts.replaceAll('AND NOT v.requires_action', '');
  }
  final rows = await writer.execute(
    '''
WITH ${AttentionDismissibleSql.prelude},
$receipts
SELECT receipt_id FROM activity_optional_dismissible ORDER BY receipt_id
''',
    parameters: [_viewerId],
  );
  return [for (final row in rows) row.first! as String];
}

Future<List<String>> _dismissibleOutcomes(
  Connection writer, {
  bool withoutPinnedExclusion = false,
}) async {
  var outcomes = AttentionDismissibleSql.dismissibleOutcomes;
  if (withoutPinnedExclusion) {
    outcomes = outcomes.replaceAll(
      'AND ii.beacon_id NOT IN (SELECT beacon_id FROM eligible_pinned)',
      '',
    );
  }
  final rows = await writer.execute(
    '''
WITH ${AttentionDismissibleSql.prelude},
$outcomes
SELECT beacon_id FROM activity_outcome_dismissible ORDER BY beacon_id
''',
    parameters: [_viewerId],
  );
  return [for (final row in rows) row.first! as String];
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
  for (final id in [_viewerId, _authorId]) {
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
VALUES
  (@ownedId, @viewerId, 'Owned', 'Owned request', 0),
  (@forwardedId, @authorId, 'Forwarded', 'Forwarded request', 0),
  (@obligationId, @authorId, 'Obligation', 'Obligation request', 0)
'''),
    parameters: {
      'ownedId': _ownedBeaconId,
      'forwardedId': _forwardedBeaconId,
      'obligationId': _obligationBeaconId,
      'viewerId': _viewerId,
      'authorId': _authorId,
    },
  );
  for (final entry in const [
    ('Fu09apred01', _forwardedBeaconId),
    ('Fu09apred02', _obligationBeaconId),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @beaconId, @senderId, @recipientId)
'''),
      parameters: {
        'id': entry.$1,
        'beaconId': entry.$2,
        'senderId': _authorId,
        'recipientId': _viewerId,
      },
    );
  }
}

/// Forwarding already creates the inbox row (`inbox_item_on_forward_insert`),
/// so the fixture sets the stance on the row that is there rather than
/// pretending an unforwarded Request can have one.
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
  parameters: {
    'userId': _viewerId,
    'beaconId': beaconId,
    'status': status,
  },
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
