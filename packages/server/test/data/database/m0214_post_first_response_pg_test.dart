@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// The first-response claim of a Post: one row per (Post, member), written by
/// `post_claim_first_response`, which only claims for a Post (`beacon.kind = 1`),
/// never for its author, for either source kind (message or reaction), and
/// engages the member's inbound contact edge on the winning call.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.4.
const _author = 'Um0214author001';
const _member = 'Um0214member001';
const _other = 'Um0214other0001';
const _post = 'Bm0214post00001';
const _request = 'Bm0214request001';

const _kindMessage = 1;
const _kindReaction = 2;

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0214_FIRST_RESPONSE_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0214_firstresp_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0214_FIRST_RESPONSE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0214_firstresp',
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
        lastInclusiveVersion: '0213',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('after migrating, a member of a Post can be claimed', () async {
      final writer = session.writer;
      await _seed(writer);

      await migrateDbSchema(writer);

      expect(await _claim(writer, _post, _member, _kindMessage, 'M1'), isTrue);
      expect(await _claim(writer, _post, _member, _kindMessage, 'M2'), isFalse);
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('the first claim wins and later ones lose', () async {
      expect(await _claim(writer, _post, _member, _kindReaction, 'E1'), isTrue);
      expect(await _claim(writer, _post, _member, _kindMessage, 'M1'), isFalse);
      expect(await _claim(writer, _post, _member, _kindReaction, 'E2'), isFalse);

      final rows = await writer.execute('''
SELECT user_id, source_kind, source_id, created_at
FROM public.post_first_response WHERE beacon_id = '$_post'
''');
      expect(rows, hasLength(1));
      expect(rows.single[0], _member);
      expect(rows.single[1], _kindReaction);
      expect(rows.single[2], 'E1');
      expect(rows.single[3], isNotNull);
    });

    // The Post/author conditions of the function look at the *beacon* row
    // (`beacon.kind = 1`, `beacon.user_id <> p_user`); the `p_kind` argument
    // is the source kind (1 message, 2 reaction) and is stored, not filtered
    // on. Both source kinds therefore claim on a Post, and both are refused
    // for a Request and for the Post's author.
    for (final (name, kind) in [
      ('message', _kindMessage),
      ('reaction', _kindReaction),
    ]) {
      group('a $name claim', () {
        test('succeeds for a member of a Post and records the source', () async {
          expect(await _claim(writer, _post, _member, kind, 'S1'), isTrue);

          final rows = await writer.execute('''
SELECT source_kind, source_id FROM public.post_first_response
WHERE beacon_id = '$_post' AND user_id = '$_member'
''');
          expect(rows.single[0], kind);
          expect(rows.single[1], 'S1');
        });

        test('succeeds for each member of a Post separately', () async {
          expect(await _claim(writer, _post, _member, kind, 'S1'), isTrue);
          expect(await _claim(writer, _post, _other, kind, 'S2'), isTrue);
          expect(await _claimRows(writer), 2);
        });

        test('is refused for the author of the Post', () async {
          expect(await _claim(writer, _post, _author, kind, 'S1'), isFalse);
          expect(await _claimRows(writer), 0);
        });

        test('is refused for a Request', () async {
          expect(await _claim(writer, _request, _member, kind, 'S1'), isFalse);
          expect(await _claimRows(writer), 0);
          expect(
            await _contactOutcome(writer, _member, beaconId: _request),
            isNull,
            reason: 'a refused claim engages nothing',
          );
        });
      });
    }

    test("a winning claim engages the member's inbound contact edge", () async {
      expect(await _contactOutcome(writer, _member), isNull);

      await _claim(writer, _post, _member, _kindMessage, 'M1');

      expect(await _contactOutcome(writer, _member), 1);
      expect(await _contactOutcome(writer, _other), isNull);
    });

    test('a losing claim leaves the contact edge as it is', () async {
      await _claim(writer, _post, _member, _kindMessage, 'M1');
      await writer.execute('''
UPDATE public.beacon_forward_edge
SET contact_outcome = 2
WHERE beacon_id = '$_post' AND recipient_id = '$_member'
''');

      expect(await _claim(writer, _post, _member, _kindMessage, 'M2'), isFalse);

      expect(await _contactOutcome(writer, _member), 2);
    });

    test('the source kind is a message or a reaction', () async {
      await writer.execute('''
INSERT INTO public.post_first_response
  (beacon_id, user_id, source_kind, source_id)
VALUES ('$_post', '$_other', 1, 'M-ok')
''');

      await expectLater(
        writer.execute('''
INSERT INTO public.post_first_response
  (beacon_id, user_id, source_kind, source_id)
VALUES ('$_post', '$_member', 3, 'X')
'''),
        throwsA(isA<ServerException>()),
      );
    });

    test('deleting the member removes their claim', () async {
      await _claim(writer, _post, _member, _kindMessage, 'M1');
      await _claim(writer, _post, _other, _kindMessage, 'M2');

      await writer.execute('''DELETE FROM public."user" WHERE id = '$_member' ''');

      expect(await _claimRows(writer), 1);
    });

    test('deleting the Post removes its claims', () async {
      await _claim(writer, _post, _member, _kindMessage, 'M1');

      await writer.execute("DELETE FROM public.beacon WHERE id = '$_post'");

      expect(await _claimRows(writer), 0);
    });
  });
}

Future<bool> _claim(
  Connection writer,
  String beaconId,
  String userId,
  int kind,
  String sourceId,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT public.post_claim_first_response('
      '@beacon, @user, @kind::smallint, @source)',
    ),
    parameters: {
      'beacon': beaconId,
      'user': userId,
      'kind': kind,
      'source': sourceId,
    },
  );
  return rows.single.single! as bool;
}

Future<int> _claimRows(Connection writer) async {
  final rows = await writer.execute(
    'SELECT count(*)::int FROM public.post_first_response',
  );
  return rows.single.single! as int;
}

Future<int?> _contactOutcome(
  Connection writer,
  String recipientId, {
  String beaconId = _post,
}) async =>
    (await writer.execute('''
SELECT contact_outcome FROM public.beacon_forward_edge
WHERE beacon_id = '$beaconId' AND recipient_id = '$recipientId'
''')).single.single
        as int?;

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _member, _other];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('m0214', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fm0214edge0001', '$_post', '$_author', '$_member'),
  ('Fm0214edge0002', '$_post', '$_author', '$_other'),
  ('Fm0214edge0003', '$_request', '$_author', '$_member')
''');
}
