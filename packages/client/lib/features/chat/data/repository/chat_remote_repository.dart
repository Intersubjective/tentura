import 'dart:async';
import 'dart:convert';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../model/chat_message_remote_model.dart';

@singleton
class ChatRemoteRepository {
  ChatRemoteRepository(
    this._remoteApiService,
  );

  final RemoteApiService _remoteApiService;

  late final updates = _remoteApiService.webSocketMessages
      .where(
        (e) =>
            e['type'] == 'subscription' &&
            e['path'] == 'p2p_chat' &&
            e['payload'] is Map<String, dynamic> &&
            // ignore: avoid_dynamic_calls // temporary
            e['payload']['intent'] == 'watch_updates' &&
            // ignore: avoid_dynamic_calls // temporary
            e['payload']['messages'] is List<dynamic>,
      )
      // ignore: avoid_dynamic_calls // temporary
      .map((e) => e['payload']['messages'] as List<dynamic>)
      .map(
        (e) => e.map(
          (m) => ChatMessageRemoteModel.fromJson(
            m as Map<String, dynamic>,
          ).asEntity,
        ),
      )
      .asBroadcastStream();

  /// Stream of send-message acknowledgements from the server, containing
  /// server-assigned serverId and createdAt for optimistic messages.
  late final messageAcks = _remoteApiService.webSocketMessages
      .where(
        (e) =>
            e['type'] == 'message_ack' &&
            e['path'] == 'p2p_chat' &&
            e['payload'] is Map<String, dynamic> &&
            // ignore: avoid_dynamic_calls
            e['payload']['intent'] == 'send_message',
      )
      .map((e) => e['payload'] as Map<String, dynamic>)
      .map(
        (p) => (
          clientId: p['client_id']! as String,
          serverId: p['server_id']! as String,
          createdAt: DateTime.parse(p['created_at']! as String),
        ),
      )
      .asBroadcastStream();

  /// Stream of fetch_history responses.
  late final historyResponses = _remoteApiService.webSocketMessages
      .where(
        (e) =>
            e['type'] == 'message_ack' &&
            e['path'] == 'p2p_chat' &&
            e['payload'] is Map<String, dynamic> &&
            // ignore: avoid_dynamic_calls
            e['payload']['intent'] == 'fetch_history',
      )
      .map((e) => e['payload'] as Map<String, dynamic>)
      .map(
        (p) => (
          messages: (p['messages'] as List<dynamic>).map(
            (m) => ChatMessageRemoteModel.fromJson(
              m as Map<String, dynamic>,
            ).asEntity,
          ),
          hasMore: p['has_more'] as bool? ?? false,
        ),
      )
      .asBroadcastStream();

  Stream<WebSocketState> get webSocketState => _remoteApiService.webSocketState;

  void subscribeToUpdates({
    required DateTime fromMoment,
    required int batchSize,
  }) => _remoteApiService.webSocketSend(
    jsonEncode({
      'type': 'subscription',
      'path': 'p2p_chat',
      'payload': {
        'intent': 'watch_updates',
        'params': {
          'batch_size': batchSize,
          'from_timestamp': fromMoment.toIso8601String(),
        },
      },
    }),
  );

  Future<void> sendMessage({
    required String receiverId,
    required String clientId,
    required String content,
  }) async => _remoteApiService.webSocketSend(
    jsonEncode({
      'type': 'message',
      'path': 'p2p_chat',
      'payload': {
        'intent': 'send_message',
        'message': {
          'receiver_id': receiverId,
          'client_id': clientId,
          'content': content,
        },
      },
    }),
  );

  Future<void> setMessageSeen({
    required ChatMessageEntity message,
  }) async => _remoteApiService.webSocketSend(
    jsonEncode({
      'type': 'message',
      'path': 'p2p_chat',
      'payload': {
        'intent': 'mark_as_delivered',
        'message': {
          'client_id': message.clientId,
          'server_id': message.serverId,
        },
      },
    }),
  );

  void fetchHistory({
    required String peerId,
    required DateTime before,
    int limit = 20,
  }) => _remoteApiService.webSocketSend(
    jsonEncode({
      'type': 'message',
      'path': 'p2p_chat',
      'payload': {
        'intent': 'fetch_history',
        'message': {
          'peer_id': peerId,
          'before_timestamp': before.toIso8601String(),
          'limit': limit,
        },
      },
    }),
  );
}
