import 'dart:convert';

import '../session/websocket_session_handler_base.dart';

/// Fans out validated Postgres invalidation hints to isolate-local sessions.
base mixin WebsocketPathEntityChanges on WebsocketSessionHandlerBase {
  void fanOutEntityChange(Map<String, dynamic> data) {
    final userIds = data['user_ids'];
    final entity = data['entity'];
    final aggregateId = data['id'];
    final event = data['event'];
    final actorUserId = data['actor_user_id'];
    if (userIds is! List ||
        entity is! String ||
        entity.isEmpty ||
        aggregateId is! String ||
        aggregateId.isEmpty ||
        event is! String ||
        !const {'insert', 'update', 'delete'}.contains(event) ||
        (actorUserId != null && actorUserId is! String)) {
      logger.warning(
        '[RealtimeFanout] realtime_event=malformed_payload reason=envelope',
      );
      return;
    }
    final message = jsonEncode({
      'type': 'subscription',
      'path': 'entity_changes',
      'payload': {
        'entity': entity,
        'id': aggregateId,
        'event': event,
        'actor_user_id': actorUserId,
      },
    });

    final seen = <String>{};
    final sentSessions = <WebSocketSession>{};
    var frameCount = 0;
    for (final userId in userIds) {
      if (userId is! String || userId.isEmpty || !seen.add(userId)) continue;
      if (!env.realtimeActorEchoEnabled && userId == actorUserId) continue;
      for (final session in getSessionsByUserId(userId)) {
        session.send(message);
        sentSessions.add(session);
        frameCount++;
      }
    }
    logger.info(
      '[RealtimeFanout] realtime_event=fanout kind=$entity '
      'recipients=${seen.length} direct_sessions=${sentSessions.length} '
      'frames=$frameCount actor_echo=${env.realtimeActorEchoEnabled}',
    );
  }
}
