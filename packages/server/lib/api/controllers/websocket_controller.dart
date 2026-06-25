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
    super.friendshipLookup,
    super.coParticipantLookup,
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
      logger.warning('WebSocket error', error);
      // Clean up session state and mark the user offline here too: closing the
      // sender normally triggers onClose, but that is not guaranteed on every
      // error path, so do not rely on it for cleanup. removeSession is
      // idempotent, so a subsequent onClose is a harmless no-op.
      final jwt = removeSession(session);
      if (jwt != null && !hasSessionsForUser(jwt.sub)) {
        await userPresenceCase.setStatus(
          userId: jwt.sub,
          status: UserPresenceStatus.offline,
        );
        await broadcastPresenceForUser(jwt.sub);
      }
      await session.sender.close(1011, 'Internal error');
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
