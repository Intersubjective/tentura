@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/post_write_guard_fixture.dart';

/// Baton «together» storage: partner columns on the candidate row, `co_taker_id`
/// on the baton, their CHECKs / indexes, realtime fan-out and Post-archive guard.
Future<void> main() async {
  final upgradeTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BATON_PARTNER_UPGRADE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_baton_partner_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BATON_PARTNER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_baton_partner',
  );
  final pgSkip =
      await pgSkipReason(upgradeTarget) ?? await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const a = guardMember;
  const x = guardOther;
  const author = guardAuthor;

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: upgradeTarget,
        lastInclusiveVersion: '0315',
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      await seedPostWriteGuard(session.writer);
      await session.writer.execute('''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, response)
VALUES ('$guardBaton', '$a', 1)
''');
    });

    test('adds partner and co-taker columns and keeps existing rows', () async {
      final writer = session.writer;
      await migrateDbSchema(writer);

      final cols = await writer.execute('''
SELECT table_name, column_name, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'beacon_room_baton_candidate'
        AND column_name IN ('partner_user_id','partner_response',
                            'partner_responded_at','partner_invites'))
    OR (table_name = 'beacon_room_baton' AND column_name = 'co_taker_id'))
ORDER BY column_name
''');
      final byName = {for (final r in cols) r[1]! as String: r};
      expect(
        byName.keys,
        containsAll([
          'partner_user_id',
          'partner_response',
          'partner_responded_at',
          'partner_invites',
          'co_taker_id',
        ]),
      );
      expect(byName['partner_invites']![2], 'NO');
      expect(byName['partner_user_id']![2], 'YES');
      expect(byName['co_taker_id']![2], 'YES');

      final row = (await writer.execute('''
SELECT partner_user_id, partner_response, partner_responded_at,
       partner_invites, response
FROM public.beacon_room_baton_candidate
WHERE baton_id = '$guardBaton' AND user_id = '$a'
''')).single;
      expect(row.toList(), [null, null, null, 0, 1]);

      final baton = (await writer.execute('''
SELECT status::int, taker_id, co_taker_id
FROM public.beacon_room_baton WHERE id = '$guardBaton'
''')).single;
      expect(baton.toList(), [0, null, null]);

      final indexes = await writer.execute('''
SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'
AND indexname IN ('beacon_room_baton_candidate_partner',
                  'beacon_room_baton_candidate_one_accepted_partner')
''');
      expect(indexes.length, 2);
      for (final r in indexes) {
        expect(r[1], contains('WHERE'), reason: '${r[0]} is partial');
      }
      expect(
        indexes.firstWhere(
          (r) => r[0] == 'beacon_room_baton_candidate_one_accepted_partner',
        )[1],
        contains('UNIQUE'),
      );
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> sub;
    final notifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      sub = listener.channels['entity_changes'].listen(
        (p) => notifications.add(jsonDecode(p) as Map<String, dynamic>),
      );
    });

    setUp(() async {
      await seedPostWriteGuard(writer);
      // NOTIFY delivery is asynchronous: let the seed's notifications land
      // before clearing so they cannot leak into the test.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      notifications.clear();
    });

    tearDownAll(() async {
      await sub.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<void> candidate(String user, int response) => writer.execute('''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, response)
VALUES ('$guardBaton', '$user', $response)
''');

    Future<void> setCandidate(String user, String set) => writer.execute('''
UPDATE public.beacon_room_baton_candidate SET $set
WHERE baton_id = '$guardBaton' AND user_id = '$user'
''');

    Future<void> take({String extra = ''}) => writer.execute('''
UPDATE public.beacon_room_baton
SET status = 1, taker_id = '$a', selection_mode = 1, resolved_at = now()
    $extra
WHERE id = '$guardBaton'
''');

    Matcher checkViolation() =>
        isA<ServerException>().having((e) => e.code, 'SQLSTATE', '23514');
    Matcher uniqueViolation() =>
        isA<ServerException>().having((e) => e.code, 'SQLSTATE', '23505');

    Future<List<Map<String, dynamic>>> batonNotes({
      bool wait = true,
    }) async {
      final deadline = DateTime.now().add(
        Duration(milliseconds: wait ? 3000 : 400),
      );
      List<Map<String, dynamic>> now() =>
          notifications.where((m) => m['entity'] == 'room_baton').toList();
      while (DateTime.now().isBefore(deadline)) {
        if (wait && now().isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return now();
    }

    Set<String> users(Map<String, dynamic> n) =>
        (n['user_ids']! as List).cast<String>().toSet();

    group('CHECK constraints', () {
      test('partner cannot be the candidate themself', () async {
        await candidate(a, 1);
        await expectLater(
          setCandidate(a, "partner_user_id = '$a', partner_response = 0"),
          throwsA(checkViolation()),
        );
        await setCandidate(a, "partner_user_id = '$x', partner_response = 0");
      });

      test(
        'on a cant_help row a pending or accepted partner is rejected',
        () async {
          await candidate(a, 2);
          await expectLater(
            setCandidate(a, "partner_user_id = '$x', partner_response = 0"),
            throwsA(checkViolation()),
          );
          await expectLater(
            setCandidate(a, "partner_user_id = '$x', partner_response = 1"),
            throwsA(checkViolation()),
          );
          await setCandidate(a, 'partner_response = NULL');
        },
      );

      test(
        'a declined partner is allowed only on a row that is not can_help',
        () async {
          await candidate(a, 0);
          await setCandidate(a, "partner_user_id = '$x', partner_response = 2");

          await setCandidate(a, 'response = 1, partner_response = NULL');
          await expectLater(
            setCandidate(a, "partner_user_id = '$x', partner_response = 2"),
            throwsA(checkViolation()),
          );
          await setCandidate(a, "partner_user_id = '$x', partner_response = 0");
          await setCandidate(a, 'partner_response = 1');
        },
      );

      test('partner_response and partner_invites stay in range', () async {
        await candidate(a, 1);
        await expectLater(
          setCandidate(a, "partner_user_id = '$x', partner_response = 3"),
          throwsA(checkViolation()),
        );
        await expectLater(
          setCandidate(a, 'partner_invites = 4'),
          throwsA(checkViolation()),
        );
        await expectLater(
          setCandidate(a, 'partner_invites = -1'),
          throwsA(checkViolation()),
        );
        await setCandidate(a, 'partner_invites = 3');
      });

      test('co_taker_id only on a taken baton, and never the taker', () async {
        Future<void> setCo(String v) => writer.execute(
          "UPDATE public.beacon_room_baton SET co_taker_id = '$v' "
          "WHERE id = '$guardBaton'",
        );
        await expectLater(setCo(x), throwsA(checkViolation()));
        await writer.execute('''
UPDATE public.beacon_room_baton SET status = 2, resolved_at = now()
WHERE id = '$guardBaton'
''');
        await expectLater(setCo(x), throwsA(checkViolation()));
      });

      test('taken baton: co-taker must differ from taker', () async {
        await take();
        await expectLater(
          writer.execute(
            "UPDATE public.beacon_room_baton SET co_taker_id = '$a' "
            "WHERE id = '$guardBaton'",
          ),
          throwsA(checkViolation()),
        );
        await writer.execute(
          "UPDATE public.beacon_room_baton SET co_taker_id = '$x' "
          "WHERE id = '$guardBaton'",
        );
      });
    });

    group('unique accepted partner', () {
      const secondBaton = 'Tpartnerbaton02';
      const secondMessage = 'Rpartnermsg0002';

      test('one accepted row per (baton, partner)', () async {
        await candidate(a, 1);
        await candidate(author, 1);
        await setCandidate(a, "partner_user_id = '$x', partner_response = 1");
        await expectLater(
          setCandidate(
            author,
            "partner_user_id = '$x', partner_response = 1",
          ),
          throwsA(uniqueViolation()),
        );
      });

      test('pending duplicates and other batons are allowed', () async {
        await candidate(a, 1);
        await candidate(author, 1);
        await setCandidate(a, "partner_user_id = '$x', partner_response = 0");
        await setCandidate(
          author,
          "partner_user_id = '$x', partner_response = 0",
        );

        await setCandidate(a, 'partner_response = 1');
        await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$secondMessage', '$guardPost', '$author', 'again')
''');
        await writer.execute('''
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id)
VALUES ('$secondBaton', '$secondMessage', '$guardPost', '$author')
''');
        await writer.execute('''
INSERT INTO public.beacon_room_baton_candidate
  (baton_id, user_id, response, partner_user_id, partner_response)
VALUES ('$secondBaton', '$a', 1, '$x', 1)
''');
      });
    });

    group('realtime fan-out', () {
      test(
        'partner_response change notifies author, candidate, partner',
        () async {
          await candidate(a, 1);
          await setCandidate(a, "partner_user_id = '$x', partner_response = 0");
          await batonNotes();
          notifications.clear();

          await setCandidate(a, 'partner_response = 1');

          final notes = await batonNotes();
          expect(notes, hasLength(1));
          expect(users(notes.single), {author, a, x});
        },
      );

      test(
        'swapping the partner notifies author, candidate, old and new partner',
        () async {
          const y = 'Upostguardfourth';
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
            parameters: {'id': y, 'key': pgTestPublicKey('postguard', 9)},
          );
          await candidate(a, 1);
          await setCandidate(a, "partner_user_id = '$x', partner_response = 0");
          await batonNotes();
          notifications.clear();

          await setCandidate(a, "partner_user_id = '$y', partner_response = 0");

          final notes = await batonNotes();
          expect(notes, hasLength(1));
          expect(users(notes.single), {author, a, x, y});
        },
      );

      test(
        'a response change still notifies author and that candidate',
        () async {
          await candidate(a, 0);
          await candidate(x, 0);
          await batonNotes();
          notifications.clear();

          await setCandidate(a, 'response = 1, responded_at = now()');

          final notes = await batonNotes();
          expect(notes, hasLength(1));
          expect(users(notes.single), {author, a});
        },
      );

      test(
        'a candidate update touching no notify-relevant column is silent',
        () async {
          await candidate(a, 1);
          await setCandidate(a, "partner_user_id = '$x', partner_response = 0");
          await batonNotes();
          notifications.clear();

          await setCandidate(a, 'partner_invites = 1, tier = 2');

          expect(await batonNotes(wait: false), isEmpty);
        },
      );

      test(
        'baton status change reaches author, candidates and partners',
        () async {
          await candidate(a, 1);
          await setCandidate(a, "partner_user_id = '$x', partner_response = 0");
          await batonNotes();
          notifications.clear();

          await writer.execute('''
UPDATE public.beacon_room_baton SET status = 2, resolved_at = now()
WHERE id = '$guardBaton'
''');

          final notes = await batonNotes();
          expect(notes, hasLength(1));
          expect(users(notes.single), {author, a, x});
        },
      );

      test('a co_taker_id-only update notifies', () async {
        await take();
        await batonNotes();
        notifications.clear();

        await writer.execute(
          "UPDATE public.beacon_room_baton SET co_taker_id = '$x' "
          "WHERE id = '$guardBaton'",
        );

        expect(await batonNotes(), isNotEmpty);
      });
    });

    group('archived Post guard', () {
      Future<void> pending() async {
        await candidate(a, 1);
        await setCandidate(a, "partner_user_id = '$x', partner_response = 0");
      }

      for (final set in [
        'partner_response = 1',
        "partner_user_id = '$author', partner_response = 0",
        'partner_responded_at = now()',
        'partner_invites = 1',
      ]) {
        test('open Post allows, closed Post rejects: $set', () async {
          await pending();
          await setCandidate(a, set);
          await writer.execute(
            "UPDATE public.beacon SET status = 6 WHERE id = '$guardPost'",
          );
          await expectLater(setCandidate(a, set), throwsA(postArchived));
        });
      }
    });

    group('account erasure', () {
      test('erased partner keeps partner_response on an open Post', () async {
        await candidate(a, 1);
        await setCandidate(a, "partner_user_id = '$x', partner_response = 1");
        await writer.execute("DELETE FROM public.\"user\" WHERE id = '$x'");
        final row = (await writer.execute('''
SELECT partner_user_id, partner_response
FROM public.beacon_room_baton_candidate
WHERE baton_id = '$guardBaton' AND user_id = '$a'
''')).single;
        expect(row.toList(), [null, 1]);
      });

      test('erased co-taker keeps the taken baton', () async {
        await take(extra: ", co_taker_id = '$x'");
        await writer.execute("DELETE FROM public.\"user\" WHERE id = '$x'");
        final row = (await writer.execute('''
SELECT status::int, taker_id, co_taker_id FROM public.beacon_room_baton
WHERE id = '$guardBaton'
''')).single;
        expect(row.toList(), [1, a, null]);
      });

      test('erasing a partner or co-taker on a closed Post succeeds', () async {
        await candidate(a, 1);
        await setCandidate(a, "partner_user_id = '$x', partner_response = 1");
        await writer.execute(
          "UPDATE public.beacon SET status = 6 WHERE id = '$guardPost'",
        );
        await writer.execute("DELETE FROM public.\"user\" WHERE id = '$x'");
        final row = (await writer.execute('''
SELECT partner_user_id, partner_response
FROM public.beacon_room_baton_candidate
WHERE baton_id = '$guardBaton' AND user_id = '$a'
''')).single;
        expect(row.toList(), [null, 1]);
      });

      test('erasing the co-taker on a closed Post nulls co_taker_id', () async {
        await take(extra: ", co_taker_id = '$x'");
        await writer.execute(
          "UPDATE public.beacon SET status = 6 WHERE id = '$guardPost'",
        );
        await writer.execute("DELETE FROM public.\"user\" WHERE id = '$x'");
        final row = (await writer.execute(
          "SELECT co_taker_id FROM public.beacon_room_baton WHERE id = '$guardBaton'",
        )).single;
        expect(row.single, isNull);
      });
    });
  });
}
