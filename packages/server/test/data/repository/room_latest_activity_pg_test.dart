@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/room_latest_activity.dart';

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
      expect(
        await room.latestRoomActivities(const [], viewerUserId: authorId),
        isEmpty,
      );
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

      final byId = await room.latestRoomActivities([
        beaconId,
        otherId,
      ], viewerUserId: authorId);

      expect(byId.keys, unorderedEquals([beaconId, otherId]));
      expect(byId[beaconId]!.lastMessageBody, 'First request');
      expect(byId[beaconId]!.lastMessageAuthorName, 'Nina');
      expect(byId[otherId]!.lastMessageBody, 'Second request');
      expect(byId[otherId]!.lastMessageAuthorName, 'Author');
    });

    test('nothing happened: no activity, no message', () async {
      final a = (await room.latestRoomActivities([
        beaconId,
      ], viewerUserId: authorId))[beaconId]!;
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
      final a = (await room.latestRoomActivities([
        beaconId,
      ], viewerUserId: authorId))[beaconId]!;
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
        final a = (await room.latestRoomActivities([
          beaconId,
        ], viewerUserId: authorId))[beaconId]!;
        expect(a.lastMessageBody, 'x' * 200);
      },
    );

    test(
      'blank lines are collapsed before the 200-character cut (#541 review)',
      () async {
        await message(
          'M1',
          author: ninaId,
          body: '${'x' * 100}${'\n' * 150}${'y' * 50}',
          at: '2026-01-02T10:00:00Z',
        );
        final a = (await room.latestRoomActivities([
          beaconId,
        ], viewerUserId: authorId))[beaconId]!;
        // Cut first, collapse later would drop every "y" and leave 100 "x"s
        // with no sign that the text was cut.
        expect(a.lastMessageBody, '${'x' * 100} ${'y' * 50}');
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
        final a = (await room.latestRoomActivities([
          beaconId,
        ], viewerUserId: authorId))[beaconId]!;
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
      final a = (await room.latestRoomActivities([
        beaconId,
      ], viewerUserId: authorId))[beaconId]!;
      expect(a.lastActivityAt, DateTime.utc(2026, 1, 2, 13));
    });

    test('a logged event (status change) counts as activity', () async {
      await writer.execute(
        'INSERT INTO public.beacon_activity_event (id, beacon_id, visibility, '
        "type, actor_id, created_at) VALUES ('Elatest1', '$beaconId', 0, 16, "
        "'$authorId', '2026-01-03T09:00:00Z')",
      );
      final a = (await room.latestRoomActivities([
        beaconId,
      ], viewerUserId: authorId))[beaconId]!;
      expect(a.lastActivityAt, DateTime.utc(2026, 1, 3, 9));
      expect(a.lastMessageAt, isNull);
    });

    group('W5 (#525): what counts as activity for the viewer', () {
      Future<void> addUser(String id, String name) => writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) VALUES '
          '(@id, @name, @key)',
        ),
        parameters: {'id': id, 'name': name, 'key': 'key-$id'},
      );

      Future<void> helpOffer(String userId, String at) => writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_help_offer (beacon_id, user_id, '
          'message, created_at, updated_at) VALUES '
          '(@b, @u, @m, @at::timestamptz, @at::timestamptz)',
        ),
        parameters: {'b': beaconId, 'u': userId, 'm': 'I can', 'at': at},
      );

      Future<RoomLatestActivity> latestFor(String viewer) async =>
          (await room.latestRoomActivities([
            beaconId,
          ], viewerUserId: viewer))[beaconId]!;

      setUp(() async {
        if (skipReason != null) return;
        await message(
          'M1',
          author: ninaId,
          body: 'Parking sorted?',
          at: '2026-01-02T11:00:00Z',
        );
      });

      test('a new help offer counts for the author', () async {
        await helpOffer(ninaId, '2026-01-04T08:00:00Z');
        final a = await latestFor(authorId);
        expect(a.lastActivityAt, DateTime.utc(2026, 1, 4, 8));
      });

      test('offering again after withdrawing counts (W5 review)', () async {
        // The re-offer reuses the row (its created_at stays old); the
        // append-only `offered` fact carries the new time.
        await helpOffer(ninaId, '2026-01-01T08:00:00Z');
        await writer.execute(
          'INSERT INTO public.beacon_commitment_event (id, seq, beacon_id, '
          'user_id, actor_user_id, kind, created_at) VALUES '
          "('Clatest01', 1, '$beaconId', '$ninaId', '$ninaId', 0, "
          "'2026-01-01T08:00:00Z'), "
          "('Clatest02', 2, '$beaconId', '$ninaId', '$ninaId', 3, "
          "'2026-01-01T09:00:00Z'), "
          "('Clatest03', 3, '$beaconId', '$ninaId', '$ninaId', 0, "
          "'2026-01-07T08:00:00Z')",
        );
        expect(
          (await latestFor(authorId)).lastActivityAt,
          DateTime.utc(2026, 1, 7, 8),
        );
        expect(
          (await latestFor(ninaId)).lastActivityAt,
          DateTime.utc(2026, 1, 2, 11),
        );
      });

      test('a new help offer counts for a steward', () async {
        const stewardId = 'Ulateststw01';
        await addUser(stewardId, 'Steward');
        await writer.execute(
          'INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES '
          "('$beaconId', '$stewardId')",
        );
        await helpOffer(ninaId, '2026-01-04T08:00:00Z');
        final a = await latestFor(stewardId);
        expect(a.lastActivityAt, DateTime.utc(2026, 1, 4, 8));
      });

      test('a help offer does not move it for another member', () async {
        const otherId = 'Ulatestoth01';
        await addUser(otherId, 'Other');
        await helpOffer(otherId, '2026-01-04T08:00:00Z');
        final a = await latestFor(ninaId);
        expect(a.lastActivityAt, DateTime.utc(2026, 1, 2, 11));
      });

      test('reading the discussion does not move it', () async {
        await writer.execute(
          'INSERT INTO public.beacon_room_seen (user_id, beacon_id, '
          "thread_item_id, last_seen_at) VALUES ('$authorId', '$beaconId', "
          "NULL, '2026-01-05T08:00:00Z')",
        );
        final a = await latestFor(authorId);
        expect(a.lastActivityAt, DateTime.utc(2026, 1, 2, 11));
      });

      test(
        'a Questions message moves neither the time nor the preview',
        () async {
          await writer.execute(
            'INSERT INTO public.coordination_item (id, beacon_id, kind, '
            'status, creator_id, published, published_at) VALUES '
            "('Llatestq01', '$beaconId', 7, 0, '$authorId', true, now())",
          );
          await writer.execute(
            'INSERT INTO public.beacon_room_message (id, beacon_id, '
            'author_id, body, thread_item_id, created_at) VALUES '
            "('Q1', '$beaconId', '$ninaId', 'Is there a lift?', "
            "'Llatestq01', '2026-01-06T08:00:00Z')",
          );
          final a = await latestFor(authorId);
          expect(a.lastActivityAt, DateTime.utc(2026, 1, 2, 11));
          expect(a.lastMessageBody, 'Parking sorted?');
        },
      );
    });
  }, skip: skipReason ?? false);
}
