import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:shelf_plus/shelf_plus.dart';

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
    super.roomMessageSnapshotLookup,
    super.qaRealtimeSocketGate,
    super.pgNotificationService, {
    @ignoreParam super.presenceOfflineGrace,
  });

  WebSocketSession handler() => WebSocketSession(
    // Another tab of the same user may still be open on this worker; then
    // they stay online (#533).
    onClose: (session) => unawaited(onSessionGone(session)),
    onError: (session, error) async {
      logger.warning('WebSocket error', error);
      // Clean up session state and mark the user offline here too: closing the
      // sender normally triggers onClose, but that is not guaranteed on every
      // error path, so do not rely on it for cleanup. removeSession is
      // idempotent, so a subsequent onClose is a harmless no-op.
      await onSessionGone(session);
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
