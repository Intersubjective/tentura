import 'dart:convert';

import 'package:tentura_server/domain/entity/realtime_watch_grant.dart';

import '../session/websocket_session_handler_base.dart';

/// Fans out validated Postgres invalidation hints to isolate-local sessions.
base mixin WebsocketPathEntityChanges on WebsocketSessionHandlerBase {
  Future<void> onEntityChangeSubscription(
    WebSocketSession session,
    Map<String, dynamic> payload,
  ) async {
    final scope = RealtimeWatchScope.fromWire(payload['scope']);
    if (scope == null) throw const FormatException('Invalid watch scope');
    switch (payload['intent']) {
      case 'replace_watch':
        final grant = payload['grant'];
        if (grant is! String) {
          throw const FormatException('Invalid watch grant');
        }
        await replaceEntityWatch(session, scope: scope, grantToken: grant);
      case 'remove_watch':
        getJwtBySession(session);
        removeEntityWatch(session, scope);
      default:
        throw UnsupportedError('Unsupported entity_changes intent');
    }
  }

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
      logger.warning(
        '[RealtimeFanout] realtime_event=malformed_payload reason=envelope',
      );
      return;
    }
    if (subjectIds is List && subjectIds.any((id) => id is! String)) {
      logger.warning(
        '[RealtimeFanout] realtime_event=malformed_payload '
        'reason=subject_ids',
      );
      return;
    }

    final normalizedSubjectIds = subjectIds is List
        ? subjectIds.cast<String>()
        : const [];
    final message = _entityChangeMessage(
      entity: entity,
      aggregateId: aggregateId,
      event: event,
      actorUserId: actorUserId as String?,
      subjectIds: normalizedSubjectIds,
    );

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

    final watchTargets = watchIntersections(normalizedSubjectIds);
    final watchSessions = <WebSocketSession>{};
    for (final entry in watchTargets.entries) {
      final session = entry.key;
      if (sentSessions.contains(session)) continue;
      if (!env.realtimeActorEchoEnabled &&
          getJwtBySession(session).sub == actorUserId) {
        continue;
      }
      final authorizedSubjects = entry.value.toList()..sort();
      for (var start = 0; start < authorizedSubjects.length; start += 100) {
        final end = start + 100 < authorizedSubjects.length
            ? start + 100
            : authorizedSubjects.length;
        final chunk = authorizedSubjects.sublist(start, end);
        session.send(
          _entityChangeMessage(
            entity: entity,
            // A relationship batch aggregate may name another changed user.
            // Watch-only sessions receive an authorized aggregate identifier.
            aggregateId: chunk.first,
            event: event,
            actorUserId: actorUserId,
            subjectIds: chunk,
          ),
        );
        watchSessions.add(session);
        frameCount++;
      }
    }
    logger.info(
      '[RealtimeFanout] realtime_event=fanout kind=$entity '
      'recipients=${seen.length} direct_sessions=${sentSessions.length} '
      'watch_sessions=${watchSessions.length} frames=$frameCount '
      'actor_echo=${env.realtimeActorEchoEnabled}',
    );
  }

  String _entityChangeMessage({
    required String entity,
    required String aggregateId,
    required String event,
    required String? actorUserId,
    required List<String> subjectIds,
  }) => jsonEncode({
    'type': 'subscription',
    'path': 'entity_changes',
    'payload': {
      'entity': entity,
      'id': aggregateId,
      'event': event,
      'actor_user_id': actorUserId,
      if (subjectIds.isNotEmpty) 'subject_ids': subjectIds,
    },
  });
}
