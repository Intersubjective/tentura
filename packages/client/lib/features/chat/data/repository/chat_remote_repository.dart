import 'dart:async';
import 'dart:convert';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../../domain/entity/peer_presence_entity.dart';
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

  /// Peer presence batches from `user_presence` subscription.
  late final presenceUpdates = _remoteApiService.webSocketMessages
      .where(
        (e) =>
            e['type'] == 'subscription' &&
            e['path'] == 'user_presence' &&
            e['payload'] is Map<String, dynamic> &&
            // ignore: avoid_dynamic_calls // temporary
            e['payload']['intent'] == 'watch_updates' &&
            // ignore: avoid_dynamic_calls // temporary
            e['payload']['events'] is List<dynamic>,
      )
      // ignore: avoid_dynamic_calls // temporary
      .map((e) => e['payload']['events'] as List<dynamic>)
      .map(
        (list) => list.map((raw) {
          final m = raw as Map<String, dynamic>;
          final statusName = m['status'] as String? ?? 'unknown';
          return PeerPresenceEntity(
            userId: m['user_id']! as String,
            status: UserPresenceStatus.values.firstWhere(
              (s) => s.name == statusName,
              orElse: () => UserPresenceStatus.unknown,
            ),
            lastSeenAt: DateTime.parse(m['last_seen_at']! as String),
          );
        }),
      )
      .asBroadcastStream();

  /// Stream of typing notifications (`p2p_chat` intent `typing`).
  late final typingUpdates = _remoteApiService.webSocketMessages
      .where(
        (e) =>
            e['type'] == 'subscription' &&
            e['path'] == 'p2p_chat' &&
            e['payload'] is Map<String, dynamic> &&
            // ignore: avoid_dynamic_calls // temporary
            e['payload']['intent'] == 'typing',
      )
      .map((e) {
        // ignore: avoid_dynamic_calls // temporary
        final msg = e['payload']['message'] as Map<String, dynamic>?;
        if (msg == null) {
          return (senderId: '', receiverId: '');
        }
        return (
          senderId: msg['sender_id']! as String,
          receiverId: msg['receiver_id']! as String,
        );
      })
      .where((e) => e.senderId.isNotEmpty && e.receiverId.isNotEmpty)
      .asBroadcastStream();

  /// Stream of send-message acknowledgements from the server, containing
  /// server-assigned serverId and createdAt for optimistic messages.
  late final messageAcks = _remoteApiService.webSocketMessages
      .where(
        (e) =>
            e['type'] == 'message_ack' &&
            e['path'] == 'p2p_chat' &&
            e['payload'] is Map<String, dynamic> &&
            // ignore: avoid_dynamic_calls // temporary
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
            // ignore: avoid_dynamic_calls // temporary
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

  void subscribePresencePeers(List<String> peerIds) =>
      _remoteApiService.webSocketSend(
        jsonEncode({
          'type': 'subscription',
          'path': 'user_presence',
          'payload': {
            'intent': 'watch_updates',
            'params': {
              'peer_ids': peerIds,
            },
          },
        }),
      );

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

  void sendTyping({
    required String receiverId,
  }) => _remoteApiService.webSocketSend(
    jsonEncode({
      'type': 'message',
      'path': 'p2p_chat',
      'payload': {
        'intent': 'typing',
        'message': {
          'receiver_id': receiverId,
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
