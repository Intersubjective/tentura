import 'dart:convert';

import '../session/websocket_session_handler_base.dart';
import 'package:tentura_server/domain/entity/room_message_snapshot.dart';

/// Fans out validated Postgres invalidation hints to isolate-local sessions.
base mixin WebsocketPathEntityChanges on WebsocketSessionHandlerBase {
  Future<void> fanOutEntityChange(Map<String, dynamic> data) async {
    final userIds = data['user_ids'];
    final entity = data['entity'];
    final aggregateId = data['id'];
    final event = data['event'];
    final actorUserId = data['actor_user_id'];
    final rawMessageId = data['message_id'];
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

    final childId = rawMessageId is String && rawMessageId.isNotEmpty
        ? rawMessageId
        : null;

    final seen = <String>{};
    final sentSessions = <WebSocketSession>{};
    for (final userId in userIds) {
      if (userId is! String || userId.isEmpty || !seen.add(userId)) continue;
      if (!env.realtimeActorEchoEnabled && userId == actorUserId) continue;
      for (final session in getSessionsByUserId(userId)) {
        sentSessions.add(session);
      }
    }
    if (sentSessions.isEmpty) {
      return;
    }

    RoomMessageSnapshot? snapshot;
    if (entity == 'room_message' && event == 'insert' && childId != null) {
      try {
        snapshot = await roomMessageSnapshotLookup.findEligibleInsert(
          messageId: childId,
          beaconId: aggregateId,
        );
      } on Object catch (e) {
        logger.warning(
          '[RealtimeFanout] realtime_event=snapshot_lookup_failed '
          'message_id=$childId error=$e',
        );
      }
    }

    final payload = <String, dynamic>{
      'entity': entity,
      'id': aggregateId,
      'event': event,
      'actor_user_id': actorUserId,
    };
    if (childId != null) {
      payload['message_id'] = childId;
    }
    if (snapshot != null) {
      payload['message'] = _serializePaint(snapshot);
    }

    final message = jsonEncode({
      'type': 'subscription',
      'path': 'entity_changes',
      'payload': payload,
    });

    var frameCount = 0;
    for (final session in sentSessions) {
      session.send(message);
      frameCount++;
    }
    logger.info(
      '[RealtimeFanout] realtime_event=fanout kind=$entity '
      'recipients=${seen.length} direct_sessions=${sentSessions.length} '
      'frames=$frameCount actor_echo=${env.realtimeActorEchoEnabled} '
      'paint=${snapshot != null}',
    );
  }

  static Map<String, dynamic> _serializePaint(RoomMessageSnapshot snapshot) => {
    'id': snapshot.id,
    'beaconId': snapshot.beaconId,
    'authorId': snapshot.authorId,
    'body': snapshot.body,
    'createdAt': snapshot.createdAt.toUtc().toIso8601String(),
    'editedAt': snapshot.editedAt?.toUtc().toIso8601String(),
    'mentions': snapshot.mentions,
    'mentionSpans': snapshot.mentionSpans,
    'threadItemId': snapshot.threadItemId,
    'replyToMessageId': snapshot.replyToMessageId,
    'replyToAuthorId': snapshot.replyToAuthorId,
    'replyToAuthorTitle': snapshot.replyToAuthorTitle,
    'replyToBodyExcerpt': snapshot.replyToBodyExcerpt,
    'replyToHasAttachments': snapshot.replyToHasAttachments,
  };
}
