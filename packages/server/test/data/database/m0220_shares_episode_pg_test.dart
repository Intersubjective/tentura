@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// m0220: `user_get_shares_episode_with_viewer` backs the Request showcase's
/// "people you know" ordering (#159, #104). Two users share an episode when
/// both were in the same non-deleted Request, as its author or as an
/// admitted participant.
const _viewer = 'Um0220viewer01';
const _peer = 'Um0220peer0001';
const _stranger = 'Um0220strang01';
const _author = 'Um0220author01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0220_SHARES_EPISODE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0220_se',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  test('the shares-episode migration is registered', () {
    expect(migrationsForTesting.map((m) => m.version), contains('0220'));
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [_viewer, _peer, _stranger, _author]) {
        await _insertUser(writer, id);
      }
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('strangers share nothing', () async {
      expect(await _shares(writer, user: _stranger, viewer: _viewer), isFalse);
    });

    test('both admitted to the same Request share an episode', () async {
      await _insertBeacon(writer, id: 'Bm0220both0001', author: _author);
      await _insertParticipant(writer, 'Bm0220both0001', _viewer);
      await _insertParticipant(writer, 'Bm0220both0001', _peer);
      expect(await _shares(writer, user: _peer, viewer: _viewer), isTrue);
      expect(await _shares(writer, user: _viewer, viewer: _peer), isTrue);
      expect(await _shares(writer, user: _author, viewer: _viewer), isTrue);
    });

    test('a pending (not admitted) participant does not count', () async {
      await _insertBeacon(writer, id: 'Bm0220pend0001', author: _stranger);
      await _insertParticipant(
        writer,
        'Bm0220pend0001',
        _viewer,
        roomAccess: 1,
      );
      expect(await _shares(writer, user: _stranger, viewer: _viewer), isFalse);
    });

    test('a deleted Request does not count', () async {
      await _insertUser(writer, 'Um0220deleted1');
      await _insertBeacon(
        writer,
        id: 'Bm0220del00001',
        author: 'Um0220deleted1',
        status: 2,
      );
      await _insertParticipant(writer, 'Bm0220del00001', _viewer);
      expect(
        await _shares(writer, user: 'Um0220deleted1', viewer: _viewer),
        isFalse,
      );
    });

    test('never true for the viewer themself or without a session', () async {
      expect(await _shares(writer, user: _viewer, viewer: _viewer), isFalse);
      final rows = await writer.execute(
        Sql.named(
          "SELECT public.user_get_shares_episode_with_viewer(u, '{}'::json) "
          'FROM public."user" u WHERE u.id = @id',
        ),
        parameters: {'id': _peer},
      );
      expect(rows.single.single, isFalse);
    });
  });
}

Future<bool> _shares(
  Connection writer, {
  required String user,
  required String viewer,
}) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT public.user_get_shares_episode_with_viewer(u, '
      "json_build_object('x-hasura-user-id', @viewer::text)) "
      'FROM public."user" u WHERE u.id = @id',
    ),
    parameters: {'id': user, 'viewer': viewer},
  );
  return rows.single.single! as bool;
}

Future<void> _insertUser(Connection writer, String id) => writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');

Future<void> _insertBeacon(
  Connection writer, {
  required String id,
  required String author,
  int status = 0,
}) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$id', '$author', 'Request', '', $status, 0, 1, false, now())
''');

Future<void> _insertParticipant(
  Connection writer,
  String beaconId,
  String userId, {
  int roomAccess = 3,
}) => writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$beaconId', '$userId', 2, $roomAccess)
''');
