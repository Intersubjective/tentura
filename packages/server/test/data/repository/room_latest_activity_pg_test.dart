@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '../../support/disposable_pg_target.dart';

/// U087 — the Requests list sorts by last activity and shows the latest
/// message. `latestRoomActivities` gives, per Request (one query per batch): the time of the latest
/// change in the discussion (message or system line, next-step edit, or a
/// logged event such as a status change) and the latest member-written
/// message with its author's name.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_LATEST_ACTIVITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_latest_activity',
  );
  final skipReason = await pgSkipReason(target);

  const authorId = 'Ulatestauth1';
  const ninaId = 'Ulatestnina1';
  const beaconId = 'Blatestact01';

  group('BeaconRoomRepository.latestRoomActivities (U087)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomRepository room;

    Future<void> message(
      String id, {
      required String? author,
      required String body,
      required String at,
      int? systemKind,
      String beacon = beaconId,
    }) => writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, '
        'body, system_message_kind, created_at) VALUES '
        '(@id, @b, @a, @body, @kind, @at::timestamptz)',
      ),
      parameters: {
        'id': id,
        'b': beacon,
        'a': author,
        'body': body,
        'kind': systemKind,
        'at': at,
      },
    );

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = TenturaDb(target.databaseEnv);
      room = BeaconRoomRepository(db);
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      await writer.execute(
        'TRUNCATE TABLE public.beacon_room_message, '
        'public.beacon_room_state, public.beacon_activity_event, '
        'public.beacon, public."user" CASCADE',
      );
      await writer.execute(
        'INSERT INTO public."user" (id, display_name, public_key) VALUES '
        "('$authorId', 'Author', 'key-a'), ('$ninaId', 'Nina', 'key-n')",
      );
      await writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description, '
        'status, kind, is_discoverable, published_at, created_at, '
        "updated_at) VALUES ('$beaconId', '$authorId', 'Moving day', 'desc', "
        "0, 0, true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
    });

    test('no ids: empty map', () async {
      expect(await room.latestRoomActivities(const []), isEmpty);
    });

    test('several Requests in one call, each with its own latest message '
        '(#541 review)', () async {
      const otherId = 'Blatestact02';
      await writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description, '
        'status, kind, is_discoverable, published_at, created_at, '
        "updated_at) VALUES ('$otherId', '$authorId', 'Other', 'desc', "
        "0, 0, true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
      await message(
        'M1',
        author: ninaId,
        body: 'First request',
        at: '2026-05-02T10:00:00Z',
      );
      await message(
        'M2',
        author: authorId,
        body: 'Second request',
        at: '2026-05-02T11:00:00Z',
        beacon: otherId,
      );

      final byId = await room.latestRoomActivities([beaconId, otherId]);

      expect(byId.keys, unorderedEquals([beaconId, otherId]));
      expect(byId[beaconId]!.lastMessageBody, 'First request');
      expect(byId[beaconId]!.lastMessageAuthorName, 'Nina');
      expect(byId[otherId]!.lastMessageBody, 'Second request');
      expect(byId[otherId]!.lastMessageAuthorName, 'Author');
    });

    test('nothing happened: no activity, no message', () async {
      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastActivityAt, isNull);
      expect(a.lastMessageAt, isNull);
      expect(a.lastMessageBody, isNull);
    });

    test('latest member message wins, with its author name', () async {
      await message(
        'M1',
        author: authorId,
        body: 'Hi all',
        at: '2026-01-02T10:00:00Z',
      );
      await message(
        'M2',
        author: ninaId,
        body: 'Parking sorted?',
        at: '2026-01-02T11:00:00Z',
      );
      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastMessageBody, 'Parking sorted?');
      expect(a.lastMessageAuthorId, ninaId);
      expect(a.lastMessageAuthorName, 'Nina');
      expect(a.lastMessageAt, DateTime.utc(2026, 1, 2, 11));
      expect(a.lastActivityAt, DateTime.utc(2026, 1, 2, 11));
    });

    test(
      'a long latest message comes back clipped to 200 characters',
      () async {
        await message(
          'M1',
          author: ninaId,
          body: 'x' * 5000,
          at: '2026-01-02T10:00:00Z',
        );
        final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
        expect(a.lastMessageBody, 'x' * 200);
      },
    );

    test(
      'a system line counts as activity but is not the latest message',
      () async {
        await message(
          'M1',
          author: ninaId,
          body: 'Parking sorted?',
          at: '2026-01-02T11:00:00Z',
        );
        await message(
          'S1',
          author: authorId,
          body: '',
          at: '2026-01-02T12:00:00Z',
          systemKind: 7,
        );
        final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
        expect(a.lastMessageBody, 'Parking sorted?');
        expect(a.lastActivityAt, DateTime.utc(2026, 1, 2, 12));
      },
    );

    test('a next-step edit counts as activity', () async {
      await message(
        'M1',
        author: ninaId,
        body: 'Parking sorted?',
        at: '2026-01-02T11:00:00Z',
      );
      await writer.execute(
        'INSERT INTO public.beacon_room_state (beacon_id, current_line, '
        "updated_at, updated_by) VALUES ('$beaconId', 'Van at 10', "
        "'2026-01-02T13:00:00Z', '$authorId')",
      );
      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastActivityAt, DateTime.utc(2026, 1, 2, 13));
    });

    test('a logged event (status change) counts as activity', () async {
      await writer.execute(
        'INSERT INTO public.beacon_activity_event (id, beacon_id, visibility, '
        "type, actor_id, created_at) VALUES ('Elatest1', '$beaconId', 0, 16, "
        "'$authorId', '2026-01-03T09:00:00Z')",
      );
      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastActivityAt, DateTime.utc(2026, 1, 3, 9));
      expect(a.lastMessageAt, isNull);
    });
  }, skip: skipReason ?? false);
}
