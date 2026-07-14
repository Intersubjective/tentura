import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:tentura_server/data/service/pg_notification_service.dart';

import '../path_handler/websocket_path_entity_changes.dart';
import '../path_handler/websocket_path_user_presence.dart';
import 'websocket_message_router.dart';
import '../session/websocket_session_handler_base.dart';
import 'websocket_subscription_router.dart';

base class WebsocketRouterBase extends WebsocketSessionHandlerBase
    with
        WebsocketPathUserPresence,
        WebsocketPathEntityChanges,
        WebsocketMessageRouter,
        WebsocketSubscriptionRouter {
  WebsocketRouterBase(
    super.env,
    super.logger,
    super.authCase,
    super.userPresenceCase,
    super.friendshipLookup,
    super.coParticipantLookup,
    super.realtimeWatchGrantCase,
    super.qaRealtimeSocketGate,
    this.pgNotificationService,
  ) {
    _entityChangeSubscription = pgNotificationService.entityChangeNotifications
        .listen(
          _onEntityChangeNotification,
          onError: (Object e) => logger.severe(
            '[WebsocketRouterBase] PG entity_changes error: $e',
          ),
        );
    _recoverySubscription = pgNotificationService.recoveryNotifications.listen(
      _onPgListenerRecovery,
      onError: (Object e) => logger.severe(
        '[WebsocketRouterBase] PG recovery stream error: $e',
      ),
    );
  }

  final PgNotificationService pgNotificationService;

  late final StreamSubscription<String> _entityChangeSubscription;
  late final StreamSubscription<PgNotificationRecovery> _recoverySubscription;

  Future<void> dispose() async {
    await _entityChangeSubscription.cancel();
    await _recoverySubscription.cancel();
  }

  void _onPgListenerRecovery(PgNotificationRecovery recovery) {
    final sessions = authenticatedSessions;
    final message = jsonEncode({
      'type': 'control',
      'path': 'entity_changes',
      'payload': {
        'intent': 'catch_up',
        'reason': 'pg_listener_recovered',
      },
    });
    for (final session in sessions) {
      session.send(message);
    }
    logger.info(
      '[RealtimeRecovery] realtime_event=listener_recovered '
      'sequence=${recovery.sequence} sessions=${sessions.length} '
      'isolate=${Isolate.current.debugName ?? 'unnamed'}',
    );
  }

  void _onEntityChangeNotification(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      fanOutEntityChange(data);
    } catch (e) {
      logger.severe(
        '[RealtimeFanout] realtime_event=payload_failure error=$e',
      );
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
    // Binary frames are not part of the protocol. Ignore them gracefully
    // instead of throwing (an unguarded throw here escapes the message
    // handler, since the controller's onMessage has no try/catch around it).
    logger.warning(
      '[WebsocketRouterBase] Ignoring unsupported binary frame '
      '(${binaryMessage.length} bytes)',
    );
    session.send(jsonEncode({'error': 'binary frames are not supported'}));
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
