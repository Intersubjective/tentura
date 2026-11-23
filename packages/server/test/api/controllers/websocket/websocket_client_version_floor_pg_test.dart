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
      final env = target.databaseEnv;
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
      final app = Router().plus
        ..get(kPathWebSocketEndpoint, controller.handler);
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
      expect(
        frames.current,
        allOf(
          containsPair('type', 'pong'),
          containsPair('min_client_version', '7.65.0'),
        ),
      );
    },
    skip: skip,
  );
}
