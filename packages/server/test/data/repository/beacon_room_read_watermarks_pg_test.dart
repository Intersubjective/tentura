@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/room_read_watermark_record.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_ROOM_READ_WM_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_broomreadwm',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon_room_read_watermarks PG test';

  group('BeaconRoomRepository.mainRoomReadWatermarks — disposable Postgres', () {
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomRepository room;

    const beaconId = 'Brwmkgpg0001';
    const authorId = 'Ubrwmpgauth1';
    const admittedId = 'Ubrwmpgadm01';
    const demotedId = 'Ubrwmpgdom01';
    const askItemId = 'CIbrwmpgask1';

    const authorTitle = 'Author Alice';
    const admittedTitle = 'Helper Bob';
    const demotedTitle = 'Demoted Carol';

    final admittedSeenAt = DateTime.utc(2026, 6, 3, 12);
    final authorSeenAt = DateTime.utc(2026, 6, 2, 12);
    final demotedSeenAt = DateTime.utc(2026, 6, 1, 12);
    final threadSeenAt = DateTime.utc(2026, 6, 4, 12);

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
        "SET tentura.discussion_internal_fixture = 'allow_non_general'",
      );
      db = TenturaDb(target.databaseEnv);
      await db.customStatement(
        "SET tentura.discussion_internal_fixture = 'allow_non_general'",
      );
      room = BeaconRoomRepository(db);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_room_seen WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.coordination_item WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_participant WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.\"user\" WHERE id IN "
        "('$authorId', '$admittedId', '$demotedId')",
      );
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await writer.close();
      await target.drop();
    });

    Future<void> seedUser({
      required String id,
      required String displayName,
      required int slot,
    }) async {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @displayName, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name
'''),
        parameters: {
          'id': id,
          'displayName': displayName,
          'publicKey': pgTestPublicKey('brwm', slot),
        },
      );
    }

    Future<void> seedFixture() async {
      await seedUser(id: authorId, displayName: authorTitle, slot: 1);
      await seedUser(id: admittedId, displayName: admittedTitle, slot: 2);
      await seedUser(id: demotedId, displayName: demotedTitle, slot: 3);

      await writer.execute(
        '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('$beaconId', '$authorId', 'Read WM PG', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );

      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES
  ('Pbrwmpgadm01', @beaconId, @admittedId, @helperRole, 0, @admitted, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Pbrwmpgdom01', @beaconId, @demotedId, @helperRole, 0, @none, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET room_access = EXCLUDED.room_access
'''),
        parameters: {
          'beaconId': beaconId,
          'admittedId': admittedId,
          'demotedId': demotedId,
          'helperRole': BeaconParticipantRoleBits.helper,
          'admitted': RoomAccessBits.admitted,
          'none': RoomAccessBits.none,
        },
      );

      await writer.execute(
        Sql.named(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id,
  published, created_at, updated_at, published_at, source, ordering
) VALUES (
  @id, @beaconId, @kind, @status, 'Ask', '', @creatorId,
  true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
  @source, 0
)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': askItemId,
          'beaconId': beaconId,
          'kind': coordinationItemKindAsk,
          'status': coordinationItemStatusOpen,
          'creatorId': authorId,
          'source': coordinationItemSourceDefault,
        },
      );

      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES
  (@authorId, @beaconId, NULL, @authorSeenAt),
  (@admittedId, @beaconId, NULL, @admittedSeenAt),
  (@demotedId, @beaconId, NULL, @demotedSeenAt),
  (@authorId, @beaconId, @askItemId, @threadSeenAt)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'authorId': authorId,
          'admittedId': admittedId,
          'demotedId': demotedId,
          'beaconId': beaconId,
          'askItemId': askItemId,
          'authorSeenAt': authorSeenAt,
          'admittedSeenAt': admittedSeenAt,
          'demotedSeenAt': demotedSeenAt,
          'threadSeenAt': threadSeenAt,
        },
      );
    }

    test(
      'returns General watermarks only, newest first, with hydrated user meta',
      () async {
        if (skipReason != false) {
          return;
        }
        await seedFixture();

        final rows = await room.mainRoomReadWatermarks(beaconId);

        expect(rows, hasLength(3));
        expect(
          rows.map((r) => r.userId).toList(),
          [admittedId, authorId, demotedId],
        );
        expect(
          rows.map((r) => r.lastSeenAt.toUtc()).toList(),
          [admittedSeenAt, authorSeenAt, demotedSeenAt],
        );

        final byUserId = {for (final row in rows) row.userId: row};

        expect(byUserId[authorId]!.userTitle, authorTitle);
        expect(byUserId[admittedId]!.userTitle, admittedTitle);
        expect(byUserId[demotedId]!.userTitle, demotedTitle);

        for (final row in rows) {
          expect(row.userTitle, isNotEmpty);
          expect(row.lastSeenAt.isUtc, isTrue);
          expect(row.userHasPicture, isFalse);
          expect(row.userPicHeight, 0);
          expect(row.userPicWidth, 0);
          expect(row.userBlurHash, '');
          expect(row.userImageId, '');
        }

        for (final row in rows) {
          expect(row, isA<RoomReadWatermarkRecord>());
        }
      },
      skip: skipReason,
    );

    test(
      'General watermark select uses beacon_room_seen_beacon_general_idx without Sort',
      () async {
        if (skipReason != false) {
          return;
        }
        await seedFixture();

        await writer.execute('SET enable_seqscan = off');
        final plan = await writer.execute(
          Sql.named(r'''
EXPLAIN (COSTS OFF)
SELECT user_id, last_seen_at
FROM public.beacon_room_seen
WHERE beacon_id = @beaconId
  AND thread_item_id IS NULL
ORDER BY last_seen_at DESC
'''),
          parameters: {'beaconId': beaconId},
        );
        final planText = plan.map((row) => row.single).join('\n');

        expect(planText, contains('beacon_room_seen_beacon_general_idx'));
        expect(planText, isNot(contains('Sort')));
      },
      skip: skipReason,
    );
  });
}
