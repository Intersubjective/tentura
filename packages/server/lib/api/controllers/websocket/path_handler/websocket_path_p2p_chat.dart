import 'dart:convert';
import 'package:uuid/uuid_value.dart';

import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/p2p_chat_case.dart';

import '../session/websocket_session_handler_base.dart';

base mixin WebsocketPathP2pChat on WebsocketSessionHandlerBase {
  P2pChatCase get p2pChatCase;

  Future<void> onP2pChatMessage(
    WebSocketSession session,
    JwtEntity jwt,
    Map<String, dynamic> payload,
  ) async {
    final message = payload['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException('Invalid message');
    }
    switch (payload['intent']) {
      case 'send_message':
        final entity = await p2pChatCase.create(
          senderId: jwt.sub,
          receiverId: message['receiver_id']! as String,
          clientMessageId: UuidValue.fromString(
            message['client_id']! as String,
          ),
          content: message['content']! as String,
        );
        session.send(
          jsonEncode({
            'type': 'message_ack',
            'path': 'p2p_chat',
            'payload': {
              'intent': 'send_message',
              'client_id': entity.clientId,
              'server_id': entity.serverId,
              'created_at': entity.createdAt.toIso8601String(),
            },
          }),
        );

      case 'mark_as_delivered':
        await p2pChatCase.markAsDelivered(
          clientId: message['client_id']! as String,
          serverId: message['server_id']! as String,
          receiverId: jwt.sub,
        );

      case 'fetch_history':
        final before = message['before_timestamp'] != null
            ? DateTime.parse(message['before_timestamp']! as String)
            : DateTime.timestamp();
        final limit = message['limit'] as int? ?? 20;
        final messages = await p2pChatCase.fetchHistory(
          userId: jwt.sub,
          peerId: message['peer_id']! as String,
          before: before,
          limit: limit,
        );
        session.send(
          jsonEncode({
            'type': 'message_ack',
            'path': 'p2p_chat',
            'payload': {
              'intent': 'fetch_history',
              'messages': messages.map((e) => e.toJson()).toList(),
              'has_more': messages.length == limit,
            },
          }),
        );

      default:
        throw UnsupportedError(
          '${payload['intent']} is not supported!',
        );
    }
  }

  /// One-time catch-up fetch on subscribe; no polling timer.
  Future<void> onP2pChatSubscription(
    WebSocketSession session,
    Map<String, dynamic> payload,
  ) async {
    final jwt = getJwtBySession(session);
    final params = payload['params'];
    if (params is! Map<String, dynamic>) {
      throw const FormatException('Invalid params');
    }

    switch (payload['intent']) {
      case 'watch_updates':
        final batchSize =
            params['batch_size'] as int? ?? env.chatDefaultBatchSize;
        final fromTimestamp =
            DateTime.parse(params['from_timestamp']! as String);

        final messages = await p2pChatCase.fetchByUserId(
          userId: jwt.sub,
          from: fromTimestamp,
          batchSize: batchSize,
        );
        if (messages.isNotEmpty) {
          session.send(
            jsonEncode({
              'type': 'subscription',
              'path': 'p2p_chat',
              'payload': {
                'intent': 'watch_updates',
                'messages': messages.map((e) => e.toJson()).toList(),
              },
            }),
          );
        }

      default:
        throw UnsupportedError(
          '${payload['intent']} is not supported!',
        );
    }
  }
}
