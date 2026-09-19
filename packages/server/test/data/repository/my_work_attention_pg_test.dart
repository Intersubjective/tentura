@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_clear_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MY_WORK_ATTENTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_my_work_attn',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('myWorkAttention', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;
    late AttentionClearCase clear;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      query = AttentionRepository(database);
      clear = AttentionClearCase(AttentionClearRepository(database));
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_forward_edge,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_viewerId, _authorId, _otherId]) {
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
  (@foreignId, @authorId, 'Foreign', 'Foreign request', 0),
  (@hiddenId, @otherId, 'Hidden', 'Hidden request', 0)
'''),
        parameters: {
          'ownedId': _ownedBeaconId,
          'foreignId': _foreignBeaconId,
          'hiddenId': _hiddenBeaconId,
          'viewerId': _viewerId,
          'authorId': _authorId,
          'otherId': _otherId,
        },
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test(
      'aggregates news and obligations with correct latest unseen and ordering',
      () async {
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nmw01o1',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T10:00:00Z',
        );
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nmw01o2',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T14:00:00Z',
        );
        await _insertBeaconReceipt(
          writer,
          id: 'Nmw01n1',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T11:00:00Z',
        );
        await _insertBeaconReceipt(
          writer,
          id: 'Nmw01n2',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T12:00:00Z',
        );
        await _insertBeaconReceipt(
          writer,
          id: 'Nmw01n3',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T13:00:00Z',
        );

        final result = await query.myWorkAttention(
          accountId: _viewerId,
          beaconIds: {_ownedBeaconId},
        );

        expect(result, hasLength(1));
        final projection = result.single;
        expect(projection.beaconId, _ownedBeaconId);
        // CHANGED IN U10b (was 5 — every unseen receipt, obligations
        // included). `unseenCount` is now the *optional* axis only: three
        // uncleared news rows. The two obligations are not lost, they are
        // counted by `liveObligations` below — D09 keeps the dot (optional)
        // and the number (obligations) independent, and a field that summed
        // both could only ever drive one of them correctly.
        expect(projection.unseenCount, 3);
        expect(projection.latestUnseen?.id, 'Nmw01n3');
        expect(
          projection.liveObligations.map((receipt) => receipt.id).toList(),
          ['Nmw01o2', 'Nmw01o1'],
        );
      },
    );

    test('includes seen-but-unsettled obligations when unseen count is zero', () async {
      await _insertLiveObligationReceipt(
        writer,
        id: 'Nmw02',
        beaconId: _ownedBeaconId,
        createdAt: '2026-07-16T12:00:00Z',
      );
      await writer.execute(
        Sql.named('''
UPDATE public.notification_outbox
SET seen_at = now()
WHERE id = @id
'''),
        parameters: {'id': 'Nmw02'},
      );

      final result = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId},
      );

      expect(result, hasLength(1));
      expect(result.single.unseenCount, 0);
      expect(result.single.latestUnseen, isNull);
      expect(result.single.liveObligations.single.id, 'Nmw02');
      expect(result.single.liveObligations.single.isLiveObligation, isTrue);
    });

    // U15R-a / R8 — clearing the last event must not move the card.
    //
    // `firstEntryAt` is the desk's stable ordering key; without it the client
    // falls back to `beacon.createdAt`, which here is deliberately a
    // different instant. So a card whose last optional event is cleared used
    // to jump, and jump back again when the next event arrived — the exact
    // "an optional update never changes a position" rule of section 6,
    // broken by the gesture that is supposed to quieten the card.
    test('the ordering anchor survives losing every active attention row',
        () async {
      await _insertBeaconReceipt(
        writer,
        id: 'NmwR8a',
        beaconId: _ownedBeaconId,
        createdAt: '2026-07-16T10:00:00Z',
      );

      final before = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId},
      );
      final anchor = before.single.firstEntryAt;
      expect(anchor, isNotNull);
      final createdAt = await _beaconCreatedAt(writer, _ownedBeaconId);
      expect(
        anchor,
        isNot(createdAt),
        reason: 'the fallback and the anchor must differ, or this proves '
            'nothing',
      );

      // Cleared through the real command, not by hand: the quantity under
      // test is what the clear path actually leaves behind.
      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
        kind: AttentionClearCaptureKind.explicit,
      );
      final cleared = await clear.clear(
        accountId: _viewerId,
        operationId: 'OPmwR8',
        snapshotToken: snapshot.token,
      );
      expect(cleared.appliedReceiptIds, ['NmwR8a']);

      final after = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId},
      );
      expect(after, hasLength(1));
      expect(after.single.unseenCount, 0);
      expect(after.single.latestUnseen, isNull);
      expect(after.single.liveObligations, isEmpty);
      expect(
        after.single.firstEntryAt,
        anchor,
        reason: 'the card is quiet, not gone — it keeps its place',
      );

      // …and the next optional event does not re-establish a new place.
      await _insertBeaconReceipt(
        writer,
        id: 'NmwR8b',
        beaconId: _ownedBeaconId,
        createdAt: '2026-08-20T10:00:00Z',
      );
      final again = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId},
      );
      expect(again.single.unseenCount, 1);
      expect(again.single.firstEntryAt, anchor);
    });

    test('omits beacons outside responsibility scope even when requested', () async {
      await _insertBeaconReceipt(
        writer,
        id: 'Nmw03',
        beaconId: _foreignBeaconId,
        createdAt: '2026-07-16T12:00:00Z',
      );

      final result = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_foreignBeaconId},
      );

      expect(result, isEmpty);
    });

    test(
      'ignores receipts outside visible_attention_receipts for counts and emission',
      () async {
        await _insertHiddenBeaconReceipt(
          writer,
          id: 'Nmw04hidden',
          beaconId: _hiddenBeaconId,
        );

        final result = await query.myWorkAttention(
          accountId: _viewerId,
          beaconIds: {_hiddenBeaconId},
        );

        expect(result, isEmpty);
      },
    );

    test('returns empty list when requested beacons have nothing to report', () async {
      final result = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId, _foreignBeaconId},
      );

      expect(result, isEmpty);
    });

    test('returns empty list for empty beacon id input', () async {
      expect(
        await query.myWorkAttention(accountId: _viewerId, beaconIds: const {}),
        isEmpty,
      );
    });
  }, skip: skipReason);
}

const _viewerId = 'Umyworkattn01';
const _authorId = 'Umyworkattn02';
const _otherId = 'Umyworkattn03';
const _ownedBeaconId = 'Bmyworkattnown';
const _foreignBeaconId = 'Bmyworkattnfore';
const _hiddenBeaconId = 'Bmyworkattnhid';

Future<void> _insertBeaconReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  required String createdAt,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content'
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
  },
);

Future<void> _insertHiddenBeaconReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Hidden title', 'Hidden body', '/attention', @dedupKey,
  '2026-07-16T12:00:00Z'::timestamptz,
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content'
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
  },
);

Future<void> _insertLiveObligationReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  required String createdAt,
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
  @id, @accountId, 'asksOfMe', 'needsMe', 'normal',
  'Obligation', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  true, @threadKey
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'threadKey': 'v1|needsMe|$id|$_viewerId',
  },
);


Future<DateTime?> _beaconCreatedAt(Connection writer, String beaconId) async {
  final rows = await writer.execute(
    Sql.named('SELECT created_at FROM public.beacon WHERE id = @id'),
    parameters: {'id': beaconId},
  );
  return rows.isEmpty ? null : (rows.first.first! as DateTime).toUtc();
}
