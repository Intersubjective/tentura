import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/annotations.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart';
import 'package:tentura_server/api/controllers/websocket/router/websocket_router_base.dart';
import 'package:tentura_server/api/controllers/websocket/session/websocket_session_handler_base.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/port/beacon_room_co_participant_lookup_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/invite_accepted_notification_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import 'websocket_realtime_protocol_test.mocks.dart';

const _actorId = 'Uaaaaaaaaaaaa';
const _affectedId = 'Ubbbbbbbbbbbb';
const _unauthorizedId = 'Ucccccccccccc';
const _accountId = 'Udddddddddddd';
const _firstId = 'Ueeeeeeeeeeee';
const _secondId = 'Uffffffffffff';

@GenerateNiceMocks([
  MockSpec<UserRepositoryPort>(),
  MockSpec<InvitationRepositoryPort>(),
  MockSpec<InviteAcceptedNotificationPort>(),
  MockSpec<UserPresenceRepositoryPort>(),
  MockSpec<VoteUserFriendshipLookupPort>(),
  MockSpec<BeaconRoomCoParticipantLookupPort>(),
])
void main() {
  group('realtime websocket protocol', () {
    test('compatibility mode filters actor but preserves metadata', () async {
      final dependencies = _Dependencies();
      final handler = _EntityChangeHarness(
        Env(realtimeActorEchoEnabled: false),
        dependencies,
      );
      final actor = _RecordingSession();
      final affected = _RecordingSession();
      final unauthorized = _RecordingSession();
      await dependencies.authenticate(handler, actor, _actorId);
      await dependencies.authenticate(handler, affected, _affectedId);
      await dependencies.authenticate(handler, unauthorized, _unauthorizedId);
      actor.sent.clear();
      affected.sent.clear();
      unauthorized.sent.clear();

      handler.fanOutEntityChange({
        'entity': 'beacon',
        'id': 'beacon-1',
        'event': 'update',
        'actor_user_id': _actorId,
        'user_ids': [_actorId, _affectedId, _actorId],
      });

      expect(actor.sent, isEmpty);
      expect(affected.sent, hasLength(1));
      expect(unauthorized.sent, isEmpty);
      final message = jsonDecode(affected.sent.single! as String) as Map;
      expect(
        message['payload'],
        containsPair('actor_user_id', _actorId),
      );
    });

    test(
      'enabled actor echo reaches actor and other affected sessions',
      () async {
        final dependencies = _Dependencies();
        final handler = _EntityChangeHarness(
          Env(realtimeActorEchoEnabled: true),
          dependencies,
        );
        final actor = _RecordingSession();
        final affected = _RecordingSession();
        await dependencies.authenticate(handler, actor, _actorId);
        await dependencies.authenticate(handler, affected, _affectedId);
        actor.sent.clear();
        affected.sent.clear();

        handler.fanOutEntityChange({
          'entity': 'forward',
          'id': 'beacon-1',
          'event': 'insert',
          'actor_user_id': _actorId,
          'user_ids': [_actorId, _affectedId],
        });

        expect(actor.sent, hasLength(1));
        expect(affected.sent, hasLength(1));
      },
    );

    test('malformed payload is not delivered', () async {
      final dependencies = _Dependencies();
      final handler = _EntityChangeHarness(Env(), dependencies);
      final session = _RecordingSession();
      await dependencies.authenticate(handler, session, _affectedId);
      session.sent.clear();

      handler.fanOutEntityChange({
        'entity': 'beacon',
        'id': '',
        'event': 'upsert',
        'user_ids': [_affectedId],
      });

      expect(session.sent, isEmpty);
    });

    test('pong is unconditional for an authenticated session', () async {
      final dependencies = _Dependencies();
      final handler = _EntityChangeHarness(Env(), dependencies);
      final session = _RecordingSession();
      await dependencies.authenticate(handler, session, _accountId);
      session.sent.clear();

      await handler.onPing(session, const {'type': 'ping'});

      expect(session.sent, hasLength(1));
      expect(
        jsonDecode(session.sent.single! as String),
        containsPair('type', 'pong'),
      );
    });

    test(
      'PG recovery broadcasts one catch-up to authenticated sessions',
      () async {
        final connector = _FakePgNotificationConnector();
        final notificationService =
            await PgNotificationService.createForTesting(Env.test(), connector);
        final dependencies = _Dependencies();
        final router = WebsocketRouterBase(
          Env(),
          Logger('WebsocketRealtimeProtocolTest'),
          dependencies.authCase,
          dependencies.userPresenceCase,
          dependencies.friendshipLookup,
          dependencies.coParticipantLookup,
          notificationService,
        );
        addTearDown(() async {
          await router.dispose();
          await notificationService.dispose();
        });
        final first = _RecordingSession();
        final second = _RecordingSession();
        await dependencies.authenticate(router, first, _firstId);
        await dependencies.authenticate(router, second, _secondId);
        first.sent.clear();
        second.sent.clear();

        await connector.connections.single.failAndClose();
        await _waitUntil(() => first.sent.isNotEmpty && second.sent.isNotEmpty);

        expect(first.sent, hasLength(1));
        expect(second.sent, hasLength(1));
        final message = jsonDecode(first.sent.single! as String) as Map;
        expect(message['type'], 'control');
        expect(
          message['payload'],
          containsPair('reason', 'pg_listener_recovered'),
        );
      },
    );
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _Dependencies {
  _Dependencies() {
    final logger = Logger('WebsocketRealtimeProtocolTest');
    authCase = AuthCase(
      MockUserRepositoryPort(),
      MockInvitationRepositoryPort(),
      MockInviteAcceptedNotificationPort(),
      env: env,
      logger: logger,
    );
    userPresenceCase = UserPresenceCase(
      MockUserPresenceRepositoryPort(),
      env: env,
      logger: logger,
    );
  }

  final env = Env.test();
  late final AuthCase authCase;
  late final UserPresenceCase userPresenceCase;
  final friendshipLookup = MockVoteUserFriendshipLookupPort();
  final coParticipantLookup = MockBeaconRoomCoParticipantLookupPort();

  Future<void> authenticate(
    WebsocketSessionHandlerBase handler,
    WebSocketSession session,
    String userId,
  ) async {
    final token = authCase.issueAccessToken(userId).rawToken;
    await handler.onAuth(session, {
      'intent': AuthRequestIntent.cnameSignIn,
      'token': token,
    });
  }
}

final class _EntityChangeHarness extends WebsocketSessionHandlerBase
    with WebsocketPathEntityChanges {
  _EntityChangeHarness(Env env, _Dependencies dependencies)
    : super(
        env,
        Logger('EntityChangeHarness'),
        dependencies.authCase,
        dependencies.userPresenceCase,
        dependencies.friendshipLookup,
        dependencies.coParticipantLookup,
      );
}

final class _RecordingSession extends WebSocketSession {
  final sent = <Object?>[];

  @override
  void send(Object? data) => sent.add(data);
}

final class _FakePgNotificationConnector implements PgNotificationConnector {
  final connections = <_FakePgNotificationConnection>[];

  @override
  Future<PgNotificationConnection> open(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  }) async {
    final connection = _FakePgNotificationConnection();
    connections.add(connection);
    return connection;
  }
}

final class _FakePgNotificationConnection implements PgNotificationConnection {
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> channel(String name) => _controller.stream;

  Future<void> failAndClose() async {
    _controller.addError(StateError('connection lost'));
    await _controller.close();
  }

  @override
  Future<void> listen(String channel) async {}

  @override
  Future<void> notify(String channel, String payload) async {}

  @override
  Future<void> close() async {}
}
