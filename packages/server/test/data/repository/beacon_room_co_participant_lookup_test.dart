@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_co_participant_lookup.dart';
import 'package:tentura_server/env.dart';

/// Admitted beacon-room co-participant lookup — skipped when Postgres unavailable.
Future<void> main() async {
  var skipReason = false;
  TenturaDb? probe;

  try {
    probe = TenturaDb(_testEnv());
    await probe.customStatement('SELECT 1');
  } on Object {
    skipReason = true;
  } finally {
    await probe?.close();
  }

  late TenturaDb db;
  late BeaconRoomCoParticipantLookup lookup;

  if (!skipReason) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      lookup = BeaconRoomCoParticipantLookup(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.beacon_participant WHERE beacon_id = 'Bcopres01'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id = 'Bcopres01'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id LIKE 'Ucopres%' ''',
      );
    });
  }

  Future<void> seedFixture() async {
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Ucopresviewer', 'Viewer', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ucoprespeer', 'Peer', $2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ucopresother', 'Other', $3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ucopresnoshare', 'NoShare', $4, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      [
        '${'v' * 43}1',
        '${'p' * 43}2',
        '${'o' * 43}3',
        '${'n' * 43}4',
      ],
    );
    await db.customStatement(
      r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES ('Bcopres01', 'Ucopresviewer', 'Co-pres beacon', 'Co-pres beacon', 1,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
    await db.customStatement(
      '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access, created_at, updated_at)
VALUES
  ('Pcopresviewer', 'Bcopres01', 'Ucopresviewer', 0, 0, ${RoomAccessBits.admitted},
    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Pcoprespeer', 'Bcopres01', 'Ucoprespeer', 2, 0, ${RoomAccessBits.admitted},
    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Pcopresother', 'Bcopres01', 'Ucopresother', 2, 0, ${RoomAccessBits.requested},
    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  test(
    'returns admitted co-participants sharing a room',
    () async {
      await seedFixture();

      final result = await lookup.coParticipantPeerIds(
        viewerId: 'Ucopresviewer',
        peerIds: ['Ucoprespeer', 'Ucopresother', 'Ucopresnoshare'],
      );

      expect(result, {'Ucoprespeer'});
    },
    skip: skipReason ? 'Postgres not reachable' : false,
  );

  test(
    'excludes viewer and empty ids',
    () async {
      await seedFixture();

      final result = await lookup.coParticipantPeerIds(
        viewerId: 'Ucopresviewer',
        peerIds: ['Ucopresviewer', '', 'Ucoprespeer'],
      );

      expect(result, {'Ucoprespeer'});
    },
    skip: skipReason ? 'Postgres not reachable' : false,
  );
}

Env _testEnv() => Env(environment: Environment.test);
