@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_MARK_BEACON_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_mark_beacon',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('markSeenForBeacon', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];
    late TenturaDb database;
    late AttentionAckRepository ack;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      ack = AttentionAckRepository(database);

      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) => notifications.add(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      );
      await _settle();
      notifications.clear();
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
      notifications.clear();
    });

    tearDownAll(() async {
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test('marks only visible unseen receipts for the given beacon', () async {
      await _insertBeaconReceipt(
        writer,
        id: 'Nmark01a',
        beaconId: _ownedBeaconId,
      );
      await _insertBeaconReceipt(
        writer,
        id: 'Nmark01b',
        beaconId: _ownedBeaconId,
      );
      await _insertBeaconReceipt(
        writer,
        id: 'Nmark01c',
        beaconId: _foreignBeaconId,
      );

      expect(
        await ack.markSeenForBeacon(
          accountId: _viewerId,
          beaconId: _ownedBeaconId,
        ),
        2,
      );
      await _assertSeen(writer, 'Nmark01a');
      await _assertSeen(writer, 'Nmark01b');
      await _assertUnread(writer, 'Nmark01c');
    });

    test(
      'sets seen_at on live obligations without touching settlement columns',
      () async {
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nmark02',
          beaconId: _ownedBeaconId,
        );

        expect(
          await ack.markSeenForBeacon(
            accountId: _viewerId,
            beaconId: _ownedBeaconId,
          ),
          1,
        );

        final row = await writer.execute(
          Sql.named('''
SELECT seen_at, settlement_kind, settled_at, requires_action
FROM public.notification_outbox
WHERE id = @id
'''),
          parameters: {'id': 'Nmark02'},
        );
        expect(row.single[0], isNotNull);
        expect(row.single[1], isNull);
        expect(row.single[2], isNull);
        expect(row.single[3], isTrue);
      },
    );

    test('ignores receipts outside visible_attention_receipts', () async {
      await _insertBeaconReceipt(
        writer,
        id: 'Nmark03visible',
        beaconId: _ownedBeaconId,
      );
      await _insertHiddenBeaconReceipt(
        writer,
        id: 'Nmark03hidden',
        beaconId: _hiddenBeaconId,
      );

      expect(
        await ack.markSeenForBeacon(
          accountId: _viewerId,
          beaconId: _hiddenBeaconId,
        ),
        0,
      );
      await _assertUnread(writer, 'Nmark03hidden');
      await _assertUnread(writer, 'Nmark03visible');

      expect(
        await ack.markSeenForBeacon(
          accountId: _viewerId,
          beaconId: _ownedBeaconId,
        ),
        1,
      );
      await _assertSeen(writer, 'Nmark03visible');
      await _assertUnread(writer, 'Nmark03hidden');
    });

    test('seen_at update emits a realtime notification update', () async {
      await _insertBeaconReceipt(
        writer,
        id: 'Nmark04',
        beaconId: _ownedBeaconId,
      );
      await _settle();
      notifications.clear();

      expect(
        await ack.markSeenForBeacon(
          accountId: _viewerId,
          beaconId: _ownedBeaconId,
        ),
        1,
      );

      await _waitUntil(
        () => _notificationUpdates(notifications).isNotEmpty,
      );
      expect(_notificationUpdates(notifications), [
        {
          'event': 'update',
          'entity': 'notification',
          'id': _viewerId,
          'user_ids': [_viewerId],
        },
      ]);
    });
  }, skip: skipReason);
}

List<Map<String, dynamic>> _notificationUpdates(
  List<Map<String, dynamic>> notifications,
) => notifications
    .where(
      (message) =>
          message['entity'] == 'notification' && message['event'] == 'update',
    )
    .toList();

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

const _viewerId = 'Uattnmark01';
const _authorId = 'Uattnmark02';
const _otherId = 'Uattnmark03';
const _ownedBeaconId = 'Battnmarkown';
const _foreignBeaconId = 'Battnmarkfore';
const _hiddenBeaconId = 'Battnmarkhid';

Future<void> _insertBeaconReceipt(
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
  'Title', 'Body', '/attention', @dedupKey,
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
  '2026-07-16T12:00:00Z'::timestamptz,
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
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'threadKey': 'v1|needsMe|$id|$_viewerId',
  },
);

Future<void> _assertSeen(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named('SELECT seen_at FROM public.notification_outbox WHERE id = @id'),
    parameters: {'id': id},
  );
  expect(row.single[0], isNotNull);
}

Future<void> _assertUnread(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named('SELECT seen_at FROM public.notification_outbox WHERE id = @id'),
    parameters: {'id': id},
  );
  expect(row.single[0], isNull);
}
