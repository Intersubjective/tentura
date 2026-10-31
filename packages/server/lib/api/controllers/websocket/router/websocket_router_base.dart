import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:tentura_server/data/service/pg_notification_service.dart';

import '../path_handler/websocket_path_entity_changes.dart';
import '../path_handler/websocket_path_room_typing.dart';
import '../path_handler/websocket_path_user_presence.dart';
import 'websocket_message_router.dart';
import '../session/websocket_session_handler_base.dart';
import 'websocket_subscription_router.dart';

base class WebsocketRouterBase extends WebsocketSessionHandlerBase
    with
        WebsocketPathUserPresence,
        WebsocketPathEntityChanges,
        WebsocketPathRoomTyping,
        WebsocketMessageRouter,
        WebsocketSubscriptionRouter {
  WebsocketRouterBase(
    super.env,
    super.logger,
    super.authCase,
    super.userPresenceCase,
    super.friendshipLookup,
    super.coParticipantLookup,
    super.roomMessageSnapshotLookup,
    super.qaRealtimeSocketGate,
    this.pgNotificationService, {
    super.presenceOfflineGrace,
  }) {
    _entityChangeSubscription = pgNotificationService.entityChangeNotifications
        .listen(
          _onEntityChangeNotification,
          onError: (Object e) => logger.severe(
            '[WebsocketRouterBase] PG entity_changes error: $e',
          ),
        );
    _presenceSubscription = pgNotificationService.presenceNotifications.listen(
      _onPresenceNotification,
      onError: (Object e) => logger.severe(
        '[WebsocketRouterBase] PG user_presence error: $e',
      ),
    );
    _roomTypingSubscription = pgNotificationService.roomTypingNotifications
        .listen(
          _onRoomTypingNotification,
          onError: (Object e) => logger.severe(
            '[WebsocketRouterBase] PG room_typing error: $e',
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
  late final StreamSubscription<String> _presenceSubscription;
  late final StreamSubscription<String> _roomTypingSubscription;
  late final StreamSubscription<PgNotificationRecovery> _recoverySubscription;

  Future<void> dispose() async {
    cancelPendingPresenceWrites();
    disposeEntityChanges();
    disposeRoomTyping();
    await _entityChangeSubscription.cancel();
    await _presenceSubscription.cancel();
    await _roomTypingSubscription.cancel();
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
    // Presence NOTIFYs sent while this worker was not listening are lost:
    // send watchers the stored status again.
    for (final userId in locallyRelevantPresenceUserIds) {
      unawaited(_fanOutPresenceQuietly(userId));
    }
    logger.info(
      '[RealtimeRecovery] realtime_event=listener_recovered '
      'sequence=${recovery.sequence} sessions=${sessions.length} '
      'isolate=${Isolate.current.debugName ?? 'unnamed'}',
    );
  }

  /// Carries the change to every web worker, this one included: a watcher's
  /// socket may live on another isolate than the watched user's (#533).
  /// Without a NOTIFY connection, at least this worker's watchers hear it.
  @override
  Future<void> broadcastPresenceForUser(String userId) async {
    try {
      await pgNotificationService.notify(
        PgNotificationService.presenceChannel,
        jsonEncode({'user_id': userId}),
      );
    } on Object catch (e) {
      logger.warning(
        '[WebsocketRouterBase] presence NOTIFY failed, local fan-out only: $e',
      );
      await fanOutPresenceLocally(userId);
    }
  }

  @override
  Future<void> announcePresenceLeaving(String userId) async {
    try {
      await pgNotificationService.notify(
        PgNotificationService.presenceChannel,
        jsonEncode({'user_id': userId, 'leaving': true}),
      );
    } on Object catch (e) {
      logger.warning(
        '[WebsocketRouterBase] presence leaving NOTIFY failed: $e',
      );
    }
  }

  /// Carries the typing change to every web worker, this one included. Without
  /// a NOTIFY connection, at least this worker's members hear it.
  @override
  Future<void> announceRoomTyping(
    String beaconId,
    String userId, {
    required bool typing,
  }) async {
    try {
      await pgNotificationService.notify(
        PgNotificationService.roomTypingChannel,
        jsonEncode({
          'beacon_id': beaconId,
          'user_id': userId,
          'typing': typing,
        }),
      );
    } on Object catch (e) {
      logger.warning(
        '[WebsocketRouterBase] room typing NOTIFY failed, local fan-out only: '
        '$e',
      );
      await fanOutRoomTyping(beaconId, userId, typing: typing);
    }
  }

  void _onRoomTypingNotification(String payload) {
    unawaited(() async {
      try {
        final data = jsonDecode(payload);
        if (data is! Map<String, dynamic>) return;
        final beaconId = data['beacon_id'];
        final userId = data['user_id'];
        final typing = data['typing'];
        if (beaconId is! String ||
            beaconId.isEmpty ||
            userId is! String ||
            userId.isEmpty ||
            typing is! bool) {
          return;
        }
        await fanOutRoomTyping(beaconId, userId, typing: typing);
      } catch (e) {
        logger.warning(
          '[WebsocketRouterBase] room typing notification failed: $e',
        );
      }
    }());
  }

  Future<void> _fanOutPresenceQuietly(String userId) async {
    try {
      await fanOutPresenceLocally(userId);
    } on Object catch (e) {
      logger.warning('[WebsocketRouterBase] presence fan-out failed: $e');
    }
  }

  void _onPresenceNotification(String payload) {
    unawaited(() async {
      try {
        final data = jsonDecode(payload);
        if (data is! Map<String, dynamic>) return;
        final userId = data['user_id'];
        if (userId is! String || userId.isEmpty) return;
        if (data['leaving'] == true) {
          await claimPresenceIfLocal(userId);
        } else {
          await fanOutPresenceLocally(userId);
        }
      } catch (e) {
        logger.warning(
          '[WebsocketRouterBase] presence notification failed: $e',
        );
      }
    }());
  }

  void _onEntityChangeNotification(String payload) {
    unawaited(() async {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        await fanOutEntityChange(data);
      } catch (e) {
        logger.severe(
          '[RealtimeFanout] realtime_event=payload_failure error=$e',
        );
      }
    }());
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
