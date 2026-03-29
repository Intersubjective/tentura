import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_root/domain/enums.dart';

import 'websocket/router/websocket_router_base.dart';

@Singleton(order: 3)
final class WebSocketController extends WebsocketRouterBase {
  WebSocketController(
    super.env,
    super.logger,
    super.authCase,
    super.userPresenceCase,
    super.p2pChatCase,
    super.pgNotificationService,
  );

  WebSocketSession handler() => WebSocketSession(
    onClose: (session) {
      unawaited(() async {
        final jwt = removeSession(session);
        if (jwt != null) {
          await userPresenceCase.setStatus(
            userId: jwt.sub,
            status: UserPresenceStatus.offline,
          );
          await broadcastPresenceForUser(jwt.sub);
        }
      }());
    },
    onError: (session, error) async {
      final err = 'Error occurred [$error]';
      print(err);
      await session.sender.close(1000, err);
    },
    onMessage: (session, data) => switch (data) {
      final String message => onTextMessage(session, message),
      final List<int> message => onBinaryMessage(session, message),
      _ => throw UnsupportedError('Unsupported payload type'),
    },
  );

  @disposeMethod
  @override
  Future<void> dispose() => super.dispose();
}
