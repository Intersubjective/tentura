@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/controllers/websocket_controller.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import '../../api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_test_public_keys.dart';

const _ann = 'Uaaaaaaaaaaaa';
const _bob = 'Ubbbbbbbbbbbb';
const _carol = 'Ucccccccccccc';
const _dave = 'Udddddddddddd';
const _requestAuthor = 'Ueeeeeeeeeeee';
const _requestMember = 'Uffffffffffff';
const _post = 'Bbudhintpost1';
const _bud = 'Bbudhintchild';
const _request = 'Bbudhintreq01';
const _requestChild = 'Bbudhintreq02';
const _budRoomMessage = 'Rbudhintchat1';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PRIVATE_BUD_REALTIME_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_private_bud_rt',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late Connection writer;
  late PgNotificationRecorder recorder;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    writer = session.writer;
    final listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    addTearDown(listener.close);
    await listener.execute('LISTEN entity_changes');
    recorder = PgNotificationRecorder(listener.channels['entity_changes']);
    addTearDown(recorder.cancel);
  });

  Future<bool> canRead(String beaconId, String userId) async {
    final rows = await writer.execute(
      Sql.named('SELECT public.beacon_can_read_content(@beacon, @viewer)'),
      parameters: {'beacon': beaconId, 'viewer': userId},
    );
    return rows.single.single! as bool;
  }

  setUp(() async {
    await writer.execute('TRUNCATE public."user", public.beacon CASCADE');
    await _seed(writer);
    final bud = await writer.execute(
      Sql.named('SELECT published_at FROM public.beacon WHERE id = @id'),
      parameters: {'id': _bud},
    );
    expect(bud.single.single, isNull);
    expect(await canRead(_post, _bob), isTrue);
    expect(await canRead(_bud, _bob), isFalse);
    expect(await canRead(_bud, _carol), isTrue);
    expect(await canRead(_bud, _dave), isTrue);
  });

  Future<void> barrier(String token) => writer.execute(
    Sql.named("SELECT pg_notify('entity_changes', @payload)"),
    parameters: {
      'payload': jsonEncode({'entity': 'barrier', 'id': token}),
    },
  );

  Future<List<Map<String, dynamic>>> record(
    Future<void> Function() write,
  ) async {
    await recorder.drain(sendBarrier: barrier);
    await write();
    await recorder.flush(sendBarrier: barrier);
    return List.of(recorder.messages);
  }

  Future<Set<String>> messageAudience({
    required String roomId,
    required String messageId,
    required Future<void> Function() write,
  }) async {
    final notifications = await record(write);
    final matching = notifications.where(
      (message) =>
          message['entity'] == 'room_message' &&
          message['id'] == roomId &&
          message['message_id'] == messageId,
    );
    expect(
      matching,
      isNotEmpty,
      reason:
          'Expected a room_message notification for room $roomId '
          'and message $messageId. Received $notifications.',
    );
    return _audience(matching);
  }

  Future<void> publishBud() => writer.execute(
    "UPDATE public.beacon SET published_at = now() WHERE id = '$_bud'",
  );

  Future<void> editTitle(String id) => writer.execute(
    Sql.named("UPDATE public.beacon SET title = title || '!' WHERE id = @id"),
    parameters: {'id': id},
  );

  Future<void> insertMessage(
    String id, {
    String room = _bud,
    String author = _dave,
  }) => writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@id, @room, @author, 'The meeting starts at noon.')
'''),
    parameters: {'id': id, 'room': room, 'author': author},
  );

  test(
    'unpublished bud Chat reaches the author and current invitees',
    () async {
      final beforeInvite = await messageAudience(
        roomId: _bud,
        messageId: _budRoomMessage,
        write: () => insertMessage(_budRoomMessage),
      );

      await _invite(writer, _bud, _dave, _bob);
      expect(await canRead(_bud, _bob), isTrue);
      const nextMessage = 'Rbudhintchat2';
      final afterInvite = await messageAudience(
        roomId: _bud,
        messageId: nextMessage,
        write: () => insertMessage(nextMessage),
      );

      expect(
        {'before invitation': beforeInvite, 'after invitation': afterInvite},
        {
          'before invitation': allOf(
            containsAll([_carol, _dave]),
            isNot(contains(_bob)),
          ),
          'after invitation': containsAll([_bob, _carol, _dave]),
        },
      );
    },
  );

  test('Post Chat notices respect an unpublished bud’s read access', () async {
    const eventId = 'HEbudhint0001';
    await writer.execute('''
INSERT INTO public.beacon_hierarchy_events
  (id, source_beacon_id, source_sequence, from_status, to_status,
   occurred_at, actor_user_id)
VALUES ('$eventId', '$_bud', 1, 0, 1, now(), '$_dave')
''');

    Future<Set<String>> notice(
      String id,
      int kind,
      Map<String, String> payload, {
      String? author,
    }) => messageAudience(
      roomId: _post,
      messageId: id,
      write: () => writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, system_message_kind, system_payload)
VALUES (@id, @room, @author, @kind::smallint, @payload::jsonb)
'''),
        parameters: {
          'id': id,
          'room': _post,
          'author': TypedValue(Type.text, author),
          'kind': kind,
          'payload': jsonEncode({'version': 1, ...payload}),
        },
      ),
    );

    Future<Set<String>> closureNotice(String id, String reason) => notice(
      id,
      BeaconRoomSystemMessageKind.postClosed,
      {'childBeaconId': _bud, 'reason': reason},
      author: _ann,
    );

    const ordinaryMessage = 'Rbudhintplain';
    final audiences = {
      'child creation': await notice(
        'Rbudhintnew01',
        BeaconRoomSystemMessageKind.childCreated,
        {'kind': 'childCreated', 'childBeaconId': _bud},
        author: _dave,
      ),
      'child lifecycle': await notice(
        'Rbudhintlife1',
        BeaconRoomSystemMessageKind.hierarchyLifecycle,
        {'kind': 'hierarchyLifecycle', 'eventId': eventId},
      ),
      'Post closed by budding': await closureNotice(
        'Rbudhintclose',
        PostClosedNoticeReason.budded,
      ),
      'Post expiration': await closureNotice(
        'Rbudhintexpir',
        PostClosedNoticeReason.expired,
      ),
      'Post closed by author': await closureNotice(
        'Rbudhintauthc',
        PostClosedNoticeReason.closedByAuthor,
      ),
      'ordinary Post message': await messageAudience(
        roomId: _post,
        messageId: ordinaryMessage,
        write: () => insertMessage(ordinaryMessage, room: _post, author: _ann),
      ),
    };

    final budReaders = allOf(contains(_carol), isNot(contains(_bob)));
    expect(audiences, {
      'child creation': allOf(budReaders, contains(_dave)),
      'child lifecycle': budReaders,
      // Indistinguishable from a plain close for an uninvited Post member.
      'Post closed by budding': contains(_bob),
      'Post expiration': contains(_bob),
      'Post closed by author': contains(_bob),
      'ordinary Post message': contains(_bob),
    });
  });

  test('publishing or editing a bud keeps hierarchy hints private', () async {
    List<Map<String, dynamic>> hierarchyHints(
      List<Map<String, dynamic>> messages,
      Set<String> ids,
    ) => [
      for (final message in messages)
        if (message['entity'] == 'beacon_hierarchy' &&
            ids.contains(message['id']))
          message,
    ];

    final publish = await record(publishBud);
    final edit = await record(() => editTitle(_bud));
    await expectLater(
      editTitle(_post),
      throwsA(
        isA<ServerException>()
            .having((error) => error.code, 'SQLSTATE', '23514')
            .having(
              (error) => error.constraintName,
              'constraint',
              'beacon_post_shape_ck',
            ),
      ),
    );
    // The author can edit the Post's composer text before its root commits
    // (BeaconRepository.updatePostDraft). This changes its own projection.
    final postEdit = await record(() async {
      final updated = await writer.execute('''
UPDATE public.beacon
SET description = 'The garden opens at noon.', updated_at = now()
WHERE id = '$_post' AND user_id = '$_ann' AND kind = 1
  AND status = 0 AND post_root_message_id IS NULL
RETURNING id
''');
      expect(updated.single.single, _post);
    });
    final requestChildEdit = await record(() => editTitle(_requestChild));
    const budProjections = {_bud, _post};
    final privateHierarchyHints = allOf(
      anyElement(containsPair('user_ids', contains(_carol))),
      everyElement(containsPair('user_ids', isNot(contains(_bob)))),
    );

    expect(
      {
        'bud publication hierarchy': hierarchyHints(publish, budProjections),
        'bud title edit hierarchy': hierarchyHints(edit, budProjections),
        'Post composer edit': _audience(hierarchyHints(postEdit, {_post})),
        'Request child title edit': _audience(
          hierarchyHints(requestChildEdit, {_requestChild}),
        ),
      },
      {
        'bud publication hierarchy': privateHierarchyHints,
        'bud title edit hierarchy': privateHierarchyHints,
        'Post composer edit': contains(_bob),
        'Request child title edit': containsAll([
          _requestAuthor,
          _requestMember,
        ]),
      },
    );
  });

  test(
    'unpublished bud updates send each entity hint only to its readers',
    () async {
      // A non-admitted participant still has a row but no content access.
      await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, room_access)
VALUES ('$_bud', '$_bob', 0)
''');
      expect(await canRead(_bud, _bob), isFalse);
      await insertMessage(_budRoomMessage);
      const poll = 'Pbudhintpoll1';
      await writer.execute('''
INSERT INTO public.polling (id, author_id, question)
VALUES ('$poll', '$_dave', 'Which day?')
''');
      await writer.execute('''
INSERT INTO public.beacon_room_message (beacon_id, author_id, linked_polling_id)
VALUES ('$_bud', '$_dave', '$poll')
''');

      const writes = {
        'beacon':
            "UPDATE public.beacon SET title = 'Garden plan' WHERE id = '$_bud'",
        'participant':
            '''
INSERT INTO public.beacon_participant (beacon_id, user_id, room_access)
VALUES ('$_bud', '$_carol', 0)
''',
        'help_offer':
            '''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message)
VALUES ('$_bud', '$_carol', 'I can bring tools.')
''',
        'forward':
            '''
UPDATE public.beacon_forward_edge SET note = 'Bring any tools you can.'
WHERE beacon_id = '$_bud' AND recipient_id = '$_carol'
''',
        'coordination_item':
            '''
INSERT INTO public.coordination_item
  (id, beacon_id, kind, creator_id, title, published, published_at)
VALUES ('Cbudhintitem1', '$_bud', 2, '$_dave', 'Can you bring tools?', true, now())
''',
        'fact_card':
            '''
INSERT INTO public.beacon_fact_card (beacon_id, fact_text, visibility, pinned_by)
VALUES ('$_bud', 'The gate opens at noon.', 0, '$_dave')
''',
        'activity_event':
            '''
INSERT INTO public.beacon_activity_event (beacon_id, visibility, type, actor_id)
VALUES ('$_bud', 0, ${BeaconActivityEventTypeBits.planUpdated}, '$_dave')
''',
        'room_reaction':
            '''
INSERT INTO public.beacon_room_message_reaction (message_id, user_id, emoji)
VALUES ('$_budRoomMessage', '$_carol', '👍')
''',
        'room_poll':
            '''
UPDATE public.polling SET question = 'What time?' WHERE id = '$poll'
''',
      };

      final missing = <String>[];
      final unreadableRecipients = <String, Set<String>>{};
      for (final MapEntry(key: entity, value: sql) in writes.entries) {
        final messages = await record(() => writer.execute(sql));
        final recipients = _audience(
          messages.where(
            (message) => message['entity'] == entity && message['id'] == _bud,
          ),
        );
        if (recipients.isEmpty) missing.add(entity);
        final unreadable = {
          for (final recipient in recipients)
            if (recipient == _bob || !await canRead(_bud, recipient)) recipient,
        };
        if (unreadable.isNotEmpty) unreadableRecipients[entity] = unreadable;
      }

      expect(
        {
          'event kinds with no recipients': missing,
          'unreadable recipients by event kind': unreadableRecipients,
        },
        {
          'event kinds with no recipients': isEmpty,
          'unreadable recipients by event kind': isEmpty,
        },
      );
    },
  );

  test(
    'connected Post members receive only the bud hints they can read',
    () async {
      final env = target.databaseEnv;
      final logger = Logger('PrivateBudRealtimeAudienceTest');
      final notifications = await PgNotificationService.create(
        env,
        const PostgresNotificationConnector(),
      );
      addTearDown(notifications.dispose);
      final auth = AuthCase(
        MockUserRepositoryPort(),
        MockInvitationRepositoryPort(),
        env: env,
        logger: logger,
      );
      final controller = WebSocketController(
        env,
        logger,
        auth,
        UserPresenceCase(
          MockUserPresenceRepositoryPort(),
          env: env,
          logger: logger,
        ),
        MockVoteUserFriendshipLookupPort(),
        MockBeaconRoomCoParticipantLookupPort(),
        // Keep optional message paint from reordering the Chat marker.
        MockRoomMessageSnapshotLookupPort(),
        QaRealtimeSocketGate(),
        notifications,
      );
      addTearDown(controller.dispose);
      final app = Router().plus
        ..get(kPathWebSocketEndpoint, controller.handler);
      final server = await shelf_io.serve(
        app.call,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final url = 'ws://127.0.0.1:${server.port}$kPathWebSocketEndpoint';

      Future<StreamIterator<Map<String, dynamic>>> connect(String user) async {
        final socket = await WebSocket.connect(url).timeout(_frameTimeout);
        addTearDown(socket.close);
        final frames = StreamIterator(
          socket.map(
            (frame) => jsonDecode(frame as String) as Map<String, dynamic>,
          ),
        );
        addTearDown(frames.cancel);
        socket.add(
          jsonEncode({
            'type': 'auth',
            'intent': AuthRequestIntent.cnameSignIn,
            'token': auth.issueAccessToken(user).rawToken,
          }),
        );
        expect(await frames.moveNext().timeout(_frameTimeout), isTrue);
        expect(
          frames.current,
          allOf(
            containsPair('type', 'auth'),
            containsPair('result', 'success'),
          ),
        );
        return frames;
      }

      final bob = await connect(_bob);
      final carol = await connect(_carol);
      final carolDeliveries = <String, bool>{};
      final bobDeliveries = <String, List<Map<String, dynamic>>>{};
      for (final (action, write, expectedEntity) in [
        ('message', () => insertMessage(_budRoomMessage), 'room_message'),
        ('publication', publishBud, 'beacon_hierarchy'),
        ('title edit', () => editTitle(_bud), 'beacon_hierarchy'),
      ]) {
        await write();
        // Both sockets receive this ordinary Post message after the tested write.
        // Its ID delimits each batch without waiting on a fixed quiet period.
        final marker = 'Rbudhintmark${carolDeliveries.length}';
        await insertMessage(marker, room: _post, author: _ann);
        final [bobBatch, carolBatch] = await Future.wait([
          _readThroughMarker(bob, marker),
          _readThroughMarker(carol, marker),
        ]).timeout(_frameTimeout);
        bool matchesAction(Map<String, dynamic> payload) =>
            payload['entity'] == expectedEntity &&
            (expectedEntity == 'room_message'
                ? payload['id'] == _bud &&
                      payload['message_id'] == _budRoomMessage
                : payload['id'] == _bud || payload['id'] == _post);
        carolDeliveries[action] = carolBatch.any(matchesAction);
        bobDeliveries[action] = bobBatch
            .where(
              (payload) =>
                  payload['id'] == _bud ||
                  payload['message_id'] == _budRoomMessage ||
                  (expectedEntity == 'beacon_hierarchy' &&
                      matchesAction(payload)),
            )
            .toList();
      }

      expect(
        {
          'Carol receives each hint': carolDeliveries,
          'Bob receives bud-related hints': bobDeliveries,
        },
        {
          'Carol receives each hint': {
            'message': true,
            'publication': true,
            'title edit': true,
          },
          'Bob receives bud-related hints': {
            'message': isEmpty,
            'publication': isEmpty,
            'title edit': isEmpty,
          },
        },
      );
    },
  );
}

const _frameTimeout = Duration(seconds: 10);

Future<List<Map<String, dynamic>>> _readThroughMarker(
  StreamIterator<Map<String, dynamic>> frames,
  String messageId,
) async {
  final batch = <Map<String, dynamic>>[];
  while (await frames.moveNext()) {
    final frame = frames.current;
    if (frame['type'] != 'subscription' || frame['path'] != 'entity_changes') {
      continue;
    }
    final payload = frame['payload'] as Map<String, dynamic>;
    if (payload['entity'] == 'room_message' &&
        payload['message_id'] == messageId) {
      return batch;
    }
    batch.add(payload);
  }
  fail('WebSocket closed before receiving Post Chat marker $messageId');
}

Set<String> _audience(Iterable<Map<String, dynamic>> messages) => {
  for (final message in messages)
    ...(message['user_ids']! as List).cast<String>(),
};

Future<void> _invite(
  Connection writer,
  String beacon,
  String sender,
  String recipient,
) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@beacon, @sender, @recipient)
'''),
  parameters: {'beacon': beacon, 'sender': sender, 'recipient': recipient},
);

Future<void> _seed(Connection writer) async {
  for (final (index, user) in [
    _ann,
    _bob,
    _carol,
    _dave,
    _requestAuthor,
    _requestMember,
  ].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': user, 'key': pgTestPublicKey('bud-hint', index + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, is_discoverable, parent_beacon_id, published_at)
VALUES
  ('$_post', '$_ann', '', '', 1, false, NULL, now()),
  ('$_bud', '$_dave', 'Garden Request', '', 0, false, '$_post', NULL),
  ('$_request', '$_requestAuthor', 'Parent Request', '', 0, false, NULL, now()),
  ('$_requestChild', '$_requestAuthor', 'Child Request', '', 0, false, '$_request', now())
''');
  await _invite(writer, _post, _ann, _bob);
  await _invite(writer, _post, _ann, _carol);
  await _invite(writer, _bud, _dave, _carol);
  await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, room_access)
VALUES ('$_request', '$_requestMember', 3)
''');
}
