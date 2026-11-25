@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/controllers/websocket_controller.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import 'websocket_realtime_protocol_test.mocks.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_WS_CLIENT_FLOOR_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_ws_client_floor',
  );
  final skip = await pgSkipReason(target);

  setUpAll(() async {
    final database = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: database));
  });

  test(
    'an authenticated websocket announces the coordinated client floor',
    () async {
      final pong = await _receiveVersionPong(target.databaseEnv);
      expect(
        pong,
        allOf(
          containsPair('type', 'pong'),
          containsPair('min_client_version', '7.69.1'),
        ),
      );
    },
    skip: skip,
  );

  test(
    'the default websocket floor excludes the previous release and admits '
    'the current release',
    () async {
      expect(Platform.environment.containsKey('MIN_CLIENT_VERSION'), isFalse);
      final pong = await _receiveVersionPong(target.databaseEnv);
      expect(pong, containsPair('type', 'pong'));
      final floor = pong['min_client_version'] as String;
      expect(
        {
          for (final version in ['7.69.0', '7.69.1'])
            version: _meetsFloor(version, floor),
        },
        {'7.69.0': false, '7.69.1': true},
        reason: 'The authenticated server announced min_client_version $floor.',
      );
    },
    skip: skip,
  );
}

Future<Map<String, dynamic>> _receiveVersionPong(Env env) async {
  final logger = Logger('WebsocketClientVersionFloorTest');
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
    MockRoomMessageSnapshotLookupPort(),
    QaRealtimeSocketGate(),
    notifications,
  );
  addTearDown(controller.dispose);
  final app = Router().plus..get(kPathWebSocketEndpoint, controller.handler);
  final server = await shelf_io.serve(
    app.call,
    InternetAddress.loopbackIPv4,
    0,
  );
  addTearDown(() => server.close(force: true));

  const frameTimeout = Duration(seconds: 5);
  final socket = await WebSocket.connect(
    'ws://127.0.0.1:${server.port}$kPathWebSocketEndpoint',
  ).timeout(frameTimeout);
  addTearDown(socket.close);
  final frames = StreamIterator(
    socket.map((frame) => jsonDecode(frame as String)),
  );
  addTearDown(frames.cancel);
  socket.add(
    jsonEncode({
      'type': 'auth',
      'intent': AuthRequestIntent.cnameSignIn,
      'token': auth.issueAccessToken('Uaaaaaaaaaaaa').rawToken,
    }),
  );
  expect(await frames.moveNext().timeout(frameTimeout), isTrue);
  expect(
    frames.current,
    allOf(containsPair('type', 'auth'), containsPair('result', 'success')),
  );

  socket.add(jsonEncode({'type': 'ping'}));
  expect(await frames.moveNext().timeout(frameTimeout), isTrue);
  return frames.current as Map<String, dynamic>;
}

bool _meetsFloor(String version, String floor) {
  final clientParts = version.split('.').map(int.parse).toList();
  final floorParts = floor.split('.').map(int.parse).toList();
  for (var index = 0; index < clientParts.length; index++) {
    final comparison = clientParts[index].compareTo(floorParts[index]);
    if (comparison != 0) return comparison > 0;
  }
  return true;
}
