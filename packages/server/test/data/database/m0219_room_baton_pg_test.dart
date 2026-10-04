@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// «Who'll take it?» (baton) storage — plan §2.1/B1
/// (`docs/plans/baton-who-takes-it-plan.md`). Both tables, their CHECK
/// constraints, the `entity_changes` NOTIFY fan-out (scoped to the author and
/// candidates only, never the whole room), and account-erasure cascades.
const _author = 'Um0219author001';
const _candidateA = 'Um0219candidA01';
const _candidateB = 'Um0219candidB01';
const _outsider = 'Um0219outsider1';

const _beacon = 'Bm0219beacon001';
const _message = 'Rm0219message01';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0219_ROOM_BATON_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0219_baton_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0219_ROOM_BATON_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0219_baton',
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
        lastInclusiveVersion: '0218',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('creates both baton tables', () async {
      final writer = session.writer;

      await migrateDbSchema(writer);

      final tables = await writer.execute('''
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('beacon_room_baton', 'beacon_room_baton_candidate')
ORDER BY table_name
''');
      expect(
        tables.map((row) => row.single).toList(),
        ['beacon_room_baton', 'beacon_room_baton_candidate'],
      );
    });
  });

  group('full schema', () {
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
    });

    setUp(() async {
      notifications.clear();
      await _seed(writer);
    });

    tearDownAll(() async {
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    List<Map<String, dynamic>> batonNotifications() =>
        notifications.where((m) => m['entity'] == 'room_baton').toList();

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

    Future<Map<String, dynamic>> waitForBatonNotify() async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        final matches = batonNotifications();
        if (matches.isNotEmpty) return matches.last;
        await settle();
      }
      fail('Timed out waiting for room_baton NOTIFY');
    }

    Future<void> waitForNoBatonNotify() async {
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(batonNotifications(), isEmpty);
    }

    Future<String> insertBaton({
      String id = 'Lm0219baton0001',
      String status = '0',
    }) async {
      await writer.execute('''
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id, status)
VALUES ('$id', '$_message', '$_beacon', '$_author', $status)
''');
      return id;
    }

    Future<void> insertCandidate({
      required String batonId,
      required String userId,
      int tier = 1,
    }) => writer.execute('''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier)
VALUES ('$batonId', '$userId', $tier)
''');

    group('CHECK constraints', () {
      test('rejects a tier outside 1..3', () async {
        final batonId = await insertBaton();
        await expectLater(
          writer.execute('''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier)
VALUES ('$batonId', '$_candidateA', 0)
'''),
          throwsA(isA<ServerException>()),
        );
        await expectLater(
          writer.execute('''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier)
VALUES ('$batonId', '$_candidateA', 4)
'''),
          throwsA(isA<ServerException>()),
        );
      });

      test('rejects a response outside 0..2', () async {
        final batonId = await insertBaton();
        await expectLater(
          writer.execute('''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier, response)
VALUES ('$batonId', '$_candidateA', 1, 3)
'''),
          throwsA(isA<ServerException>()),
        );
      });

      test('rejects status 1 (taken) without selection_mode and resolved_at', () async {
        await expectLater(
          writer.execute('''
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id, status)
VALUES ('Lm0219bad00001', '$_message', '$_beacon', '$_author', 1)
'''),
          throwsA(isA<ServerException>()),
        );
      });

      test('allows status 1 with selection_mode and resolved_at set', () async {
        await writer.execute('''
INSERT INTO public.beacon_room_baton
  (id, message_id, beacon_id, author_id, status, taker_id, selection_mode, resolved_at)
VALUES
  ('Lm0219good0001', '$_message', '$_beacon', '$_author', 1, '$_candidateA', 1, now())
''');
      });

      test(
        'a second live baton on the same message violates the partial unique index; '
        'cancelling the first frees it for a new one',
        () async {
          await insertBaton(id: 'Lm0219first001');

          await expectLater(
            writer.execute('''
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id, status)
VALUES ('Lm0219second01', '$_message', '$_beacon', '$_author', 0)
'''),
            throwsA(isA<ServerException>()),
          );

          await writer.execute('''
UPDATE public.beacon_room_baton SET status = 2, resolved_at = now()
WHERE id = 'Lm0219first001'
''');

          await writer.execute('''
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id, status)
VALUES ('Lm0219second01', '$_message', '$_beacon', '$_author', 0)
''');
        },
      );
    });

    group('entity_changes NOTIFY', () {
      test(
        'inserting a baton notifies room_baton with the author and candidates only',
        () async {
          final batonId = await insertBaton();
          await insertCandidate(batonId: batonId, userId: _candidateA);
          await insertCandidate(batonId: batonId, userId: _candidateB);
          notifications.clear();

          await writer.execute('''
UPDATE public.beacon_room_baton SET status = 2, resolved_at = now()
WHERE id = '$batonId'
''');

          final notify = await waitForBatonNotify();
          expect(notify['event'], 'update');
          expect(notify['entity'], 'room_baton');
          expect(notify['id'], _beacon);
          final recipients = (notify['user_ids']! as List).cast<String>().toSet();
          expect(recipients, {_author, _candidateA, _candidateB});
          expect(recipients, isNot(contains(_outsider)));
        },
      );

      test('inserting a baton row itself notifies room_baton', () async {
        notifications.clear();

        await insertBaton();

        final notify = await waitForBatonNotify();
        expect(notify['entity'], 'room_baton');
        expect((notify['user_ids']! as List).cast<String>(), [_author]);
      });

      test(
        'a stale status UPDATE (no actual change) emits no NOTIFY',
        () async {
          final batonId = await insertBaton();
          await waitForBatonNotify();
          notifications.clear();

          await writer.execute('''
UPDATE public.beacon_room_baton SET status = 0 WHERE id = '$batonId'
''');

          await waitForNoBatonNotify();
        },
      );

      test(
        "updating one candidate's response notifies only the author and that candidate",
        () async {
          final batonId = await insertBaton();
          await insertCandidate(batonId: batonId, userId: _candidateA);
          await insertCandidate(batonId: batonId, userId: _candidateB);
          await waitForBatonNotify();
          notifications.clear();

          await writer.execute('''
UPDATE public.beacon_room_baton_candidate SET response = 1, responded_at = now()
WHERE baton_id = '$batonId' AND user_id = '$_candidateA'
''');

          final notify = await waitForBatonNotify();
          final recipients = (notify['user_ids']! as List).cast<String>().toSet();
          expect(recipients, {_author, _candidateA});
          expect(recipients, isNot(contains(_candidateB)));
        },
      );

      test(
        'a candidate update that does not change the response emits no NOTIFY',
        () async {
          final batonId = await insertBaton();
          await insertCandidate(batonId: batonId, userId: _candidateA);
          await waitForBatonNotify();
          notifications.clear();

          await writer.execute('''
UPDATE public.beacon_room_baton_candidate SET tier = 2
WHERE baton_id = '$batonId' AND user_id = '$_candidateA'
''');

          await waitForNoBatonNotify();
        },
      );
    });

    group('account erasure', () {
      test("erasing a candidate's account removes their candidate row", () async {
        final batonId = await insertBaton();
        await insertCandidate(batonId: batonId, userId: _candidateA);
        await insertCandidate(batonId: batonId, userId: _candidateB);

        await writer.execute("DELETE FROM public.\"user\" WHERE id = '$_candidateA'");

        final remaining = await writer.execute('''
SELECT user_id FROM public.beacon_room_baton_candidate WHERE baton_id = '$batonId'
''');
        expect(remaining.map((r) => r.single).toList(), [_candidateB]);
      });

      test('erasing the taker nulls taker_id but keeps the baton row', () async {
        await writer.execute('''
INSERT INTO public.beacon_room_baton
  (id, message_id, beacon_id, author_id, status, taker_id, selection_mode, resolved_at)
VALUES
  ('Lm0219taker001', '$_message', '$_beacon', '$_author', 1, '$_candidateA', 1, now())
''');

        await writer.execute("DELETE FROM public.\"user\" WHERE id = '$_candidateA'");

        final row = await writer.execute('''
SELECT taker_id FROM public.beacon_room_baton WHERE id = 'Lm0219taker001'
''');
        expect(row.single.single, isNull);
      });

      test('erasing the author cascades away the whole baton', () async {
        const authorOnly = 'Um0219soleauth1';
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': authorOnly, 'key': pgTestPublicKey('m0219', 9)},
        );
        await writer.execute('''
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id, status)
VALUES ('Lm0219soleaut1', '$_message', '$_beacon', '$authorOnly', 0)
''');

        await writer.execute("DELETE FROM public.\"user\" WHERE id = '$authorOnly'");

        final row = await writer.execute('''
SELECT count(*)::int FROM public.beacon_room_baton WHERE id = 'Lm0219soleaut1'
''');
        expect(row.single.single, 0);
      });
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_room_baton_candidate,
  public.beacon_room_baton,
  public.beacon_room_message,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _candidateA, _candidateB, _outsider];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('m0219', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_beacon', '$_author', 'Baton fixture', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_message', '$_beacon', '$_author', 'Can someone take this?')
''');
}
