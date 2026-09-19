@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';

import '../../support/disposable_pg_target.dart';

/// U16c-1 — the *Dismiss all* enablement signal, and the one property that
/// makes it honest.
///
/// The header control is the clear axis (D02). Before this unit the surface
/// summary carried no field for it: `activityUnreadTotal` is the *read* axis,
/// and `forYouDot` includes `eligible_pinned`, so gating on it would light the
/// button when only an unanswered forward remains — a control that enables and
/// then does nothing, which is §6's "One predicate" failure wearing a button.
///
/// So `forYouSweepEligible` is composed from the same two sets the sweep
/// itself captures, and this file asserts the **iff** that makes composition
/// more than a comment:
///
///   forYouSweepEligible == (the sweep's own capture SQL returns ≥ 1 row)
///
/// A fixture where the sweep captures nothing but the flag is true — or the
/// reverse — fails here. That is deliberately a property over the *live*
/// `AttentionSweepRepository.captureSql`, not over a paraphrase of it: U15R-d's
/// verify pass caught a guard that had its own slightly looser copy of the
/// predicate it existed to protect, and could therefore never catch the drift.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U16C_ELIGIBILITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_u16c_eligible',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late AttentionRepository query;

  setUpAll(() async {
    if (skipReason != false) return;
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    query = AttentionRepository(database);
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    if (skipReason != false) return;
    await _resetFixtures(writer);
  });

  /// The whole point of the unit, as one assertion, run after every fixture.
  Future<bool> expectAgreement() async {
    final summary = await query.surfaceSummary(accountId: _viewerId);
    final captured = await _captureCount(writer);
    expect(
      summary.forYouSweepEligible,
      captured > 0,
      reason:
          'the enablement flag must be true exactly when the sweep would '
          'capture at least one row (captured = $captured)',
    );
    return summary.forYouSweepEligible;
  }

  group('forYouSweepEligible agrees with what the sweep captures', () {
    test('an empty surface is not eligible', () async {
      expect(await expectAgreement(), isFalse);
    });

    test('a dismissible optional receipt makes it eligible (Set R)', () async {
      await _insertReceipt(
        writer,
        id: 'Nu16celig01',
        beaconId: _forwardedBeaconIds.first,
      );
      expect(await expectAgreement(), isTrue);
    });

    test('a Request-less optional receipt makes it eligible too', () async {
      await _insertReceipt(writer, id: 'Nu16celig02', beaconId: null);
      expect(await expectAgreement(), isTrue);
    });

    test('a decided outcome row makes it eligible (Set O)', () async {
      await _insertInboxItem(writer, beaconId: _watchedBeaconId, status: 1);
      expect(await expectAgreement(), isTrue);
    });

    test(
      'an unanswered forward alone is NOT eligible, though for you.dot is on',
      () async {
        // The whole reason `forYouDot` cannot be the enablement signal.
        // `eligible_pinned` lights the dot and is never swept (owner A).
        await _insertInboxItem(writer, beaconId: _watchedBeaconId, status: 0);
        final summary = await query.surfaceSummary(accountId: _viewerId);
        expect(summary.forYouDot, isTrue, reason: 'a pin lights the tab');
        expect(await expectAgreement(), isFalse);
      },
    );

    test('a live obligation alone is not eligible', () async {
      // An obligation has no × and is never swept (D06, D07). It is also on
      // My Desk, so it is not this surface's business at all.
      await _insertReceipt(
        writer,
        id: 'Nu16celig03',
        beaconId: _ownedBeaconId,
        requiresAction: true,
      );
      expect(await expectAgreement(), isFalse);
    });

    test('a My Desk optional receipt alone is not eligible', () async {
      await _insertReceipt(
        writer,
        id: 'Nu16celig04',
        beaconId: _ownedBeaconId,
      );
      expect(await expectAgreement(), isFalse);
    });

    test('an already-cleared receipt alone is not eligible', () async {
      await _insertReceipt(
        writer,
        id: 'Nu16celig05',
        beaconId: _forwardedBeaconIds.first,
        cleared: true,
      );
      expect(await expectAgreement(), isFalse);
    });

    test('clearing the last dismissible row turns the flag off', () async {
      await _insertReceipt(
        writer,
        id: 'Nu16celig06',
        beaconId: _forwardedBeaconIds.first,
      );
      expect(await expectAgreement(), isTrue);

      await writer.execute(
        Sql.named(
          "UPDATE public.notification_outbox "
          "SET cleared_at = now(), clear_reason = 'explicit' "
          'WHERE id = @id',
        ),
        parameters: {'id': 'Nu16celig06'},
      );
      expect(await expectAgreement(), isFalse);
    });

    test(
      'a pin beside a dismissible receipt is eligible, and stays so after the '
      'receipt is the only thing swept',
      () async {
        await _insertInboxItem(writer, beaconId: _watchedBeaconId, status: 0);
        await _insertReceipt(
          writer,
          id: 'Nu16celig07',
          beaconId: _forwardedBeaconIds[2],
        );
        expect(await expectAgreement(), isTrue);

        await writer.execute(
          Sql.named(
            "UPDATE public.notification_outbox "
            "SET cleared_at = now(), clear_reason = 'explicit' "
            'WHERE id = @id',
          ),
          parameters: {'id': 'Nu16celig07'},
        );
        // Cleared means *no dismissible attention left*, not an empty screen:
        // the pin is still there, the tab dot is still on, and the button is
        // correctly dead.
        final summary = await query.surfaceSummary(accountId: _viewerId);
        expect(summary.forYouDot, isTrue);
        expect(await expectAgreement(), isFalse);
      },
    );
  }, skip: skipReason);
}

const _viewerId = 'Uu16celig01';
const _authorId = 'Uu16celig02';
const _ownedBeaconId = 'Bu16celigown';
const _watchedBeaconId = 'Bu16celigfwd1';
const _forwardedBeaconIds = [
  'Bu16celigfwd1',
  'Bu16celigfwd2',
  'Bu16celigfwd3',
];

/// The sweep's *own* capture statement, run verbatim. Nothing here paraphrases
/// it — that is the guard.
Future<int> _captureCount(Connection writer) async {
  final rows = await writer.execute(
    AttentionSweepRepository.captureSql,
    parameters: [_viewerId],
  );
  return rows.length;
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
        'id': 'Fu16celig$beaconId',
        'beaconId': beaconId,
        'senderId': _authorId,
        'recipientId': _viewerId,
      },
    );
  }
}

/// Forwarding already creates the inbox row, so the fixture sets a stance on
/// the row that is there.
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
  bool cleared = false,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key, cleared_at, clear_reason
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey, now(),
  @beaconId, @sourceEventKey,
  @destinationKind, @presentationKey, '{"eventType":"fixture"}'::jsonb,
  'standard', @accessPolicy,
  @requiresAction, @threadKey,
  CASE WHEN @cleared THEN now() ELSE NULL END,
  CASE WHEN @cleared THEN 'explicit' ELSE NULL END
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
    'cleared': cleared,
  },
);
