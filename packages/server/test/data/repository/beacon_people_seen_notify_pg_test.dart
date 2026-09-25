@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// m0198: `beacon_people_seen` watermark, `bridge_attention_people_seen`, and
/// the `people_seen` realtime fan-out (issue #178 plan P1.1).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_PEOPLE_SEEN_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_seen',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('beacon_people_seen people_seen NOTIFY + attention bridge', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
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
  public.beacon_help_offer,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [
        _authorId,
        _offererA,
        _offererB,
        _withdrawnId,
        _strangerId,
      ]) {
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
  (@beaconId, @authorId, 'People seen', 'People seen request', 0),
  (@lonelyId, @authorId, 'Lonely', 'Request without offers', 0)
'''),
        parameters: {
          'beaconId': _beaconId,
          'lonelyId': _lonelyBeaconId,
          'authorId': _authorId,
        },
      );
      await _insertOffer(writer, userId: _offererA, status: 0);
      await _insertOffer(writer, userId: _offererB, status: 0);
      await _insertOffer(writer, userId: _withdrawnId, status: 1);
      await _settle();
      notifications.clear();
    });

    tearDownAll(() async {
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    List<Map<String, dynamic>> peopleSeen() => notifications
        .where((message) => message['entity'] == 'people_seen')
        .toList();

    test(
      'INSERT emits one people_seen update to active offerers minus writer, '
      'without seen_user_id',
      () async {
        final seenAt = DateTime.utc(2026, 7, 20, 12);

        await _upsertPeopleSeen(
          writer,
          userId: _authorId,
          beaconId: _beaconId,
          at: seenAt,
        );

        await _waitUntil(() => peopleSeen().isNotEmpty);
        await _settle();
        final messages = peopleSeen();
        expect(messages, hasLength(1));
        final notify = messages.single;
        expect(notify['event'], 'update');
        expect(notify['entity'], 'people_seen');
        expect(
          (notify['user_ids']! as List).cast<String>().toSet(),
          {_offererA, _offererB},
        );
        expect(notify.containsKey('last_seen_at'), isTrue);
        expect(
          DateTime.parse(notify['last_seen_at'] as String).toUtc(),
          seenAt,
        );
        expect(notify.containsKey('seen_user_id'), isFalse);
      },
    );

    test('writer who is an offerer is excluded from recipients', () async {
      await _upsertPeopleSeen(
        writer,
        userId: _offererA,
        beaconId: _beaconId,
        at: DateTime.utc(2026, 7, 20, 13),
      );

      await _waitUntil(() => peopleSeen().isNotEmpty);
      await _settle();
      expect(peopleSeen(), hasLength(1));
      final recipients = (peopleSeen().single['user_ids']! as List)
          .cast<String>()
          .toSet();
      expect(recipients, {_offererB});
      expect(recipients, isNot(contains(_offererA)));
      expect(recipients, isNot(contains(_withdrawnId)));
    });

    test(
      'stale upsert kept by GREATEST emits nothing and bridges nothing',
      () async {
        final newer = DateTime.utc(2026, 7, 21, 12);
        final stale = DateTime.utc(2026, 7, 21, 10);

        await _upsertPeopleSeen(
          writer,
          userId: _authorId,
          beaconId: _beaconId,
          at: newer,
        );
        await _waitUntil(() => peopleSeen().isNotEmpty);

        // Created before both watermarks but inserted after the first upsert,
        // so only a (wrongly) re-run bridge could mark it.
        await _insertReceipt(
          writer,
          id: 'Npseen_stale',
          beaconId: _beaconId,
          createdAt: DateTime.utc(2026, 7, 21, 9),
        );
        await _settle();
        notifications.clear();

        await _upsertPeopleSeen(
          writer,
          userId: _authorId,
          beaconId: _beaconId,
          at: stale,
        );
        await _settle();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(peopleSeen(), isEmpty);
        expect(_notificationUpdates(notifications), isEmpty);
        await _assertUnread(writer, 'Npseen_stale');
        final row = await writer.execute(
          Sql.named('''
SELECT last_seen_at FROM public.beacon_people_seen
WHERE user_id = @userId AND beacon_id = @beaconId
'''),
          parameters: {'userId': _authorId, 'beaconId': _beaconId},
        );
        expect((row.single[0]! as DateTime).toUtc(), newer);
      },
    );

    test('advancing upsert emits a new people_seen update', () async {
      await _upsertPeopleSeen(
        writer,
        userId: _authorId,
        beaconId: _beaconId,
        at: DateTime.utc(2026, 7, 22, 10),
      );
      await _waitUntil(() => peopleSeen().isNotEmpty);
      notifications.clear();

      final advanced = DateTime.utc(2026, 7, 22, 11);
      await _upsertPeopleSeen(
        writer,
        userId: _authorId,
        beaconId: _beaconId,
        at: advanced,
      );
      await _waitUntil(() => peopleSeen().isNotEmpty);
      await _settle();
      expect(peopleSeen(), hasLength(1));
      expect(
        DateTime.parse(peopleSeen().single['last_seen_at'] as String).toUtc(),
        advanced,
      );
    });

    test(
      'no active offerers: no people_seen NOTIFY but the bridge still runs',
      () async {
        await _insertReceipt(
          writer,
          id: 'Npseen_lonely',
          beaconId: _lonelyBeaconId,
          createdAt: DateTime.utc(2026, 7, 23, 9),
        );
        await _settle();
        notifications.clear();

        await _upsertPeopleSeen(
          writer,
          userId: _authorId,
          beaconId: _lonelyBeaconId,
          at: DateTime.utc(2026, 7, 23, 12),
        );
        await _settle();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(peopleSeen(), isEmpty);
        await _assertSeen(writer, 'Npseen_lonely');
      },
    );

    test(
      'bridge marks only the writer help_offer_submitted receipts up to the '
      'watermark and leaves everything else untouched',
      () async {
        final watermark = DateTime.utc(2026, 7, 24, 12);
        final before = DateTime.utc(2026, 7, 24, 9);
        final after = DateTime.utc(2026, 7, 24, 15);

        await _insertReceipt(
          writer,
          id: 'Npseen_hit',
          beaconId: _beaconId,
          createdAt: before,
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_edge',
          beaconId: _beaconId,
          createdAt: watermark,
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_obligation',
          beaconId: _beaconId,
          createdAt: before,
          requiresAction: true,
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_future',
          beaconId: _beaconId,
          createdAt: after,
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_other_acct',
          accountId: _strangerId,
          beaconId: _beaconId,
          createdAt: before,
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_other_beacon',
          beaconId: _lonelyBeaconId,
          createdAt: before,
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_declined',
          beaconId: _beaconId,
          createdAt: before,
          presentationKey: 'offer_declined',
          accessPolicy: 'recipient_safe',
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_removed',
          beaconId: _beaconId,
          createdAt: before,
          presentationKey: 'offer_removed',
          accessPolicy: 'recipient_safe',
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_room_msg',
          beaconId: _beaconId,
          createdAt: before,
          destinationKind: 'beacon_room_message',
          presentationKey: 'room_message_posted',
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_wrong_dest',
          beaconId: _beaconId,
          createdAt: before,
          destinationKind: 'beacon',
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_settled',
          beaconId: _beaconId,
          createdAt: before,
          requiresAction: true,
        );
        await writer.execute(
          Sql.named('''
UPDATE public.notification_outbox
SET settlement_kind = 'resolved',
    settled_at = '2026-07-24T10:00:00Z'::timestamptz,
    settled_by_user_id = @settledBy,
    settled_by_occurrence_id = 'Occpseen01',
    logical_task_key = 'ltk-Npseen_settled',
    lifecycle_generation = 3
WHERE id = 'Npseen_settled'
'''),
          parameters: {'settledBy': _offererA},
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_cleared',
          beaconId: _beaconId,
          createdAt: before,
        );
        await writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = '2026-07-24T10:30:00Z'::timestamptz,
    clear_reason = 'explicit'
WHERE id = 'Npseen_cleared'
''');
        final obligationBefore = await _lifecycleColumns(
          writer,
          'Npseen_obligation',
        );
        final settledBefore = await _lifecycleColumns(
          writer,
          'Npseen_settled',
        );
        final clearedBefore = await _lifecycleColumns(writer, 'Npseen_cleared');
        expect(obligationBefore.first, isTrue);
        expect(settledBefore[1], 'resolved');
        expect(settledBefore[2], isNotNull);
        expect(clearedBefore[5], 'explicit');

        await _upsertPeopleSeen(
          writer,
          userId: _authorId,
          beaconId: _beaconId,
          at: watermark,
        );

        await _assertSeen(writer, 'Npseen_hit');
        await _assertSeen(writer, 'Npseen_edge');
        await _assertSeen(writer, 'Npseen_obligation');
        await _assertSeen(writer, 'Npseen_settled');
        await _assertSeen(writer, 'Npseen_cleared');
        for (final id in [
          'Npseen_future',
          'Npseen_other_acct',
          'Npseen_other_beacon',
          'Npseen_declined',
          'Npseen_removed',
          'Npseen_room_msg',
          'Npseen_wrong_dest',
        ]) {
          await _assertUnread(writer, id);
        }

        expect(
          await _lifecycleColumns(writer, 'Npseen_obligation'),
          obligationBefore,
        );
        expect(
          await _lifecycleColumns(writer, 'Npseen_settled'),
          settledBefore,
        );
        expect(
          await _lifecycleColumns(writer, 'Npseen_cleared'),
          clearedBefore,
        );
      },
    );

    test(
      'exactly one notification update reaches the writer when a receipt is '
      'marked',
      () async {
        await _insertReceipt(
          writer,
          id: 'Npseen_rt1',
          beaconId: _beaconId,
          createdAt: DateTime.utc(2026, 7, 25, 9),
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_rt2',
          beaconId: _beaconId,
          createdAt: DateTime.utc(2026, 7, 25, 10),
        );
        await _settle();
        notifications.clear();

        await _upsertPeopleSeen(
          writer,
          userId: _authorId,
          beaconId: _beaconId,
          at: DateTime.utc(2026, 7, 25, 12),
        );

        await _waitUntil(
          () => _notificationUpdates(notifications).isNotEmpty,
        );
        await _settle();
        expect(_notificationUpdates(notifications), [
          {
            'event': 'update',
            'entity': 'notification',
            'id': _authorId,
            'user_ids': [_authorId],
          },
        ]);
      },
    );

    test(
      'non-owner writer: bridge marks and notifies only the writer, not the '
      'request owner',
      () async {
        final before = DateTime.utc(2026, 7, 29, 9);
        await _insertReceipt(
          writer,
          id: 'Npseen_writer_rcpt',
          accountId: _offererA,
          beaconId: _beaconId,
          createdAt: before,
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_owner_rcpt',
          beaconId: _beaconId,
          createdAt: before,
        );
        await _insertReceipt(
          writer,
          id: 'Npseen_peer_rcpt',
          accountId: _offererB,
          beaconId: _beaconId,
          createdAt: before,
        );
        await _settle();
        notifications.clear();

        await _upsertPeopleSeen(
          writer,
          userId: _offererA,
          beaconId: _beaconId,
          at: DateTime.utc(2026, 7, 29, 12),
        );

        await _waitUntil(
          () => _notificationUpdates(notifications).isNotEmpty,
        );
        await _settle();
        await _assertSeen(writer, 'Npseen_writer_rcpt');
        await _assertUnread(writer, 'Npseen_owner_rcpt');
        await _assertUnread(writer, 'Npseen_peer_rcpt');
        expect(_notificationUpdates(notifications), [
          {
            'event': 'update',
            'entity': 'notification',
            'id': _offererA,
            'user_ids': [_offererA],
          },
        ]);
      },
    );

    test(
      'm0198 schema: composite PK, cascading FKs, beacon_id index, comment, '
      'trigger',
      () async {
        final pk = await writer.execute('''
SELECT array_agg(a.attname::text ORDER BY k.ord)
FROM pg_constraint c
CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
JOIN pg_attribute a
  ON a.attrelid = c.conrelid AND a.attnum = k.attnum
WHERE c.conrelid = 'public.beacon_people_seen'::regclass AND c.contype = 'p'
''');
        expect(pk.single[0], ['user_id', 'beacon_id']);

        final fks = await writer.execute('''
SELECT a.attname::text, c.confrelid::regclass::text, c.confdeltype::text
FROM pg_constraint c
JOIN pg_attribute a
  ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
WHERE c.conrelid = 'public.beacon_people_seen'::regclass AND c.contype = 'f'
ORDER BY 1
''');
        expect(
          fks.map((row) => row.toList()).toList(),
          [
            ['beacon_id', 'beacon', 'c'],
            ['user_id', '"user"', 'c'],
          ],
        );

        final index = await writer.execute('''
SELECT indexdef FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'beacon_people_seen'
  AND indexname = 'beacon_people_seen_beacon_idx'
''');
        expect(index, hasLength(1));
        expect(index.single[0], contains('(beacon_id)'));

        final comment = await writer.execute(
          "SELECT obj_description('public.beacon_people_seen'::regclass, 'pg_class')",
        );
        expect(comment.single[0], isA<String>());
        expect((comment.single[0]! as String).trim(), isNotEmpty);

        final trigger = await writer.execute('''
SELECT pg_get_triggerdef(t.oid)
FROM pg_trigger t
WHERE t.tgrelid = 'public.beacon_people_seen'::regclass
  AND t.tgname = 'beacon_people_seen_notify'
  AND NOT t.tgisinternal
''');
        expect(trigger, hasLength(1));
        final def = trigger.single[0]! as String;
        expect(def, contains('AFTER INSERT OR UPDATE OF last_seen_at'));
        expect(def, contains('notify_people_seen_change()'));

        final bridge = await writer.execute('''
SELECT count(*) FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'bridge_attention_people_seen'
''');
        expect(bridge.single[0], 1);
      },
    );

    test(
      'cascade: deleting the request removes its people-seen watermarks',
      () async {
        await _upsertPeopleSeen(
          writer,
          userId: _authorId,
          beaconId: _lonelyBeaconId,
          at: DateTime.utc(2026, 7, 26, 12),
        );
        await writer.execute(
          Sql.named('DELETE FROM public.beacon WHERE id = @id'),
          parameters: {'id': _lonelyBeaconId},
        );
        final rows = await writer.execute(
          Sql.named(
            'SELECT 1 FROM public.beacon_people_seen WHERE beacon_id = @id',
          ),
          parameters: {'id': _lonelyBeaconId},
        );
        expect(rows, isEmpty);
      },
    );

    test(
      'bridge failure is NOT swallowed: the watermark write aborts',
      () async {
        await _insertReceipt(
          writer,
          id: 'Npseen_bridge_fail',
          beaconId: _beaconId,
          createdAt: DateTime.utc(2026, 7, 27, 9),
        );
        await writer.execute(r'''
CREATE OR REPLACE FUNCTION public.test_people_seen_fail_outbox_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'test: forced bridge failure';
END
$$
''');
        await writer.execute('''
CREATE TRIGGER test_people_seen_fail_outbox_update
BEFORE UPDATE OF seen_at ON public.notification_outbox
FOR EACH ROW EXECUTE FUNCTION public.test_people_seen_fail_outbox_update()
''');
        try {
          await expectLater(
            _upsertPeopleSeen(
              writer,
              userId: _authorId,
              beaconId: _beaconId,
              at: DateTime.utc(2026, 7, 27, 12),
            ),
            throwsA(
              isA<ServerException>().having(
                (error) => error.message,
                'message',
                contains('forced bridge failure'),
              ),
            ),
          );
        } finally {
          await writer.execute(
            'DROP TRIGGER IF EXISTS test_people_seen_fail_outbox_update '
            'ON public.notification_outbox',
          );
          await writer.execute(
            'DROP FUNCTION IF EXISTS '
            'public.test_people_seen_fail_outbox_update()',
          );
        }

        final rows = await writer.execute(
          Sql.named('''
SELECT 1 FROM public.beacon_people_seen
WHERE user_id = @userId AND beacon_id = @beaconId
'''),
          parameters: {'userId': _authorId, 'beaconId': _beaconId},
        );
        expect(rows, isEmpty);
        await _assertUnread(writer, 'Npseen_bridge_fail');
        await _settle();
        expect(peopleSeen(), isEmpty);
      },
    );

    test(
      'fan-out failure is caught: the write and the bridge still commit',
      () async {
        await _insertReceipt(
          writer,
          id: 'Npseen_fanout_fail',
          beaconId: _beaconId,
          createdAt: DateTime.utc(2026, 7, 28, 9),
        );
        await _settle();
        notifications.clear();

        // Recipients come from beacon_help_offer; hold an exclusive lock on it
        // so the fan-out's read hits lock_timeout inside its EXCEPTION block.
        final locker = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        final locked = Completer<void>();
        final release = Completer<void>();
        final lockTx = locker.runTx((tx) async {
          await tx.execute(
            'LOCK TABLE public.beacon_help_offer IN ACCESS EXCLUSIVE MODE',
          );
          locked.complete();
          await release.future;
        });
        try {
          await locked.future;
          await writer.execute("SET lock_timeout = '300ms'");
          await _upsertPeopleSeen(
            writer,
            userId: _authorId,
            beaconId: _beaconId,
            at: DateTime.utc(2026, 7, 28, 12),
          );
        } finally {
          await writer.execute('RESET lock_timeout');
          if (!release.isCompleted) release.complete();
          await lockTx;
          await locker.close();
        }

        final rows = await writer.execute(
          Sql.named('''
SELECT last_seen_at FROM public.beacon_people_seen
WHERE user_id = @userId AND beacon_id = @beaconId
'''),
          parameters: {'userId': _authorId, 'beaconId': _beaconId},
        );
        expect(rows, hasLength(1));
        expect(
          (rows.single[0]! as DateTime).toUtc(),
          DateTime.utc(2026, 7, 28, 12),
        );
        await _assertSeen(writer, 'Npseen_fanout_fail');
        await _settle();
        expect(peopleSeen(), isEmpty);
      },
    );
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

const _authorId = 'Upseen01';
const _offererA = 'Upseen02';
const _offererB = 'Upseen03';
const _withdrawnId = 'Upseen04';
const _strangerId = 'Upseen05';
const _beaconId = 'Bpseenmain';
const _lonelyBeaconId = 'Bpseenlonely';

Future<void> _insertOffer(
  Connection writer, {
  required String userId,
  required int status,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status)
VALUES (@beaconId, @userId, 'I can help', @status)
'''),
  parameters: {'beaconId': _beaconId, 'userId': userId, 'status': status},
);

Future<void> _upsertPeopleSeen(
  Connection writer, {
  required String userId,
  required String beaconId,
  required DateTime at,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_people_seen (user_id, beacon_id, last_seen_at)
VALUES (@userId, @beaconId, @at)
ON CONFLICT (user_id, beacon_id)
DO UPDATE SET last_seen_at = GREATEST(
  beacon_people_seen.last_seen_at, EXCLUDED.last_seen_at
)
'''),
  parameters: {'userId': userId, 'beaconId': beaconId, 'at': at},
);

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  required DateTime createdAt,
  String accountId = _authorId,
  String destinationKind = 'beacon_people_offer',
  String presentationKey = 'help_offer_submitted',
  String accessPolicy = 'beacon_content',
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
  'Title', 'Body', '/attention', @dedupKey, @createdAt,
  @beaconId, @sourceEventKey,
  @destinationKind, @presentationKey, '{"eventType":"fixture"}'::jsonb,
  'standard', @accessPolicy,
  @requiresAction, @threadKey
)
'''),
  parameters: {
    'id': id,
    'accountId': accountId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'destinationKind': destinationKind,
    'presentationKey': presentationKey,
    'accessPolicy': accessPolicy,
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$accountId' : null,
  },
);

/// Everything the bridge must not touch: obligation, settlement, clear and
/// read state.
Future<List<Object?>> _lifecycleColumns(Connection writer, String id) async {
  final result = await writer.execute(
    Sql.named('''
SELECT requires_action, settlement_kind, settled_at, settled_by_user_id,
       settled_by_occurrence_id, clear_reason, cleared_at,
       logical_task_key, lifecycle_generation, read_at, attention_thread_key
FROM public.notification_outbox
WHERE id = @id
'''),
    parameters: {'id': id},
  );
  return result.single.toList();
}

Future<void> _assertSeen(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named('SELECT seen_at FROM public.notification_outbox WHERE id = @id'),
    parameters: {'id': id},
  );
  expect(row.single[0], isNotNull, reason: '$id should be marked seen');
}

Future<void> _assertUnread(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named('SELECT seen_at FROM public.notification_outbox WHERE id = @id'),
    parameters: {'id': id},
  );
  expect(row.single[0], isNull, reason: '$id should stay unread');
}
