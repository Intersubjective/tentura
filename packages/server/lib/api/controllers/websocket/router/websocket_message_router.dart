import '../path_handler/websocket_path_room_typing.dart';
import '../path_handler/websocket_path_user_presence.dart';
import '../session/websocket_session_handler_base.dart';

base mixin WebsocketMessageRouter
    on
        WebsocketSessionHandlerBase,
        WebsocketPathUserPresence,
        WebsocketPathRoomTyping {
  Future<void> onMessage(
    WebSocketSession session,
    Map<String, dynamic> message,
  ) {
    final jwt = getJwtBySession(session);
    final payload = message['payload'];
    if (payload is Map<String, dynamic>) {
      return switch (message['path']) {
        'user_presence' => onUserPresence(jwt, payload),
        'room_typing' => onRoomTyping(jwt, payload),
        _ => throw UnsupportedError('Unsupported path'),
      };
    }
    throw const FormatException('Invalid payload');
  }
}
