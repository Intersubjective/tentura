import 'dart:async';
import 'dart:convert';

import 'package:tentura_server/domain/use_case/p2p_chat_case.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';

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
    this.pgNotificationService,
  ) {
    _notificationSubscription = pgNotificationService.notifications.listen(
      _onPgNotification,
      onError: (Object e) => logger.severe(
        '[WebsocketRouterBase] PG notification error: $e',
      ),
    );
  }

  @override
  final P2pChatCase p2pChatCase;

  final PgNotificationService pgNotificationService;

  late final StreamSubscription<String> _notificationSubscription;

  Future<void> dispose() async {
    await _notificationSubscription.cancel();
  }

  void _onPgNotification(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final event = data['event'] as String?;
      switch (event) {
        case 'new_message':
          _fanOutNewMessage(data);
        case 'delivered':
          _fanOutDeliveryReceipt(data);
        default:
          logger.warning(
            '[WebsocketRouterBase] Unknown pg notification event: $event',
          );
      }
    } catch (e) {
      logger.severe('[WebsocketRouterBase] Failed to handle notification: $e');
    }
  }

  void _fanOutNewMessage(Map<String, dynamic> data) {
    final receiverId = data['receiver_id'] as String?;
    final senderId = data['sender_id'] as String?;
    if (receiverId == null || senderId == null) return;

    final messageJson = jsonEncode({
      'type': 'subscription',
      'path': 'p2p_chat',
      'payload': {
        'intent': 'watch_updates',
        'messages': [data..remove('event')],
      },
    });

    for (final session in getSessionsByUserId(receiverId)) {
      session.send(messageJson);
    }
    for (final session in getSessionsByUserId(senderId)) {
      session.send(messageJson);
    }
  }

  void _fanOutDeliveryReceipt(Map<String, dynamic> data) {
    final senderId = data['sender_id'] as String?;
    final receiverId = data['receiver_id'] as String?;
    if (senderId == null || receiverId == null) return;

    final receiptJson = jsonEncode({
      'type': 'subscription',
      'path': 'p2p_chat',
      'payload': {
        'intent': 'watch_updates',
        'messages': [data..remove('event')],
      },
    });

    for (final session in getSessionsByUserId(senderId)) {
      session.send(receiptJson);
    }
    for (final session in getSessionsByUserId(receiverId)) {
      session.send(receiptJson);
    }
  }

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
