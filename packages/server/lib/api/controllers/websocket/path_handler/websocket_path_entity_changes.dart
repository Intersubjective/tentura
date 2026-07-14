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
    final subjectIds = data['subject_ids'];
    if (userIds is! List ||
        entity is! String ||
        entity.isEmpty ||
        aggregateId is! String ||
        aggregateId.isEmpty ||
        event is! String ||
        !const {'insert', 'update', 'delete'}.contains(event) ||
        (actorUserId != null && actorUserId is! String) ||
        (subjectIds != null && subjectIds is! List)) {
      logger.warning('[WebsocketPathEntityChanges] Ignored malformed payload');
      return;
    }
    if (subjectIds is List && subjectIds.any((id) => id is! String)) {
      logger.warning(
        '[WebsocketPathEntityChanges] Ignored malformed subject_ids',
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
        'subject_ids': ?subjectIds,
      },
    });

    final seen = <String>{};
    for (final userId in userIds) {
      if (userId is! String || userId.isEmpty || !seen.add(userId)) continue;
      if (!env.realtimeActorEchoEnabled && userId == actorUserId) continue;
      for (final session in getSessionsByUserId(userId)) {
        session.send(message);
      }
    }
  }
}
