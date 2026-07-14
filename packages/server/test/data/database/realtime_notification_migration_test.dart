@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final env = _testEnv();
  final reachable = await _canConnect(env);
  final skipReason = reachable ? false : 'local Postgres not reachable';

  group('m0114 realtime notification contract', () {
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      writer = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      await migrateDbSchema(writer);
      listener = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) => notifications.add(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      );
    });

    setUp(() async {
      await _settle();
      notifications.clear();
    });

    tearDownAll(() async {
      await notificationSubscription.cancel();
      await listener.close();
      await writer.close();
    });

    test(
      'all generic trigger arguments and publishers are enumerated',
      () async {
        final triggerRows = await writer.execute('''
SELECT encode(t.tgargs, 'escape')
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND p.proname = 'notify_entity_change'
ORDER BY 1
''');
        final arguments = triggerRows
            .map((row) => (row[0]! as String).replaceAll(r'\000', ''))
            .toSet();

        expect(
          arguments,
          containsAll(<String>{
            'beacon',
            'forward',
            'help_offer',
            'room_message',
            'participant',
            'fact_card',
            'activity_event',
            'coordination_item',
            'person_capability_event',
            'inbox_item',
            'contact',
            'room_reaction',
            'room_poll',
            'room_poll_act',
            'room_seen',
            'profile',
            'notification',
          }),
        );

        final publisherRows = await writer.execute('''
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND pg_get_functiondef(p.oid) LIKE '%pg_notify(''entity_changes''%'
ORDER BY p.proname
''');
        expect(
          publisherRows.map((row) => row[0]),
          ['emit_realtime_entity_change'],
        );

        final relationshipRows = await writer.execute('''
SELECT c.relname, count(*), bool_and((t.tgtype & 1) = 0)
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND p.proname = 'notify_relationship_change'
GROUP BY c.relname
ORDER BY c.relname
''');
        expect(
          relationshipRows.map((row) => (row[0], row[1], row[2])),
          [
            ('user_trust_edge', 3, true),
            ('vote_user', 3, true),
          ],
        );
      },
      skip: skipReason,
    );

    test(
      'actor is retained and several hundred recipients are byte chunked',
      () async {
        final recipients = [
          for (var i = 0; i < 350; i++)
            'U${i.toRadixString(16).padLeft(12, '0')}',
        ];
        const actor = 'U000000000001';
        final sqlArray = recipients.map((id) => "'$id'").join(',');

        await writer.execute('BEGIN');
        await writer.execute(
          r"SELECT set_config('tentura.mutating_user_id', $1, true)",
          parameters: [actor],
        );
        await writer.execute('''
SELECT public.emit_realtime_entity_change(
  'beacon', 'Brealtime0001', 'update', ARRAY[$sqlArray]::text[]
)
''');
        await writer.execute('COMMIT');

        await _waitUntil(() => _ofKind(notifications, 'beacon').length == 4);
        final chunks = _ofKind(notifications, 'beacon');
        expect(chunks, hasLength(4));
        expect(
          chunks.expand((message) => message['user_ids']! as List).toSet(),
          recipients.toSet(),
        );
        for (final message in chunks) {
          expect(message['actor_user_id'], actor);
          expect((message['user_ids']! as List).length, lessThanOrEqualTo(100));
          expect(utf8.encode(jsonEncode(message)).length, lessThan(7900));
        }
      },
      skip: skipReason,
    );

    test(
      'bulk relationship writes coalesce through a statement trigger',
      () async {
        await writer.execute('''
CREATE TEMP TABLE realtime_relationship_batch (
  subject text NOT NULL,
  object text NOT NULL
)
''');
        await writer.execute('''
CREATE TRIGGER realtime_relationship_batch_notify
  AFTER INSERT ON realtime_relationship_batch
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_relationship_change()
''');
        final values = [
          for (var i = 0; i < 300; i++)
            "('U${i.toRadixString(16).padLeft(12, '0')}','U${(i + 300).toRadixString(16).padLeft(12, '0')}')",
        ].join(',');

        await writer.execute('BEGIN');
        await writer.execute(
          'INSERT INTO realtime_relationship_batch (subject, object) VALUES $values',
        );
        await writer.execute('COMMIT');

        await _waitUntil(
          () => _ofKind(notifications, 'relationship').length == 6,
        );
        final changes = _ofKind(notifications, 'relationship');
        expect(changes, hasLength(6));
        expect(
          changes.expand((message) => message['subject_ids']! as List).toSet(),
          hasLength(600),
        );
      },
      skip: skipReason,
    );

    test(
      'row trigger emits insert, update, and delete with actor metadata',
      () async {
        const viewerId = 'Urtcontact001';
        const subjectId = 'Urtcontact002';
        addTearDown(() async {
          await writer.execute(
            Sql.named(
              'DELETE FROM public."user" WHERE id IN (@viewerId, @subjectId)',
            ),
            parameters: {'viewerId': viewerId, 'subjectId': subjectId},
          );
        });
        for (final entry in [
          (viewerId, 'realtime-contact-viewer-key'),
          (subjectId, 'realtime-contact-subject-key'),
        ]) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
ON CONFLICT (id) DO NOTHING
'''),
            parameters: {'id': entry.$1, 'key': entry.$2},
          );
        }
        await _settle();
        notifications.clear();

        Future<Map<String, dynamic>> mutate(
          String operation,
          String statement,
        ) async {
          await writer.execute('BEGIN');
          await writer.execute(
            r"SELECT set_config('tentura.mutating_user_id', $1, true)",
            parameters: [viewerId],
          );
          await writer.execute(
            Sql.named(statement),
            parameters: {
              'viewerId': viewerId,
              'subjectId': subjectId,
            },
          );
          await writer.execute('COMMIT');
          await _waitUntil(() => _ofKind(notifications, 'contact').isNotEmpty);
          final change = _ofKind(notifications, 'contact').single;
          expect(change['event'], operation);
          expect(change['id'], subjectId);
          expect(change['user_ids'], [viewerId]);
          expect(change['subject_ids'], [subjectId]);
          expect(change['actor_user_id'], viewerId);
          notifications.clear();
          return change;
        }

        await mutate('insert', '''
INSERT INTO public.user_contact (viewer_id, subject_id, contact_name)
VALUES (@viewerId, @subjectId, 'First name')
''');
        await mutate('update', '''
UPDATE public.user_contact
SET contact_name = 'Updated name'
WHERE viewer_id = @viewerId AND subject_id = @subjectId
''');
        await mutate('delete', '''
DELETE FROM public.user_contact
WHERE viewer_id = @viewerId AND subject_id = @subjectId
''');
      },
      skip: skipReason,
    );

    test('room_seen no-op update emits no feedback invalidation', () async {
      const userId = 'Urtseen000001';
      const beaconId = 'Brtseen000001';
      addTearDown(() async {
        await writer.execute(
          Sql.named('DELETE FROM public."user" WHERE id = @id'),
          parameters: {'id': userId},
        );
      });
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Realtime seen', @key)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {'id': userId, 'key': 'realtime-seen-public-key'},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES (@id, @userId, 'Realtime', 'Room seen trigger test')
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {'id': beaconId, 'userId': userId},
      );
      await _settle();
      notifications.clear();

      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_seen (
  user_id, beacon_id, thread_item_id, last_seen_at
) VALUES (@userId, @beaconId, NULL, '2026-07-14T10:00:00Z')
ON CONFLICT (user_id, beacon_id) WHERE thread_item_id IS NULL
DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
'''),
        parameters: {'userId': userId, 'beaconId': beaconId},
      );
      await _waitUntil(() => _ofKind(notifications, 'room_seen').length == 1);
      notifications.clear();

      await writer.execute(
        Sql.named('''
UPDATE public.beacon_room_seen
SET last_seen_at = last_seen_at
WHERE user_id = @userId AND beacon_id = @beaconId AND thread_item_id IS NULL
'''),
        parameters: {'userId': userId, 'beaconId': beaconId},
      );
      await _settle();
      expect(_ofKind(notifications, 'room_seen'), isEmpty);

      await writer.execute(
        Sql.named('''
UPDATE public.beacon_room_seen
SET last_seen_at = '2026-07-14T10:01:00Z'
WHERE user_id = @userId AND beacon_id = @beaconId AND thread_item_id IS NULL
'''),
        parameters: {'userId': userId, 'beaconId': beaconId},
      );
      await _waitUntil(() => _ofKind(notifications, 'room_seen').length == 1);
    }, skip: skipReason);
  }, skip: skipReason);
}

List<Map<String, dynamic>> _ofKind(
  List<Map<String, dynamic>> notifications,
  String kind,
) => notifications.where((message) => message['entity'] == kind).toList();

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

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: '127.0.0.1',
  pgPort: 5432,
  pgPassword: 'password',
  printEnv: false,
  isDebugModeOn: false,
);
