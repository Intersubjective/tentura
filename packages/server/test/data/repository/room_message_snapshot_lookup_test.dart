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
        'WHERE message_id IN (\'Rlookup000001\', \'Rlookup000002\', \'Rlookup000003\')',
      );
      await database.customStatement(
        'DELETE FROM public.beacon_room_message '
        'WHERE id IN (\'Rlookup000001\', \'Rlookup000002\', \'Rlookup000003\', '
        '\'Rlookupparent1\', \'Rlookupother1\')',
      );
      await database.customStatement(
        'DELETE FROM public.beacon_participant WHERE beacon_id IN '
        '(\'Blookup000001\', \'Blookupother1\')',
      );
      await database.customStatement(
        'DELETE FROM public.beacon WHERE id IN '
        '(\'Blookup000001\', \'Blookupother1\')',
      );
      await database.customStatement(
        'DELETE FROM public."user" WHERE id IN '
        '(\'Ulookup000001\', \'Ulookup000002\')',
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

  test(
    'findEligibleInsert returns reply snapshot fields for scoped parent',
    () async {
      await database.customStatement(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Ulookup000001', 'Lookup author', 'lookup-author-key'),
  ('Ulookup000002', 'Parent author', 'lookup-parent-key')
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
) VALUES
  ('Rlookupparent1', 'Blookup000001', 'Ulookup000002', 'parent body'),
  ('Rlookup000002', 'Blookup000001', 'Ulookup000001', 'reply body')
ON CONFLICT (id) DO UPDATE SET
  body = EXCLUDED.body,
  reply_to_message_id = EXCLUDED.reply_to_message_id
''',
      );
      await database.customStatement(
        '''
UPDATE public.beacon_room_message
SET reply_to_message_id = 'Rlookupparent1'
WHERE id = 'Rlookup000002'
''',
      );

      final snapshot = await lookup.findEligibleInsert(
        messageId: 'Rlookup000002',
        beaconId: 'Blookup000001',
      );

      expect(snapshot?.replyToMessageId, 'Rlookupparent1');
      expect(snapshot?.replyToAuthorId, 'Ulookup000002');
      expect(snapshot?.replyToAuthorTitle, 'Parent author');
      expect(snapshot?.replyToBodyExcerpt, 'parent body');
      expect(snapshot?.replyToHasAttachments, isFalse);
    },
    skip: skipReason,
  );

  test(
    'findEligibleInsert keeps reply id but null quote when parent is out of scope',
    () async {
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
VALUES
  ('Blookup000001', 'Ulookup000001', 'Lookup', 'Lookup test'),
  ('Blookupother1', 'Ulookup000001', 'Other', 'Other test')
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
) VALUES
  ('Rlookupother1', 'Blookupother1', 'Ulookup000001', 'other beacon parent'),
  ('Rlookup000003', 'Blookup000001', 'Ulookup000001', 'cross-scope reply')
ON CONFLICT (id) DO UPDATE SET
  body = EXCLUDED.body,
  reply_to_message_id = EXCLUDED.reply_to_message_id
''',
      );
      await database.customStatement(
        '''
UPDATE public.beacon_room_message
SET reply_to_message_id = 'Rlookupother1'
WHERE id = 'Rlookup000003'
''',
      );

      final snapshot = await lookup.findEligibleInsert(
        messageId: 'Rlookup000003',
        beaconId: 'Blookup000001',
      );

      expect(snapshot?.replyToMessageId, 'Rlookupother1');
      expect(snapshot?.replyToAuthorId, isNull);
      expect(snapshot?.replyToAuthorTitle, isNull);
      expect(snapshot?.replyToBodyExcerpt, isNull);
      expect(snapshot?.replyToHasAttachments, isFalse);
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
