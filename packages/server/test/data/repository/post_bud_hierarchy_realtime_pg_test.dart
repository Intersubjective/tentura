@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_test_public_keys.dart';

/// Budding B4 (Arch §3.4, I11): `beacon_hierarchy` hints for a Request budded
/// from a Post go to the child's own audience plus its bud snapshot
/// observers, never to live Post membership.
///
/// Post `_post` (author `_postAuthor`) → child `_child` (author `_budder`).
/// Snapshot observers: `_postAuthor`, `_observer`, `_leaver` (left the Post
/// after the bud), `_blockee` (blocked by the Post author in a test). `_late`
/// joined the Post after the bud. Request `_req` → `_reqChild` keeps live
/// parent membership (`_reqMember`).
const _postAuthor = 'Ubudrtpauth01';
const _budder = 'Ubudrtbudder1';
const _observer = 'Ubudrtobserv1';
const _leaver = 'Ubudrtleaver1';
const _blockee = 'Ubudrtblocke1';
const _late = 'Ubudrtlate001';
const _reqAuthor = 'Ubudrtreqaut1';
const _reqMember = 'Ubudrtreqmem1';

const _users = [
  _postAuthor,
  _budder,
  _observer,
  _leaver,
  _blockee,
  _late,
  _reqAuthor,
  _reqMember,
];

const _post = 'Bbudrtpost001';
const _child = 'Bbudrtchild01';
const _req = 'Bbudrtreq0001';
const _reqChild = 'Bbudrtreqchd1';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_REALTIME_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_rt_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_REALTIME_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_rt',
  );
  final pgSkip =
      await pgSkipReason(migrationTarget) ?? await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0242',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('rows written before the migration get snapshot recipients', () async {
      final writer = session.writer;
      await _seed(writer);
      expect(await _recipients(writer, _child), contains(_late));

      await migrateDbSchema(writer);

      expect(
        await _recipients(writer, _child),
        {_budder, _postAuthor, _observer, _leaver, _blockee},
      );
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late PgNotificationRecorder recorder;
    var markerSeq = 0;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      recorder = PgNotificationRecorder(listener.channels['entity_changes']);
    });

    setUp(() async {
      await _seed(writer);
    });

    tearDownAll(() async {
      await recorder.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    /// Runs [action] and returns the `beacon_hierarchy` recipients of every
    /// hint on [aggregateId] it emitted, one set per notification.
    Future<List<Set<String>>> hintsOn(
      String aggregateId,
      Future<void> Function() action,
    ) async {
      await recorder.drain(
        sendBarrier: (token) => writer.execute(
          Sql.named("SELECT pg_notify('entity_changes', @payload)"),
          parameters: {
            'payload': jsonEncode({'entity': 'barrier', 'id': token}),
          },
        ),
      );
      await action();
      final marker = 'marker-${markerSeq++}';
      await writer.execute(
        Sql.named("SELECT pg_notify('entity_changes', @payload)"),
        parameters: {
          'payload': jsonEncode({'entity': 'marker', 'id': marker}),
        },
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!recorder.messages.any((m) => m['id'] == marker)) {
        if (DateTime.now().isAfter(deadline)) {
          fail('marker $marker not delivered');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return [
        for (final m in recorder.messages)
          if (m['entity'] == 'beacon_hierarchy' && m['id'] == aggregateId)
            (m['user_ids']! as List).cast<String>().toSet(),
      ];
    }

    Future<void> touchChild() => writer.execute(
      "UPDATE public.beacon SET title = title || '!' WHERE id = '$_child'",
    );

    test('child recipients are the child audience plus the snapshot', () async {
      expect(
        await _recipients(writer, _child),
        {_budder, _postAuthor, _observer, _leaver, _blockee},
      );
    });

    test('a later Post member gets no child hint', () async {
      final hints = await hintsOn(_child, touchChild);
      expect(hints, isNotEmpty);
      for (final users in hints) {
        expect(users, isNot(contains(_late)));
        expect(users, contains(_observer));
      }
    });

    test('a snapshot observer who left the Post still gets it', () async {
      await writer.execute(
        'UPDATE public.beacon_participant SET room_access = 5 '
        "WHERE beacon_id = '$_post' AND user_id = '$_leaver'",
      );
      final hints = await hintsOn(_child, touchChild);
      expect(hints, isNotEmpty);
      for (final users in hints) {
        expect(users, contains(_leaver));
      }
    });

    test('a blocked observer gets only the invalidation', () async {
      final invalidation = await hintsOn(
        _child,
        () => writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_postAuthor', '$_blockee', '$_postAuthor')
'''),
      );
      expect(invalidation, isNotEmpty);
      expect(invalidation.expand((u) => u), contains(_blockee));

      expect(await _recipients(writer, _child), isNot(contains(_blockee)));
      final later = await hintsOn(_child, touchChild);
      expect(later, isNotEmpty);
      for (final users in later) {
        expect(users, isNot(contains(_blockee)));
      }
    });

    test(
      'accepted gap: Post deletion sends former observers no hint',
      () async {
        // The parent-deletion path passes no extra recipients; former
        // observers refetch on their next read and the read wall answers.
        final hints = await hintsOn(
          _child,
          () => writer.execute(
            "UPDATE public.beacon SET status = 2 WHERE id = '$_post'",
          ),
        );
        expect(hints, isNotEmpty);
        for (final users in hints) {
          expect(users, isNot(contains(_observer)));
          expect(users, contains(_budder));
        }
      },
    );

    test('emits owned by the Post itself still reach live members', () async {
      expect(await _recipients(writer, _post), contains(_late));
    });

    test('Request parents keep live parent membership', () async {
      expect(
        await _recipients(writer, _reqChild),
        {_reqAuthor, _reqMember},
      );
    });

    test(
      'the recipient function stays STABLE with default attributes',
      () async {
        final rows = await writer.execute('''
SELECT p.procost::int, p.provolatile::text, p.prosecdef, p.proconfig IS NULL
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'realtime_beacon_hierarchy_recipients'
''');
        expect(rows.single.toList(), [100, 's', false, true]);
      },
    );
  });
}

Future<Set<String>> _recipients(Connection writer, String owner) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT unnest(public.realtime_beacon_hierarchy_recipients(@id))',
    ),
    parameters: {'id': owner},
  );
  return {for (final r in rows) r.single! as String};
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_bud_observer,
  public.user_block,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('bt', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_postAuthor', '', '', 0, 1, 1, false, now())
''');
  var edgeSeq = 0;
  // Forward edges admit their recipients to the Post (m0210).
  for (final member in [_budder, _observer, _leaver, _blockee, _late]) {
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fbudrt${(edgeSeq++).toString().padLeft(4, '0')}', '$_post',
        '$_postAuthor', '$member')
''');
  }
  Future<void> request(String id, String author, String? parent) =>
      writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable,
   parent_beacon_id, published_at)
VALUES ('$id', '$author', 'Request', '', 0, false,
        ${parent == null ? 'NULL' : "'$parent'"}, now())
''');
  await request(_child, _budder, _post);
  for (final o in [_postAuthor, _observer, _leaver, _blockee]) {
    await writer.execute('''
INSERT INTO public.beacon_bud_observer (beacon_id, user_id)
VALUES ('$_child', '$o')
''');
  }
  await request(_req, _reqAuthor, null);
  await request(_reqChild, _reqAuthor, _req);
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('P$_req$_reqMember', '$_req', '$_reqMember', 0, 0, 3)
''');
}
