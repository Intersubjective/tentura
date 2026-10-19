@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '../../support/disposable_pg_target.dart';

/// #498 — a message with no text (a photo, a file, a poll, a quoted fact) is
/// still the latest message on the Requests card. `latestRoomActivities`
/// returns it with its kind (`lastMessageKind`: image, file, poll or fact) so
/// the client can say "📷 Photo" instead of skipping it or showing "—".
/// A text message has no kind (null): its text is the preview.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_LATEST_NON_TEXT_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_latest_non_text',
  );
  final skipReason = await pgSkipReason(target);

  const authorId = 'Unontextau1';
  const ninaId = 'Unontextni1';
  const beaconId = 'Bnontext001';
  const textAt = '2026-01-02T10:00:00Z';
  const laterAt = '2026-01-02T11:00:00Z';

  group('latestRoomActivities: messages without text (#498)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomRepository room;

    Future<void> message(
      String id, {
      required String author,
      required String body,
      required String at,
      String? pollingId,
      String? quotedFactId,
      int? quotedFactSeq,
    }) => writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, '
        'body, linked_polling_id, quoted_fact_card_id, '
        'quoted_fact_revision_seq, created_at) VALUES '
        '(@id, @b, @a, @body, @poll, @fact, @seq, @at::timestamptz)',
      ),
      parameters: {
        'id': id,
        'b': beaconId,
        'a': author,
        'body': body,
        'poll': pollingId,
        'fact': quotedFactId,
        'seq': quotedFactSeq,
        'at': at,
      },
    );

    Future<void> attachment(String messageId, {required int kind}) =>
        writer.execute(
          Sql.named(
            'INSERT INTO public.beacon_room_message_attachment (id, '
            'message_id, kind, file_url, file_name, mime) VALUES '
            "(@id, @m, @kind, 'https://example.test/f', 'f.bin', "
            "'application/octet-stream')",
          ),
          parameters: {'id': 'A$messageId', 'm': messageId, 'kind': kind},
        );

    Future<void> textFirst() => message(
      'Mtext',
      author: authorId,
      body: 'Parking sorted?',
      at: textAt,
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
        'TRUNCATE TABLE public.beacon_room_message_attachment, '
        'public.beacon_room_message, public.polling, '
        'public.beacon_fact_card_revision, public.beacon_fact_card, '
        'public.beacon_room_state, public.beacon_activity_event, '
        'public.beacon, public."user" CASCADE',
      );
      await writer.execute(
        'INSERT INTO public."user" (id, display_name, public_key) VALUES '
        "('$authorId', 'Author', 'key-nt-a'), "
        "('$ninaId', 'Nina', 'key-nt-n')",
      );
      await writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description, '
        'status, kind, is_discoverable, published_at, created_at, '
        "updated_at) VALUES ('$beaconId', '$authorId', 'Moving day', 'desc', "
        "0, 0, true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
    });

    test('a photo with no caption is the latest message, kind image', () async {
      await textFirst();
      await message('Mphoto', author: ninaId, body: '', at: laterAt);
      await attachment('Mphoto', kind: BeaconRoomMessageAttachmentKind.image);
      // Vacuity guard: the photo row really is stored with a blank body.
      final raw = await writer.execute(
        "SELECT body FROM public.beacon_room_message WHERE id = 'Mphoto'",
      );
      expect(raw.single.single, '');

      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastMessageAt, DateTime.utc(2026, 1, 2, 11));
      expect(a.lastMessageAuthorId, ninaId);
      expect(a.lastMessageAuthorName, 'Nina');
      expect(a.lastMessageKind, 'image');
      // No text of its own: never the older text, never a placeholder.
      expect(a.lastMessageBody ?? '', isEmpty);
    });

    test('a file with no caption is the latest message, kind file', () async {
      await textFirst();
      await message('Mfile', author: ninaId, body: '', at: laterAt);
      await attachment('Mfile', kind: BeaconRoomMessageAttachmentKind.file);

      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastMessageAt, DateTime.utc(2026, 1, 2, 11));
      expect(a.lastMessageAuthorId, ninaId);
      expect(a.lastMessageKind, 'file');
      expect(a.lastMessageBody ?? '', isEmpty);
    });

    test('a poll is the latest message, kind poll', () async {
      await textFirst();
      await writer.execute(
        'INSERT INTO public.polling (id, author_id, question) VALUES '
        "('Pnontext01', '$ninaId', 'Pizza or sushi?')",
      );
      await message(
        'Mpoll',
        author: ninaId,
        body: '',
        at: laterAt,
        pollingId: 'Pnontext01',
      );

      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastMessageAt, DateTime.utc(2026, 1, 2, 11));
      expect(a.lastMessageAuthorId, ninaId);
      expect(a.lastMessageKind, 'poll');
    });

    test(
      'a quoted fact with no text is the latest message, kind fact',
      () async {
        await textFirst();
        await writer.execute(
          'INSERT INTO public.beacon_fact_card (id, beacon_id, fact_text, '
          'visibility, pinned_by, status, created_at, updated_at, '
          "revision_seq) VALUES ('Fnontext01', '$beaconId', 'Van at 10', "
          '${BeaconFactCardVisibilityBits.public}, '
          "'$authorId', ${BeaconFactCardStatusBits.active}, '$textAt', "
          "'$textAt', 1)",
        );
        await writer.execute(
          'INSERT INTO public.beacon_fact_card_revision (fact_card_id, seq, '
          "fact_text, actor_id, kind, created_at) VALUES ('Fnontext01', 1, "
          "'Van at 10', '$authorId', "
          "${BeaconFactCardRevisionKindBits.created}, '$textAt')",
        );
        await message(
          'Mfact',
          author: ninaId,
          body: '',
          at: laterAt,
          quotedFactId: 'Fnontext01',
          quotedFactSeq: 1,
        );

        final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
        expect(a.lastMessageAt, DateTime.utc(2026, 1, 2, 11));
        expect(a.lastMessageAuthorId, ninaId);
        expect(a.lastMessageKind, 'fact');
        expect(a.lastMessageBody ?? '', isEmpty);
      },
    );

    test('a photo with a caption previews the caption', () async {
      await textFirst();
      await message('Mcap', author: ninaId, body: 'The van', at: laterAt);
      await attachment('Mcap', kind: BeaconRoomMessageAttachmentKind.image);

      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastMessageBody, 'The van');
      expect(a.lastMessageAuthorId, ninaId);
    });

    test('guard: a plain text message has no kind', () async {
      await textFirst();
      final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
      expect(a.lastMessageBody, 'Parking sorted?');
      expect(a.lastMessageKind, isNull);
    });

    test(
      'guard: a blank message with nothing attached is still skipped',
      () async {
        await textFirst();
        await message('Mblank', author: ninaId, body: '   ', at: laterAt);

        final a = (await room.latestRoomActivities([beaconId]))[beaconId]!;
        expect(a.lastMessageBody, 'Parking sorted?');
        expect(a.lastMessageAuthorId, authorId);
        expect(a.lastMessageAt, DateTime.utc(2026, 1, 2, 10));
        expect(a.lastMessageKind, isNull);
      },
    );
  }, skip: skipReason ?? false);
}
