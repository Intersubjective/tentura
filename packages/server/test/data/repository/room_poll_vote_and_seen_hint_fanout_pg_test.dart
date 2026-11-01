@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/polling_act_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_test_public_keys.dart';

/// A vote on a room poll and a read mark in a Request chat must each reach
/// every member who may have the chat open — the Request author (who has no
/// participant row) and every admitted participant — as a realtime hint, so
/// their open chats update poll counts and read receipts without a reload.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_HINT_FANOUT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_hint_fanout',
  );
  final skipReason = await pgSkipReason(target);
  late DisposablePgWriterSession session;
  late TenturaDb db;
  late BeaconRoomRepository room;
  late PollingActRepository pollingActs;
  late Connection listener;
  late PgNotificationRecorder recorder;

  const authorId = 'Uhintauthor1';
  const voterId = 'Uhintvoter01';
  const readerId = 'Uhintreader1';
  const watcherId = 'Uhintwatch01';
  const outsiderId = 'Uhintoutside';
  const beaconId = 'Bhintfanout1';
  const pollId = 'Phintfanout1';
  const yesVariantId = 'Vhintfanyes1';
  const noVariantId = 'Vhintfanno01';
  const pollMessageId = 'Mhintfanpoll';

  const roomMembers = {authorId, voterId, readerId, watcherId};

  Future<void> barrier(String token) => session.writer.execute(
    Sql.named("SELECT pg_notify('entity_changes', @payload)"),
    parameters: {
      'payload': jsonEncode({'entity': 'barrier', 'id': token}),
    },
  );

  setUpAll(() async {
    if (skipReason != null) return;
    session = await setUpDisposablePgWriter(target: target);
    db = TenturaDb(target.databaseEnv);
    room = BeaconRoomRepository(db);
    pollingActs = PollingActRepository(db);
    listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    await listener.execute('LISTEN entity_changes');
    recorder = PgNotificationRecorder(listener.channels['entity_changes']);

    final writer = session.writer;
    final users = [authorId, voterId, readerId, watcherId, outsiderId];
    for (var i = 0; i < users.length; i++) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': users[i], 'key': pgTestPublicKey('hintfan', i + 1)},
      );
    }
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon (id, user_id, title, description) '
        "VALUES (@beaconId, @authorId, 'Lunch', 'Pick a day')",
      ),
      parameters: {'beaconId': beaconId, 'authorId': authorId},
    );
    // The author has no participant row; three admitted members and one
    // participant without room access.
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES
  ('Phintpart001', @beaconId, @voterId, 0, 0, @admitted, now(), now()),
  ('Phintpart002', @beaconId, @readerId, 0, 0, @admitted, now(), now()),
  ('Phintpart003', @beaconId, @watcherId, 0, 0, @admitted, now(), now()),
  ('Phintpart004', @beaconId, @outsiderId, 0, 0, @none, now(), now())
'''),
      parameters: {
        'beaconId': beaconId,
        'voterId': voterId,
        'readerId': readerId,
        'watcherId': watcherId,
        'outsiderId': outsiderId,
        'admitted': RoomAccessBits.admitted,
        'none': RoomAccessBits.none,
      },
    );
    await writer.execute(
      Sql.named(
        'INSERT INTO public.polling (id, author_id, question) '
        "VALUES (@pollId, @authorId, 'Which day?')",
      ),
      parameters: {'pollId': pollId, 'authorId': authorId},
    );
    await writer.execute(
      Sql.named(
        'INSERT INTO public.polling_variant (id, polling_id, description) '
        "VALUES (@yes, @pollId, 'Monday'), (@no, @pollId, 'Tuesday')",
      ),
      parameters: {'yes': yesVariantId, 'no': noVariantId, 'pollId': pollId},
    );
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_room_message '
        '(id, beacon_id, author_id, body, linked_polling_id, created_at) '
        "VALUES (@id, @beaconId, @authorId, '', @pollId, "
        "now() - interval '1 minute')",
      ),
      parameters: {
        'id': pollMessageId,
        'beaconId': beaconId,
        'authorId': authorId,
        'pollId': pollId,
      },
    );
  });

  tearDownAll(() async {
    if (skipReason != null) return;
    await recorder.cancel();
    await listener.close();
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  Set<String> recipientsOf(String entity) => {
    for (final message in recorder.messages)
      if (message['entity'] == entity && message['id'] == beaconId)
        ...(message['user_ids']! as List).cast<String>(),
  };

  group(
    'Request chat realtime hints reach every member with the chat open',
    () {
      test(
        'a poll vote hints the Request author and every admitted member',
        () async {
          await recorder.drain(sendBarrier: barrier);

          await pollingActs.upsert(
            authorId: voterId,
            pollingId: pollId,
            variantIds: const [yesVariantId],
            pollType: 'single',
            allowRevote: true,
          );
          await recorder.flush(sendBarrier: barrier);

          final recipients = recipientsOf('room_poll');
          expect(
            recipients,
            containsAll(roomMembers),
            reason:
                'every member with the chat open must get the room_poll hint '
                'for the vote (got $recipients)',
          );
          expect(recipients, isNot(contains(outsiderId)));
        },
        skip: skipReason,
      );

      test(
        'a read mark hints the Request author and every admitted member',
        () async {
          await recorder.drain(sendBarrier: barrier);

          await room.markBeaconRoomSeen(
            userId: readerId,
            beaconId: beaconId,
            threadItemId: null,
            at: DateTime.timestamp(),
          );
          await recorder.flush(sendBarrier: barrier);

          final peerHints = recorder.messages
              .where(
                (m) => m['entity'] == 'room_seen_peer' && m['id'] == beaconId,
              )
              .toList();
          expect(peerHints, isNotEmpty, reason: 'the read mark sent no hint');
          expect(peerHints.last['seen_user_id'], readerId);
          final recipients = recipientsOf('room_seen_peer');
          expect(
            recipients,
            containsAll(roomMembers),
            reason:
                'every member with the chat open must get the read-mark hint '
                '(got $recipients)',
          );
          expect(recipients, isNot(contains(outsiderId)));
        },
        skip: skipReason,
      );
    },
    skip: skipReason,
  );
}
