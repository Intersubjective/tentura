@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/room_message_snapshot_lookup.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final env = Env(
    environment: Environment.test,
    pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
    pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
    pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
    printEnv: false,
    isDebugModeOn: false,
  );
  final reachable = await _canConnect(env);
  final skipReason = reachable ? false : 'Postgres not reachable for lookup test';

  late TenturaDb database;
  late RoomMessageSnapshotLookup lookup;

  if (skipReason == false) {
    setUpAll(() async {
      database = TenturaDb(env);
      lookup = RoomMessageSnapshotLookup(database);
    });

    tearDownAll(() async {
      await database.close();
    });

    tearDown(() async {
      await database.customStatement(
        'DELETE FROM public.beacon_room_message_attachment '
        'WHERE message_id = \'Rlookup000001\'',
      );
      await database.customStatement(
        'DELETE FROM public.beacon_room_message WHERE id = \'Rlookup000001\'',
      );
      await database.customStatement(
        'DELETE FROM public.beacon_participant WHERE beacon_id = \'Blookup000001\'',
      );
      await database.customStatement(
        'DELETE FROM public.beacon WHERE id = \'Blookup000001\'',
      );
      await database.customStatement(
        'DELETE FROM public."user" WHERE id = \'Ulookup000001\'',
      );
    });
  }

  Future<void> seedPlainMessage() async {
    await database.customStatement(
      '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Ulookup000001', 'Lookup author', 'lookup-author-key')
ON CONFLICT (id) DO NOTHING
''',
    );
    await database.customStatement(
      '''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES ('Blookup000001', 'Ulookup000001', 'Lookup', 'Lookup test')
ON CONFLICT (id) DO NOTHING
''',
    );
    await database.customStatement(
      '''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access
) VALUES ('Plookup000001', 'Blookup000001', 'Ulookup000001', 2, 0, 3)
ON CONFLICT DO NOTHING
''',
    );
    await database.customStatement(
      '''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body
) VALUES ('Rlookup000001', 'Blookup000001', 'Ulookup000001', 'eligible text')
ON CONFLICT (id) DO UPDATE SET body = EXCLUDED.body
''',
    );
  }

  test(
    'findEligibleInsert returns plain text snapshot',
    () async {
      await seedPlainMessage();
      final snapshot = await lookup.findEligibleInsert(
        messageId: 'Rlookup000001',
        beaconId: 'Blookup000001',
      );
      expect(snapshot?.body, 'eligible text');
      expect(snapshot?.authorId, 'Ulookup000001');
    },
    skip: skipReason,
  );

  test(
    'findEligibleInsert returns null for blank body',
    () async {
      await seedPlainMessage();
      await database.customStatement(
        'UPDATE public.beacon_room_message SET body = \'\' '
        'WHERE id = \'Rlookup000001\'',
      );
      final snapshot = await lookup.findEligibleInsert(
        messageId: 'Rlookup000001',
        beaconId: 'Blookup000001',
      );
      expect(snapshot, isNull);
    },
    skip: skipReason,
  );

  test(
    'findEligibleInsert returns null when attachment exists',
    () async {
      await seedPlainMessage();
      await database.customStatement(
        '''
INSERT INTO public.beacon_room_message_attachment (
  id, message_id, kind, mime, size_bytes
) VALUES ('Alookup000001', 'Rlookup000001', 1, 'image/png', 1)
ON CONFLICT (id) DO NOTHING
''',
      );
      final snapshot = await lookup.findEligibleInsert(
        messageId: 'Rlookup000001',
        beaconId: 'Blookup000001',
      );
      expect(snapshot, isNull);
    },
    skip: skipReason,
  );

  test(
    'findEligibleInsert returns null for mismatched beacon',
    () async {
      await seedPlainMessage();
      final snapshot = await lookup.findEligibleInsert(
        messageId: 'Rlookup000001',
        beaconId: 'Bwrong000001',
      );
      expect(snapshot, isNull);
    },
    skip: skipReason,
  );
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
