@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';

import '../../support/disposable_pg_target.dart';

/// m0255: realtime hints about a Request **Questions** message, its
/// reactions and its attachments reach only the Questions audience
/// (`questions_audience` minus people blocked with the message author). The
/// General publishers skip Questions rows; General rows stay unchanged.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0255_QUESTIONS_HINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0255_qhint',
  );
  final skipReason = await pgSkipReason(target);

  const beaconId = 'Bqhint000001';
  const lobbyId = 'Lqhint000001';
  // General room recipient and Questions author.
  const author = 'Uqhauthor001';
  // Admitted helper: General recipient and Questions audience.
  const helper = 'Uqhhelper001';
  // Admitted helper the author removed from Questions: General only.
  const bannedHelper = 'Uqhbanned001';
  // Admitted helper blocked with the questioner: General only for their
  // messages.
  const blockedHelper = 'Uqhblockd001';
  // Live forward, asks the question: Questions audience only.
  const questioner = 'Uqhasker0001';
  // Live forward: Questions audience only.
  const forwardee = 'Uqhforwrd001';
  // Discovery-only reader: neither.
  const outsider = 'Uqhoutsid001';

  group('m0255 Questions realtime hint scope', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> subscription;
    final notifications = <Map<String, dynamic>>[];

    Future<void> sql(String statement) => writer.execute(statement);

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      subscription = listener.channels['entity_changes'].listen(
        (payload) =>
            notifications.add(jsonDecode(payload) as Map<String, dynamic>),
      );
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await subscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      await sql(
        'TRUNCATE TABLE public.beacon_room_message, '
        'public.beacon_room_message_reaction, '
        'public.beacon_room_message_attachment, public.coordination_item, '
        'public.beacon_help_offer, public.beacon_forward_edge, '
        'public.beacon_participant, public.beacon_lobby_ban, '
        'public.user_block, public.beacon, public."user" CASCADE',
      );
      final users = [
        author,
        helper,
        bannedHelper,
        blockedHelper,
        questioner,
        forwardee,
        outsider,
      ];
      await sql(
        'INSERT INTO public."user" (id, display_name, handle, public_key) '
        'VALUES ${[for (final u in users) "('$u', '${u.substring(3, 9)}', '${u.substring(3, 9)}', 'k$u')"].join(', ')}',
      );
      await sql(
        'INSERT INTO public.beacon (id, user_id, title, description, status, '
        'kind, is_discoverable, published_at, created_at, updated_at) VALUES '
        "('$beaconId', '$author', 'Moving day', 'desc', 0, 0, true, "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
      for (final u in [
        helper,
        bannedHelper,
        blockedHelper,
        questioner,
        forwardee,
      ]) {
        await sql(
          'INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, '
          "recipient_id) VALUES ('$beaconId', '$author', '$u')",
        );
      }
      for (final u in [helper, bannedHelper, blockedHelper]) {
        await sql(
          'INSERT INTO public.beacon_help_offer (beacon_id, user_id, '
          "message, status) VALUES ('$beaconId', '$u', 'I can help', 0)",
        );
        await sql(
          'INSERT INTO public.beacon_participant (beacon_id, user_id, role, '
          "status, room_access) VALUES ('$beaconId', '$u', 2, 0, 3)",
        );
      }
      await sql(
        'INSERT INTO public.beacon_lobby_ban (beacon_id, user_id, banned_by) '
        "VALUES ('$beaconId', '$bannedHelper', '$author')",
      );
      await sql(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        "VALUES ('$blockedHelper', '$questioner', '$blockedHelper')",
      );
      await sql(
        'INSERT INTO public.coordination_item (id, beacon_id, kind, status, '
        "creator_id, published, published_at) VALUES ('$lobbyId', "
        "'$beaconId', $coordinationItemKindLobby, 0, '$author', true, now())",
      );
      // Settle every setup hint before the test watches the channel.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      notifications.clear();
    });

    const roomKinds = {'room_message', 'room_reaction', 'room_poll'};

    /// Every recipient of a hint of [entity] about [beaconId] (optionally
    /// [messageId]) after [action], once the stream has gone quiet. With
    /// [forbidden], also fails when ANY room hint (any kind, any message)
    /// reached one of them.
    Future<Set<String>> recipientsAfter(
      Future<void> Function() action, {
      required String entity,
      String? messageId,
      Set<String> waitFor = const {},
      Set<String> forbidden = const {},
    }) async {
      notifications.clear();
      await action();
      Set<String> current() => {
        for (final n in notifications)
          if (n['entity'] == entity &&
              n['id'] == beaconId &&
              (messageId == null || n['message_id'] == messageId))
            ...(n['user_ids'] as List).cast<String>(),
      };
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline) &&
          !current().containsAll(waitFor)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // A late leak would arrive in the same NOTIFY batch; give it a beat.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      for (final n in notifications) {
        if (!roomKinds.contains(n['entity'])) continue;
        final leaked = (n['user_ids'] as List).cast<String>().toSet()
          ..retainAll(forbidden);
        expect(leaked, isEmpty, reason: 'room hint leaked: $n');
      }
      return current();
    }

    Future<void> insertMessage(String id, String authorId, {String? thread}) =>
        sql(
          'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, '
          "body, thread_item_id) VALUES ('$id', '$beaconId', '$authorId', "
          "'Which Saturday?', ${thread == null ? 'NULL' : "'$thread'"})",
        );

    const audience = {author, helper, questioner, forwardee};
    const outsideAudience = {bannedHelper, blockedHelper, outsider};

    test('a Questions message hint reaches only the audience '
        '(insert, edit, delete)', () async {
      const messageId = 'Mqhint000001';
      final inserted = await recipientsAfter(
        () => insertMessage(messageId, questioner, thread: lobbyId),
        entity: 'room_message',
        messageId: messageId,
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(inserted, audience);

      final edited = await recipientsAfter(
        () => sql(
          "UPDATE public.beacon_room_message SET body = 'Sunday?' "
          "WHERE id = '$messageId'",
        ),
        entity: 'room_message',
        messageId: messageId,
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(edited, audience);

      final deleted = await recipientsAfter(
        () => sql(
          "DELETE FROM public.beacon_room_message WHERE id = '$messageId'",
        ),
        entity: 'room_message',
        messageId: messageId,
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(deleted, audience);
      expect(deleted.intersection(outsideAudience), isEmpty);
    });

    test('a Questions reaction hint reaches only the audience', () async {
      const messageId = 'Mqhint000002';
      await insertMessage(messageId, questioner, thread: lobbyId);
      final added = await recipientsAfter(
        () => sql(
          'INSERT INTO public.beacon_room_message_reaction (id, message_id, '
          "user_id, emoji) VALUES ('Eqhint000001', '$messageId', '$helper', "
          "'+1')",
        ),
        entity: 'room_reaction',
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(added, audience);

      final removed = await recipientsAfter(
        () => sql(
          'DELETE FROM public.beacon_room_message_reaction '
          "WHERE id = 'Eqhint000001'",
        ),
        entity: 'room_reaction',
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(removed, audience);
    });

    test('a Questions attachment hint reaches only the audience', () async {
      const messageId = 'Mqhint000003';
      await insertMessage(messageId, questioner, thread: lobbyId);
      final added = await recipientsAfter(
        () => sql(
          'INSERT INTO public.beacon_room_message_attachment (id, message_id, '
          "kind, file_url, file_name) VALUES ('Aqhint000001', '$messageId', "
          "1, 'room/x', 'x.pdf')",
        ),
        entity: 'room_message',
        messageId: messageId,
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(added, audience);

      final removed = await recipientsAfter(
        () => sql(
          'DELETE FROM public.beacon_room_message_attachment '
          "WHERE id = 'Aqhint000001'",
        ),
        entity: 'room_message',
        messageId: messageId,
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(removed, audience);
    });

    test('General message, reaction and attachment hints are unchanged: '
        'every General recipient, banned from Questions or not', () async {
      const messageId = 'Mqhint000004';
      final general = <String>{author, helper, bannedHelper, blockedHelper};
      final inserted = await recipientsAfter(
        () => insertMessage(messageId, helper),
        entity: 'room_message',
        messageId: messageId,
        waitFor: general,
      );
      expect(inserted, general);

      final reacted = await recipientsAfter(
        () => sql(
          'INSERT INTO public.beacon_room_message_reaction (id, message_id, '
          "user_id, emoji) VALUES ('Eqhint000002', '$messageId', "
          "'$bannedHelper', '+1')",
        ),
        entity: 'room_reaction',
        waitFor: general,
      );
      expect(reacted, general);

      final attached = await recipientsAfter(
        () => sql(
          'INSERT INTO public.beacon_room_message_attachment (id, message_id, '
          "kind, file_url, file_name) VALUES ('Aqhint000002', '$messageId', "
          "1, 'room/y', 'y.pdf')",
        ),
        entity: 'room_message',
        messageId: messageId,
        waitFor: general,
      );
      expect(attached, general);

      final deleted = await recipientsAfter(
        () => sql(
          "DELETE FROM public.beacon_room_message WHERE id = '$messageId'",
        ),
        entity: 'room_message',
        messageId: messageId,
        waitFor: general,
      );
      expect(deleted, general);
    });

    test('deleting the Questions item cascades its messages with '
        'audience-only hints', () async {
      const messageId = 'Mqhint000005';
      await insertMessage(messageId, questioner, thread: lobbyId);
      await sql(
        'INSERT INTO public.beacon_room_message_reaction (id, message_id, '
        "user_id, emoji) VALUES ('Eqhint000005', '$messageId', '$helper', "
        "'+1')",
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final deleted = await recipientsAfter(
        () => sql(
          "DELETE FROM public.coordination_item WHERE id = '$lobbyId'",
        ),
        entity: 'room_message',
        messageId: messageId,
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(deleted, audience);
    });

    test('moving rows into or out of Questions never reaches people '
        'outside the audience', () async {
      const generalId = 'Mqhint000006';
      const questionId = 'Mqhint000007';
      await insertMessage(generalId, helper);
      await insertMessage(questionId, questioner, thread: lobbyId);
      await sql(
        'INSERT INTO public.beacon_room_message_reaction (id, message_id, '
        "user_id, emoji) VALUES ('Eqhint000006', '$generalId', '$helper', "
        "'+1')",
      );
      await sql(
        'INSERT INTO public.beacon_room_message_attachment (id, message_id, '
        "kind, file_url, file_name) VALUES ('Aqhint000006', '$generalId', "
        "1, 'room/z', 'z.pdf')",
      );
      // Let the General setup hints land before watching for leaks.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final reactionMoved = await recipientsAfter(
        () => sql(
          'UPDATE public.beacon_room_message_reaction '
          "SET message_id = '$questionId' WHERE id = 'Eqhint000006'",
        ),
        entity: 'room_reaction',
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(reactionMoved, audience);

      final attachmentMoved = await recipientsAfter(
        () => sql(
          'UPDATE public.beacon_room_message_attachment '
          "SET message_id = '$questionId' WHERE id = 'Aqhint000006'",
        ),
        entity: 'room_message',
        messageId: questionId,
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(attachmentMoved, audience);

      final messageMovedOut = await recipientsAfter(
        () => sql(
          'UPDATE public.beacon_room_message SET thread_item_id = NULL '
          "WHERE id = '$questionId'",
        ),
        entity: 'room_message',
        messageId: questionId,
        waitFor: audience,
        forbidden: outsideAudience,
      );
      expect(messageMovedOut, audience);
    });

    test('a Questions message can never link a poll', () async {
      await expectLater(
        sql(
          'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, '
          'body, thread_item_id, linked_polling_id) VALUES '
          "('Mqhint000008', '$beaconId', '$questioner', '', '$lobbyId', "
          "'Pqhint000001')",
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            contains('discussion_scope_disabled'),
          ),
        ),
      );
    });
  }, skip: skipReason);
}
