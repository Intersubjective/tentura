@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/pg_test_public_keys.dart';

/// Direct SQL proof for the m0156 DB-level backstop triggers (Task 07).
///
/// These triggers are the runtime-role write protection behind
/// `BeaconRoomCase`'s application-level guards — they must independently
/// reject what the application guard rejects, and must independently permit
/// what it permits, in case some other write path ever bypasses the
/// application layer. No other test in the suite exercises this SQL at all.
Future<void> main() async {
  final target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for m0156 guard PG test';

  group('m0156 general-only + lifecycle write guard triggers — disposable Postgres',
      () {
    late Connection writer;

    const userId = 'Um0156guard1';
    const openBeaconId = 'Bm0156guard1';
    const closedBeaconId = 'Bm0156guard2';
    const itemId = 'CIm0156grd01';

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, now(), now())
'''),
        parameters: {'id': userId, 'key': pgTestPublicKey('m0156', 1)},
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES (@id, @user, 't', 'd', 0, now(), now())
'''),
        parameters: {'id': openBeaconId, 'user': userId},
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES (@id, @user, 't', 'd', 6, now(), now())
'''),
        parameters: {'id': closedBeaconId, 'user': userId},
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.coordination_item (id, beacon_id, kind, creator_id)
VALUES (@id, @beacon, 1, @user)
'''),
        parameters: {'id': itemId, 'beacon': openBeaconId, 'user': userId},
      );
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await writer.close();
      await target.drop();
    });

    Future<void> insertMessage({
      required String id,
      required String beaconId,
      String? authorId,
      String? threadItemId,
      int? systemMessageKind,
    }) => writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, thread_item_id, system_message_kind, created_at)
VALUES (@id, @beacon, @author, '', @thread, @kind, now())
'''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'author': authorId,
        'thread': threadItemId,
        'kind': systemMessageKind,
      },
    );

    test(
      'lifecycle guard rejects an ordinary user message on a closed beacon',
      () async {
        await expectLater(
          insertMessage(
            id: 'Rm0156g001',
            beaconId: closedBeaconId,
            authorId: userId,
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.message,
              'message',
              contains('discussion_read_only'),
            ),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'lifecycle guard permits a system-authored notice on the same closed beacon',
      () async {
        await insertMessage(
          id: 'Rm0156g002',
          beaconId: closedBeaconId,
          authorId: null,
          systemMessageKind: 1,
        );
        final rows = await writer.execute(
          Sql.named(
            'SELECT id FROM public.beacon_room_message WHERE id = @id',
          ),
          parameters: {'id': 'Rm0156g002'},
        );
        expect(rows, hasLength(1));
      },
      skip: skipReason,
    );

    test(
      'general-only guard rejects a non-General insert on an open beacon '
      'with no fixture bypass',
      () async {
        await expectLater(
          insertMessage(
            id: 'Rm0156g003',
            beaconId: openBeaconId,
            authorId: userId,
            threadItemId: itemId,
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.message,
              'message',
              contains('discussion_scope_disabled'),
            ),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'general-only guard permits the same non-General insert when the '
      'internal dormant-fixture GUC is explicitly set',
      () async {
        await writer.execute(
          "SET tentura.discussion_internal_fixture = 'allow_non_general'",
        );
        await insertMessage(
          id: 'Rm0156g004',
          beaconId: openBeaconId,
          authorId: userId,
          threadItemId: itemId,
        );
        await writer.execute('RESET tentura.discussion_internal_fixture');
        final rows = await writer.execute(
          Sql.named(
            'SELECT id FROM public.beacon_room_message WHERE id = @id',
          ),
          parameters: {'id': 'Rm0156g004'},
        );
        expect(rows, hasLength(1));
      },
      skip: skipReason,
    );

    test(
      'ordinary General message on an open beacon succeeds',
      () async {
        await insertMessage(
          id: 'Rm0156g005',
          beaconId: openBeaconId,
          authorId: userId,
        );
        final rows = await writer.execute(
          Sql.named(
            'SELECT id FROM public.beacon_room_message WHERE id = @id',
          ),
          parameters: {'id': 'Rm0156g005'},
        );
        expect(rows, hasLength(1));
      },
      skip: skipReason,
    );
  });
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}
