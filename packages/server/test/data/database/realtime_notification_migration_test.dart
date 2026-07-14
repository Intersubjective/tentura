@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      // The developer database may already record version 0114 while this
      // unpushed migration is still being refined. Reapply its idempotent
      // statements so this contract test always exercises the checked-out
      // source, not a stale function body from an earlier local run.
      for (final statement in m0114.statements) {
        await writer.execute(statement);
      }
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

        final contractEntries = _contractEntries();
        final expectedArguments = contractEntries
            .expand(
              (entry) => (entry['genericTriggerArgs']! as List).cast<String>(),
            )
            .toSet();
        expect(arguments, expectedArguments);

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

        final expectedSpecializedPublishers = contractEntries
            .expand(
              (entry) =>
                  (entry['specializedPublishers']! as List).cast<String>(),
            )
            .toSet();
        final specializedRows = await writer.execute('''
SELECT DISTINCT p.proname
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
ORDER BY p.proname
''');
        final attachedPublishers = specializedRows
            .map((row) => row[0]! as String)
            .where(expectedSpecializedPublishers.contains)
            .toSet();
        expect(attachedPublishers, expectedSpecializedPublishers);

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
        final entityId =
            'Brealtime${DateTime.timestamp().microsecondsSinceEpoch}';
        const actor = 'U000000000001';
        final sqlArray = recipients.map((id) => "'$id'").join(',');

        await writer.execute('BEGIN');
        await writer.execute(
          r"SELECT set_config('tentura.mutating_user_id', $1, true)",
          parameters: [actor],
        );
        await writer.execute('''
SELECT public.emit_realtime_entity_change(
  'beacon', '$entityId', 'update', ARRAY[$sqlArray]::text[]
)
''');
        await writer.execute('COMMIT');

        List<Map<String, dynamic>> testChanges() => _ofKind(
          notifications,
          'beacon',
        ).where((message) => message['id'] == entityId).toList();

        await _waitUntil(() => testChanges().length == 4);
        final chunks = testChanges();
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
        final subjectPrefix =
            'realtime_${DateTime.timestamp().microsecondsSinceEpoch}_';
        final subjects = [
          for (var i = 0; i < 600; i++)
            '$subjectPrefix${i.toRadixString(16).padLeft(3, '0')}',
        ];
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
            "('${subjects[i]}','${subjects[i + 300]}')",
        ].join(',');

        await writer.execute('BEGIN');
        await writer.execute(
          'INSERT INTO realtime_relationship_batch (subject, object) VALUES $values',
        );
        await writer.execute('COMMIT');

        List<Map<String, dynamic>> testChanges() =>
            _ofKind(
                  notifications,
                  'relationship',
                )
                .where(
                  (message) =>
                      (message['id']! as String).startsWith(subjectPrefix),
                )
                .toList();

        await _waitUntil(
          () => testChanges().length == 6,
          timeout: const Duration(seconds: 10),
        );
        final changes = testChanges();
        expect(changes, hasLength(6));
        expect(
          changes.expand((message) => message['user_ids']! as List).toSet(),
          subjects.toSet(),
        );
        expect(
          changes.every((message) => !message.containsKey('subject_ids')),
          isTrue,
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
          List<Map<String, dynamic>> testChanges() => _ofKind(
            notifications,
            'contact',
          ).where((message) => message['id'] == subjectId).toList();
          await _waitUntil(() => testChanges().isNotEmpty);
          final change = testChanges().single;
          expect(change['event'], operation);
          expect(change['id'], subjectId);
          expect(change['user_ids'], [viewerId]);
          expect(change, isNot(contains('subject_ids')));
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

    test(
      'cascade-deleted thread message retains room recipients',
      () async {
        final suffix = DateTime.timestamp().microsecondsSinceEpoch.toString();
        final ownerId = 'Urtmsgowner$suffix';
        final participantId = 'Urtmsgparticipant$suffix';
        final authorId = 'Urtmsgauthor$suffix';
        final mentionedId = 'Urtmsgmentioned$suffix';
        final beaconId = 'Brtmsg$suffix';
        final participantRowId = 'Prtmsg$suffix';
        final itemId = 'Irtmsg$suffix';
        final messageId = 'Rrtmsg$suffix';
        final userIds = [ownerId, participantId, authorId, mentionedId];

        addTearDown(() async {
          await writer.execute(
            Sql.named('DELETE FROM public.beacon WHERE id = @beaconId'),
            parameters: {'beaconId': beaconId},
          );
          await writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = ANY(@userIds)'),
            parameters: {'userIds': userIds},
          );
        });

        for (final userId in userIds) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@userId, @userId, @publicKey)
'''),
            parameters: {
              'userId': userId,
              'publicKey': 'realtime-room-message-$userId',
            },
          );
        }
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES (@beaconId, @ownerId, 'Realtime', 'Thread cascade test')
'''),
          parameters: {'beaconId': beaconId, 'ownerId': ownerId},
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access
) VALUES (@id, @beaconId, @userId, 2, 0, 3)
'''),
          parameters: {
            'id': participantRowId,
            'beaconId': beaconId,
            'userId': participantId,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, creator_id, target_person_id, accepted_by_id, published
) VALUES (
  @id, @beaconId, 2, @ownerId, @participantId, @authorId, true
)
'''),
          parameters: {
            'id': itemId,
            'beaconId': beaconId,
            'ownerId': ownerId,
            'participantId': participantId,
            'authorId': authorId,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, mentions, thread_item_id
) VALUES (
  @id, @beaconId, @authorId, 'Thread reply', ARRAY[@mentionedId]::text[], @itemId
)
'''),
          parameters: {
            'id': messageId,
            'beaconId': beaconId,
            'authorId': authorId,
            'mentionedId': mentionedId,
            'itemId': itemId,
          },
        );
        await _settle();
        notifications.clear();

        await writer.execute(
          Sql.named('DELETE FROM public.coordination_item WHERE id = @itemId'),
          parameters: {'itemId': itemId},
        );

        List<Map<String, dynamic>> testChanges() => _ofKind(
          notifications,
          'room_message',
        ).where((message) => message['id'] == beaconId).toList();
        await _waitUntil(() => testChanges().isNotEmpty);

        final change = testChanges().single;
        expect(change['event'], 'delete');
        expect(change['user_ids'], unorderedEquals(userIds));
      },
      skip: skipReason,
    );

    test(
      'profile updates emit only for profile-visible columns',
      () async {
        final suffix = DateTime.timestamp().microsecondsSinceEpoch.toString();
        final userId = 'Urtprofile$suffix';
        addTearDown(() async {
          await writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = @userId'),
            parameters: {'userId': userId},
          );
        });
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@userId, 'Profile before', @publicKey)
'''),
          parameters: {
            'userId': userId,
            'publicKey': 'realtime-profile-$userId',
          },
        );
        await _settle();
        notifications.clear();

        List<Map<String, dynamic>> testChanges() => _ofKind(
          notifications,
          'profile',
        ).where((message) => message['id'] == userId).toList();

        await writer.execute(
          Sql.named('''
UPDATE public."user"
SET updated_at = updated_at + interval '1 second'
WHERE id = @userId
'''),
          parameters: {'userId': userId},
        );
        await _settle();
        expect(testChanges(), isEmpty);

        await writer.execute(
          Sql.named('''
UPDATE public."user"
SET display_name = 'Profile after'
WHERE id = @userId
'''),
          parameters: {'userId': userId},
        );
        await _waitUntil(() => testChanges().isNotEmpty);

        final change = testChanges().single;
        expect(change['event'], 'update');
        expect(change['user_ids'], [userId]);
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

      List<Map<String, dynamic>> testChanges() => _ofKind(
        notifications,
        'room_seen',
      ).where((message) => message['id'] == beaconId).toList();

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
      await _waitUntil(() => testChanges().length == 1);
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
      expect(testChanges(), isEmpty);

      await writer.execute(
        Sql.named('''
UPDATE public.beacon_room_seen
SET last_seen_at = '2026-07-14T10:01:00Z'
WHERE user_id = @userId AND beacon_id = @beaconId AND thread_item_id IS NULL
'''),
        parameters: {'userId': userId, 'beaconId': beaconId},
      );
      await _waitUntil(() => testChanges().length == 1);
    }, skip: skipReason);

    test(
      'full trust recompute refreshes weights without relationship fan-out',
      () async {
        final suffix = DateTime.timestamp().microsecondsSinceEpoch.toString();
        final subjectId = 'Urttrustsubj$suffix';
        final objectId = 'Urttrustobj$suffix';
        final ids = [subjectId, objectId];
        addTearDown(() async {
          await writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = ANY(@ids)'),
            parameters: {'ids': ids},
          );
        });
        for (final id in ids) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
            parameters: {'id': id, 'key': 'realtime-trust-$id'},
          );
        }
        await _settle();
        notifications.clear();

        List<Map<String, dynamic>> ownEdgeChanges() =>
            _ofKind(notifications, 'relationship')
                .where(
                  (message) => ((message['user_ids'] as List?) ?? const [])
                      .contains(subjectId),
                )
                .toList();

        // An ordinary trust-edge write still fans out: the suppression flag is
        // scoped to bulk maintenance, not applied to real relationship changes.
        await writer.execute(
          Sql.named('''
INSERT INTO public.user_trust_edge (subject, object, anchor_at, s_good)
VALUES (@subject, @object, now() - interval '1 hour', 10)
'''),
          parameters: {'subject': subjectId, 'object': objectId},
        );
        await _waitUntil(() => ownEdgeChanges().isNotEmpty);

        final before = await writer.execute(
          Sql.named('''
SELECT prev_sent_weight FROM public.user_trust_edge
WHERE subject = @s AND object = @o
'''),
          parameters: {'s': subjectId, 'o': objectId},
        );

        await _settle();
        notifications.clear();

        // Full-graph decay recompute refreshes prev_sent_weight but must emit
        // no relationship invalidation for any edge (bookkeeping-only rewrite).
        await writer.execute(
          r'SELECT public.trust_recompute_all($1)',
          parameters: [3600.0],
        );
        await _settle();
        expect(_ofKind(notifications, 'relationship'), isEmpty);

        final after = await writer.execute(
          Sql.named('''
SELECT prev_sent_weight FROM public.user_trust_edge
WHERE subject = @s AND object = @o
'''),
          parameters: {'s': subjectId, 'o': objectId},
        );
        expect((before.single.single! as num).toDouble(), 0);
        // s_good = 10, ~one half-life old ⇒ f ≈ 0.5 ⇒ weight = 5 / 10 ≈ 0.5
        // (marginally under 0.5 since elapsed time exceeds the half-life by the
        // test's own runtime). The point is prev_sent_weight was refreshed off 0.
        expect((after.single.single! as num).toDouble(), closeTo(0.5, 0.01));
      },
      skip: skipReason,
    );

    test(
      'a single evidence application emits one relationship invalidation',
      () async {
        final suffix = DateTime.timestamp().microsecondsSinceEpoch.toString();
        final subjectId = 'Urtapplysubj$suffix';
        final objectId = 'Urtapplyobj$suffix';
        final ids = [subjectId, objectId];
        addTearDown(() async {
          await writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = ANY(@ids)'),
            parameters: {'ids': ids},
          );
        });
        for (final id in ids) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
            parameters: {'id': id, 'key': 'realtime-apply-$id'},
          );
        }
        await _settle();
        notifications.clear();

        List<Map<String, dynamic>> edgeChanges() =>
            _ofKind(notifications, 'relationship')
                .where(
                  (message) => ((message['user_ids'] as List?) ?? const [])
                      .contains(subjectId),
                )
                .toList();

        // A large epsilon means no engine push, so prev_sent_weight is left
        // alone: the only write that should reach the wire is the single bump
        // UPDATE, not the former upsert + bump (+ prev_sent_weight) trio that
        // each fired the statement trigger.
        await writer.execute(
          r'SELECT public.trust_apply_evidence($1, $2, $3, $4, $5, $6)',
          parameters: [subjectId, objectId, 'good', 4.0, 3600.0, 1000000.0],
        );
        await _waitUntil(() => edgeChanges().isNotEmpty);
        await _settle();
        expect(edgeChanges(), hasLength(1));

        final edge = await writer.execute(
          Sql.named('''
SELECT s_good, prev_sent_weight FROM public.user_trust_edge
WHERE subject = @s AND object = @o
'''),
          parameters: {'s': subjectId, 'o': objectId},
        );
        expect((edge.single[0]! as num).toDouble(), greaterThan(0));
        expect((edge.single[1]! as num).toDouble(), 0);
      },
      skip: skipReason,
    );
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

List<Map<String, dynamic>> _contractEntries() {
  final contract = jsonDecode(_contractFile().readAsStringSync()) as Map;
  return (contract['kinds']! as List)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList(growable: false);
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Realtime entity contract manifest not found');
}
