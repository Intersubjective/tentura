@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_attention.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field_requests.dart';
import 'package:tentura_server/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart';
import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/controllers/websocket/session/websocket_session_handler_base.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_requests_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/domain/use_case/constellation_field_requests_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart';

// These fixture accounts also authenticate over the production JWT path.
const _reader = 'U0ead00000001';
const _author = 'Ua07000000001';
const _seated = 'Uopenseated01';
const _request = 'Bopenread01';

// Real GraphQL resolvers and PostgreSQL policies cover opening, both Field
// projections, peer receipts and subsequent admission. A seated reader is the
// control: opening preserves their room cursor, while reading moves it.
// Input, locale and viewport are n/a for this server-only contract.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_OPEN_ROOM_READ_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_open_room_read',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late Connection listener;
  late StreamSubscription<String> subscription;
  late MutationAttention opening;
  late QueryConstellationField full;
  late QueryConstellationFieldRequests targeted;
  late BeaconRoomRepository room;
  final notifications = <Map<String, dynamic>>[];
  final env = Env(environment: Environment.test);
  final logger = Logger('RequestOpenRoomReadIsolationPgTest');
  var barrier = 0;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    room = BeaconRoomRepository(db);
    opening = MutationAttention(ack: AttentionAckRepository(db));
    full = QueryConstellationField(
      constellationFieldCase: ConstellationFieldCase(
        ConstellationFieldRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
        ),
        env: env,
        logger: logger,
      ),
    );
    targeted = QueryConstellationFieldRequests(
      case_: ConstellationFieldRequestsCase(
        ConstellationFieldRequestsRepository(db),
        env: env,
        logger: logger,
      ),
    );
    listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    subscription = listener.channels['entity_changes'].listen(
      (payload) => notifications.add(
        jsonDecode(payload) as Map<String, dynamic>,
      ),
    );
    await listener.execute('LISTEN entity_changes');
  });

  tearDownAll(() async {
    await subscription.cancel();
    await listener.close();
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  // A committed NOTIFY after the action is a delivery barrier for prior
  // notifications, so absence assertions do not depend on a guessed sleep.
  Future<void> drainNotifications() async {
    final token = ++barrier;
    await session.writer.execute(
      Sql.named("SELECT pg_notify('entity_changes', @payload)"),
      parameters: {
        'payload': jsonEncode({'test_barrier': token}),
      },
    );
    final deadline = DateTime.timestamp().add(const Duration(seconds: 3));
    while (!notifications.any((event) => event['test_barrier'] == token)) {
      if (DateTime.timestamp().isAfter(deadline)) {
        fail('The notification listener did not receive its delivery barrier');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> admit(String userId) => room.inviteOfferUserToBeaconRoom(
    beaconId: _request,
    offerUserId: userId,
    authorUserId: _author,
  );

  Future<void> open(String userId) async {
    expect(
      await opening.attentionMarkSeenForBeacon.resolve!(null, {
        kGlobalInputQueryJwt: JwtEntity(sub: userId),
        'beaconId': _request,
      }),
      0,
      reason: 'Opening without attention receipts still records the Field open',
    );
  }

  Future<bool> fieldUnread({required bool refresh}) async {
    final args = {
      kGlobalInputQueryJwt: const JwtEntity(sub: _reader),
      'showClosed': false,
      'participatedOnly': false,
    };
    final List<dynamic> rows;
    if (refresh) {
      rows =
          await targeted.constellationFieldRequests.resolve!(null, {
                ...args,
                'ids': [_request],
              })
              as List;
    } else {
      final result =
          await full.constellationField.resolve!(null, {
                ...args,
                'projection': 'FULL',
              })
              as Map<String, dynamic>;
      rows = result['requests'] as List;
    }
    expect(rows.map((row) => (row as Map)['id']), contains(_request));
    final request = rows.cast<Map<String, dynamic>>().singleWhere(
      (row) => row['id'] == _request,
    );
    expect(request['has_unread'], isA<bool>());
    return request['has_unread']! as bool;
  }

  Future<void> expectFieldUnread({
    required bool unread,
    required bool refresh,
  }) async {
    expect(await fieldUnread(refresh: refresh), unread);
  }

  Future<void> message(String body, DateTime at) async {
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (beacon_id, author_id, body, created_at)
VALUES (@beacon, @author, @body, @at)
'''),
      parameters: {
        'beacon': _request,
        'author': _author,
        'body': body,
        'at': at,
      },
    );
  }

  setUp(() async {
    await session.writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_reader, _author, _seated].indexed) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('open-room-read', index + 1),
        },
      );
    }
    await session.writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, is_discoverable, published_at)
VALUES ('$_request', '$_author', 'Discussion plans', '', 0, 0, true, now())
''');
    await session.writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$_request', '$_author', '$_reader')
''');
    await session.writer.execute('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$_reader', '$_author', 1), ('$_author', '$_reader', 1)
''');
    final access = await session.writer.execute('''
SELECT public.beacon_can_read_content('$_request', '$_reader'),
       public.beacon_effective_admission('$_request', '$_reader')
''');
    expect(access.single, [true, false]);
    await drainNotifications();
    notifications.clear();
  });

  group('Request opening keeps Field state separate from discussion reads', () {
    test(
      'unseated opening sends a private Field unread invalidation to both reader sessions',
      () async {
        final auth = AuthCase(
          MockUserRepositoryPort(),
          MockInvitationRepositoryPort(),
          env: Env.test(),
          logger: logger,
        );
        final presence = UserPresenceCase(
          MockUserPresenceRepositoryPort(),
          env: Env.test(),
          logger: logger,
        );
        final connections = [
          for (final actorEcho in [true, false])
            (
              handler: _FieldInvalidationHandler(
                actorEcho: actorEcho,
                auth: auth,
                presence: presence,
                logger: logger,
              ),
              first: _RecordingFieldSession(),
              second: _RecordingFieldSession(),
              unrelated: _RecordingFieldSession(),
            ),
        ];
        for (final sockets in connections) {
          addTearDown(() {
            sockets.handler.disposeEntityChanges();
            [
              sockets.first,
              sockets.second,
              sockets.unrelated,
            ].forEach(sockets.handler.removeSession);
          });
          for (final (socket, accountId) in [
            (sockets.first, _reader),
            (sockets.second, _reader),
            (sockets.unrelated, _author),
          ]) {
            // Sign and validate real JWTs through the production auth handler.
            await sockets.handler.onAuth(socket, {
              'intent': AuthRequestIntent.cnameSignIn,
              'token': auth.issueAccessToken(accountId).rawToken,
            });
          }
          expect(
            sockets.handler.getSessionsByUserId(_reader),
            unorderedEquals([sockets.first, sockets.second]),
          );
          expect(
            sockets.handler.getSessionsByUserId(_author),
            unorderedEquals([sockets.unrelated]),
          );
          for (final socket in [
            sockets.first,
            sockets.second,
            sockets.unrelated,
          ]) {
            socket.sent.clear();
          }
        }
        await expectFieldUnread(unread: true, refresh: false);
        await expectFieldUnread(unread: true, refresh: true);
        expect(
          await session.writer.execute('''
SELECT user_id, beacon_id FROM public.beacon_field_seen
WHERE user_id = '$_reader' AND beacon_id = '$_request'
'''),
          isEmpty,
        );
        // Exclude hints from fixture setup and the precondition Field reads.
        await drainNotifications();
        notifications.clear();

        await open(_reader);
        await drainNotifications();
        final openNotifications = List<Map<String, dynamic>>.of(notifications);
        final opened = await session.writer.execute('''
SELECT user_id, beacon_id FROM public.beacon_field_seen
WHERE user_id = '$_reader' AND beacon_id = '$_request'
''');
        expect(opened, hasLength(1));
        expect(opened.single, [_reader, _request]);

        await expectFieldUnread(unread: false, refresh: false);
        await expectFieldUnread(unread: false, refresh: true);
        final watermarks = await session.writer.execute('''
SELECT last_seen_at FROM public.beacon_room_seen
WHERE user_id = '$_reader' AND beacon_id = '$_request'
''');
        expect(watermarks, isEmpty);
        expect(
          openNotifications.where(
            (event) => event['entity'] == 'room_seen_peer',
          ),
          isEmpty,
        );

        // Opening changes this account's Field projection, not its discussion
        // cursor. Use the existing account-scoped Field invalidation contract.
        final hints = openNotifications
            .where((event) => event['entity'] == 'constellation_field')
            .toList();
        expect(
          hints,
          [
            allOf(
              containsPair('entity', 'constellation_field'),
              containsPair('event', 'update'),
              containsPair('id', 'global'),
              containsPair('user_ids', [_reader]),
            ),
          ],
          reason:
              "The new Field-open row must invalidate only its reader's Field",
        );
        for (final hint in hints) {
          expect(hint['user_ids'], [_reader]);
          for (final sockets in connections) {
            // Pass the real committed NOTIFY to the production mixin. Only
            // the socket transport is recorded; auth and dispatch are real.
            await sockets.handler.fanOutEntityChange(Map.of(hint));
            for (final socket in [sockets.first, sockets.second]) {
              expect(socket.sent, hasLength(1));
              final frame = socket.sent.single;
              expect(frame['type'], 'subscription');
              expect(frame['path'], 'entity_changes');
              final payload = frame['payload'] as Map<String, dynamic>;
              expect(payload['entity'], 'constellation_field');
              expect(payload['event'], 'update');
              expect(payload['id'], 'global');
            }
            expect(
              sockets.unrelated.sent,
              isEmpty,
              reason:
                  "The Request author must not receive the reader's private invalidation",
            );
          }
        }
      },
    );

    for (final refresh in [false, true]) {
      test(
        '${refresh ? 'targeted' : 'full'} Field clears unread on repeated unseated opens without creating a room watermark',
        () async {
          await expectFieldUnread(unread: true, refresh: refresh);
          await open(_reader);
          await expectFieldUnread(unread: false, refresh: refresh);
          await open(_reader);
          await expectFieldUnread(unread: false, refresh: refresh);

          final watermarks = await session.writer.execute('''
SELECT last_seen_at FROM public.beacon_room_seen
WHERE user_id = '$_reader' AND beacon_id = '$_request'
''');
          expect(
            watermarks,
            isEmpty,
            reason: 'Opening a Request without a room seat is not a room read',
          );
        },
      );
    }

    test(
      'an existing discussion watermark stays unchanged while an unseated open clears Field unread',
      () async {
        final readAt = DateTime.utc(2020, 1, 2);
        // Seed only a historical discussion read, with no Request-open action.
        // Its presence must not stand in for the independent Field-open fact.
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_seen
  (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES (@reader, @request, NULL, @at)
'''),
          parameters: {'reader': _reader, 'request': _request, 'at': readAt},
        );
        final unreadBeforeOpen = [
          await fieldUnread(refresh: false),
          await fieldUnread(refresh: true),
        ];
        await drainNotifications();
        notifications.clear();

        await open(_reader);
        await drainNotifications();
        expect(
          await room.getMainRoomLastSeen(beaconId: _request, userId: _reader),
          readAt,
          reason: 'An unseated open must preserve the historical room cursor',
        );
        expect(
          notifications.where(
            (event) =>
                event['entity'] == 'room_seen_peer' && event['id'] == _request,
          ),
          isEmpty,
          reason: 'Opening must not re-emit the historical room read receipt',
        );
        await expectFieldUnread(unread: false, refresh: false);
        await expectFieldUnread(unread: false, refresh: true);
        expect(
          unreadBeforeOpen,
          [true, true],
          reason:
              'A room watermark alone must not clear Field unread before opening',
        );
      },
    );

    test(
      'unseated opening emits no peer read receipt while seated room reads still notify peers',
      () async {
        await admit(_seated);
        expect(
          await room.getMainRoomLastSeen(beaconId: _request, userId: _seated),
          isNull,
        );
        await drainNotifications();
        notifications.clear();
        await open(_seated);
        await drainNotifications();
        final seatedWatermarks = await session.writer.execute('''
SELECT last_seen_at FROM public.beacon_room_seen
WHERE user_id = '$_seated' AND beacon_id = '$_request'
''');
        expect(
          seatedWatermarks,
          isEmpty,
          reason: 'Opening without a cursor must not create a seated room read',
        );
        expect(
          notifications.where(
            (event) =>
                event['entity'] == 'room_seen_peer' && event['id'] == _request,
          ),
          isEmpty,
          reason: 'A seated open without a cursor must not emit a read receipt',
        );
        notifications.clear();
        final readAt = DateTime.utc(2020, 1, 2);
        await message('An already read discussion message', DateTime.utc(2020));
        await room.markBeaconRoomSeen(
          userId: _seated,
          beaconId: _request,
          threadItemId: null,
          at: readAt,
        );
        await drainNotifications();
        expect(
          notifications.where(
            (event) =>
                event['entity'] == 'room_seen_peer' &&
                event['id'] == _request &&
                event['seen_user_id'] == _seated,
          ),
          isNotEmpty,
          reason: 'The real listener observes legitimate seated read receipts',
        );
        notifications.clear();

        expect(
          (await room.unreadRoomSummaries(
            [_request],
            viewerUserId: _seated,
          ))[_request]?.discussion,
          0,
        );
        await message('An unread discussion message', DateTime.utc(2020, 1, 3));
        await drainNotifications();
        notifications.clear();
        await open(_seated);
        await drainNotifications();
        final seatedOpenPeerReceipts = notifications
            .where(
              (event) =>
                  event['entity'] == 'room_seen_peer' &&
                  event['id'] == _request,
            )
            .toList();
        expect(
          seatedOpenPeerReceipts,
          isEmpty,
          reason:
              'Opening as a seated reader must not emit a peer read receipt',
        );
        expect(
          await room.getMainRoomLastSeen(beaconId: _request, userId: _seated),
          readAt,
          reason: "Opening preserves a seated reader's existing room cursor",
        );
        expect(
          (await room.unreadRoomSummaries(
            [_request],
            viewerUserId: _seated,
          ))[_request]?.discussion,
          1,
          reason:
              "Opening a seated reader's Request does not read new messages",
        );
        await drainNotifications();
        notifications.clear();
        await open(_reader);
        await drainNotifications();
        expect(
          notifications.where(
            (event) =>
                event['entity'] == 'room_seen_peer' && event['id'] == _request,
          ),
          isEmpty,
          reason:
              'Opening as an unseated reader must not emit a peer read receipt',
        );
      },
    );

    test(
      'later admission leaves discussion messages from before an unseated open unread',
      () async {
        await message('Choose a meeting point', DateTime.utc(2020));
        await message('Bring the supplies', DateTime.utc(2020, 1, 3));
        await expectFieldUnread(unread: true, refresh: true);
        await open(_reader);
        await expectFieldUnread(unread: false, refresh: true);
        await admit(_reader);

        final access = await session.writer.execute('''
SELECT public.beacon_effective_admission('$_request', '$_reader')
''');
        expect(access.single.single, isTrue);
        final summaries = await room.unreadRoomSummaries(
          [_request],
          viewerUserId: _reader,
        );
        expect(
          summaries[_request]?.discussion,
          2,
          reason: 'Opening before admission did not read either old message',
        );
        expect(summaries[_request]?.oldestRoom, 'discussion');
        final counts = await room.unreadMainRoomMessageCounts(
          [_request],
          viewerUserId: _reader,
        );
        expect(counts[_request], 2);
        final facts = await room.roomViewerFacts(
          [_request],
          viewerUserId: _reader,
        );
        expect(facts[_request]?.lastSeenAt, isNull);
        await expectFieldUnread(unread: true, refresh: false);
        await expectFieldUnread(unread: true, refresh: true);

        // Only an actual seated room read acknowledges those old messages.
        await room.markBeaconRoomSeen(
          userId: _reader,
          beaconId: _request,
          threadItemId: null,
          at: DateTime.utc(2020, 1, 4),
        );
        expect(
          (await room.unreadRoomSummaries(
            [_request],
            viewerUserId: _reader,
          ))[_request]?.discussion,
          0,
        );
        await expectFieldUnread(unread: false, refresh: true);
      },
    );
  });
}

// The production authentication registry and fan-out mixin run unchanged;
// unrelated database lookups use this suite's existing websocket port mocks.
final class _FieldInvalidationHandler extends WebsocketSessionHandlerBase
    with WebsocketPathEntityChanges {
  _FieldInvalidationHandler({
    required bool actorEcho,
    required AuthCase auth,
    required UserPresenceCase presence,
    required Logger logger,
  }) : super(
         Env(realtimeActorEchoEnabled: actorEcho),
         logger,
         auth,
         presence,
         MockVoteUserFriendshipLookupPort(),
         MockBeaconRoomCoParticipantLookupPort(),
         MockRoomMessageSnapshotLookupPort(),
         QaRealtimeSocketGate(),
       );
}

final class _RecordingFieldSession extends WebSocketSession {
  final sent = <Map<String, dynamic>>[];

  @override
  void send(Object? data) =>
      sent.add(jsonDecode(data! as String) as Map<String, dynamic>);
}
