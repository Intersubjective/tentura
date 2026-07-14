import '../path_handler/websocket_path_user_presence.dart';
import '../session/websocket_session_handler_base.dart';

base mixin WebsocketSubscriptionRouter
    on WebsocketSessionHandlerBase, WebsocketPathUserPresence {
  Future<void> onSubscription(
    WebSocketSession session,
    Map<String, dynamic> message,
  ) {
    final payload = message['payload'];
    if (payload is Map<String, dynamic>) {
      return switch (message['path']) {
        'user_presence' => onUserPresenceSubscription(session, payload),
        _ => throw UnsupportedError('Unsupported path'),
      };
    }
    throw const FormatException('Invalid payload');
  }
}
