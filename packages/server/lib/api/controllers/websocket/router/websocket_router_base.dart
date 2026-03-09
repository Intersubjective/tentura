import 'dart:async';
import 'dart:convert';

import 'package:tentura_server/domain/use_case/p2p_chat_case.dart';

import '../path_handler/websocket_path_p2p_chat.dart';
import '../path_handler/websocket_path_user_presence.dart';
import 'websocket_message_router.dart';
import '../session/websocket_session_handler_base.dart';
import 'websocket_subscription_router.dart';

base class WebsocketRouterBase extends WebsocketSessionHandlerBase
    with
        WebsocketPathP2pChat,
        WebsocketPathUserPresence,
        WebsocketMessageRouter,
        WebsocketSubscriptionRouter {
  WebsocketRouterBase(
    super.env,
    super.logger,
    super.authCase,
    super.userPresenceCase,
    this.p2pChatCase,
  );

  @override
  final P2pChatCase p2pChatCase;

  ///
  /// Process text message
  ///
  Future<void> onTextMessage(
    WebSocketSession session,
    String textMessage,
  ) async {
    try {
      final message = jsonDecode(textMessage);
      if (message is! Map<String, dynamic>) {
        throw FormatException('Wrong message [${message.runtimeType}]');
      }
      final type = message['type'];
      if (type is! String) {
        throw FormatException('Wrong type [${type.runtimeType}]');
      }
      await _dispatchMessage(type, session, message);
    } catch (e) {
      session.send(jsonEncode({'error': e.toString()}));
    }
  }

  ///
  /// Process binary message (CBOR?)
  ///
  Future<void> onBinaryMessage(
    WebSocketSession session,
    List<int> binaryMessage,
  ) async {
    throw UnimplementedError();
  }

  Future<void> _dispatchMessage(
    String messageType,
    WebSocketSession session,
    Map<String, dynamic> message,
  ) => switch (messageType) {
    'ping' => onPing(session, message),
    'auth' => onAuth(session, message),
    'message' => onMessage(session, message),
    'subscription' => onSubscription(session, message),
    _ => throw UnsupportedError('Unsupported message type'),
  };
}
