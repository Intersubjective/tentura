import 'dart:convert';

import '../session/websocket_session_handler_base.dart';
import 'package:tentura_server/consts/realtime_consts.dart';
import 'package:tentura_server/domain/entity/room_message_snapshot.dart';

/// Fans out validated Postgres invalidation hints to isolate-local sessions.
base mixin WebsocketPathEntityChanges on WebsocketSessionHandlerBase {
  static const _forwardedExtrasByKind = <String, Set<String>>{
    'room_seen_peer': {'seen_user_id', 'last_seen_at'},
    'people_seen': {'last_seen_at'},
  };

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

    final forwardedExtras = _forwardedExtrasByKind[entity];
    if (forwardedExtras != null) {
      final seenUserId = data['seen_user_id'];
      final lastSeenAt = data['last_seen_at'];
      if ((forwardedExtras.contains('seen_user_id') &&
              (seenUserId is! String || seenUserId.isEmpty)) ||
          lastSeenAt is! String ||
          DateTime.tryParse(lastSeenAt) == null) {
        logger.warning(
          '[RealtimeFanout] realtime_event=malformed_payload reason=$entity',
        );
        return;
      }
    }

    final childId = rawMessageId is String && rawMessageId.isNotEmpty
        ? rawMessageId
        : null;

    final seen = <String>{};
    final sentSessions = <WebSocketSession>{};
    for (final userId in userIds) {
      if (userId is! String || userId.isEmpty || !seen.add(userId)) continue;
      if (!env.realtimeActorEchoEnabled &&
          userId == actorUserId &&
          !kRealtimeAlwaysEchoKinds.contains(entity)) {
        continue;
      }
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
    if (forwardedExtras != null) {
      for (final key in forwardedExtras) {
        payload[key] = data[key];
      }
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

  // DORMANT(item-threads): threadItemId in realtime paint; always null in production (General is thread_item_id IS NULL).
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
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
    'semanticMarker': snapshot.semanticMarker,
    'systemPayload': snapshot.systemPayload,
    'systemMessageKind': snapshot.systemMessageKind,
    'quotedFact': switch (snapshot.quotedFact) {
      null => null,
      final q => {
        'factCardId': q.factCardId,
        'seq': q.seq,
        'text': q.factText,
        'pinnedById': q.pinnedById,
        'pinnedByTitle': q.pinnedByTitle,
        'visibility': q.visibility,
        'status': q.status,
        'currentSeq': q.currentSeq,
        'attachmentsJson': q.attachmentsJson,
      },
    },
  };
}
