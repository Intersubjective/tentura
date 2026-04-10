import 'dart:convert';

import '../session/websocket_session_handler_base.dart';

/// Fans out Postgres `entity_changes` NOTIFY payloads to affected WebSocket
/// sessions based on the `user_ids` array embedded in the notification.
base mixin WebsocketPathEntityChanges on WebsocketSessionHandlerBase {
  void fanOutEntityChange(Map<String, dynamic> data) {
    final userIds = data['user_ids'];
    if (userIds is! List<dynamic>) return;

    final message = jsonEncode({
      'type': 'subscription',
      'path': 'entity_changes',
      'payload': {
        'entity': data['entity'],
        'id': data['id'],
        'event': data['event'],
      },
    });

    final seen = <String>{};
    for (final uid in userIds) {
      if (uid is String && seen.add(uid)) {
        for (final session in getSessionsByUserId(uid)) {
          session.send(message);
        }
      }
    }
  }
}
