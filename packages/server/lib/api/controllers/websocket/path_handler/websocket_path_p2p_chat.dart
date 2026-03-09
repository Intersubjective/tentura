import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid_value.dart';

import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/p2p_chat_case.dart';

import '../session/websocket_session_handler_base.dart';

base mixin WebsocketPathP2pChat on WebsocketSessionHandlerBase {
  P2pChatCase get p2pChatCase;

  Future<void> onP2pChatMessage(
    JwtEntity jwt,
    Map<String, dynamic> payload,
  ) {
    final message = payload['message'];
    if (message is Map<String, dynamic>) {
      return switch (payload['intent']) {
        'send_message' => p2pChatCase.create(
          senderId: jwt.sub,
          receiverId: message['receiver_id']! as String,
          clientMessageId: UuidValue.fromString(
            message['client_id']! as String,
          ),
          content: message['content']! as String,
        ),
        'mark_as_delivered' => p2pChatCase.markAsDelivered(
          clientId: message['client_id']! as String,
          serverId: message['server_id']! as String,
          receiverId: jwt.sub,
        ),
        final intent => throw UnsupportedError('$intent is not supported!'),
      };
    }
    throw const FormatException('Invalid message');
  }

  Future<void> onP2pChatSubscription(
    WebSocketSession session,
    Map<String, dynamic> payload,
  ) async {
    final jwt = getJwtBySession(session);
    final params = payload['params'];
    if (params is! Map<String, dynamic>) {
      throw const FormatException('Invalid params');
    }

    final batchSize = params['batch_size'] as int? ?? env.chatDefaultBatchSize;

    var fromTimestamp = DateTime.parse(params['from_timestamp']! as String);

    return switch (payload['intent']) {
      'watch_updates' => addWorker(
        session,
        worker: Timer.periodic(
          env.chatPollingInterval,
          (_) async {
            final messages = await p2pChatCase.fetchByUserId(
              userId: jwt.sub,
              from: fromTimestamp,
              batchSize: batchSize,
            );
            if (messages.isEmpty) {
              return;
            }
            fromTimestamp = messages.fold(
              fromTimestamp,
              (max, msg) {
                final latest = msg.deliveredAt ?? msg.createdAt;
                return max.isAfter(latest) ? max : latest;
              },
            );
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
          },
        ),
      ),
      final intent => throw UnsupportedError('$intent is not supported!'),
    };
  }
}
