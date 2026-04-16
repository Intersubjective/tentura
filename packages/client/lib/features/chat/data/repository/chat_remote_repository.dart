import 'dart:async';
import 'dart:convert';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/remote_repository.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../../domain/entity/peer_presence_entity.dart';
import '../../domain/port/chat_remote_repository_port.dart';
import '../model/chat_message_remote_model.dart';

@Singleton(
  as: ChatRemoteRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class ChatRemoteRepository extends RemoteRepository
    implements ChatRemoteRepositoryPort {
  ChatRemoteRepository({
    required super.remoteApiService,
    required super.log,
  });

  @override
  late final updates = remoteApiService.webSocketMessages
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
  @override
  late final presenceUpdates = remoteApiService.webSocketMessages
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
  @override
  late final typingUpdates = remoteApiService.webSocketMessages
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
  @override
  late final messageAcks = remoteApiService.webSocketMessages
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
  @override
  late final historyResponses = remoteApiService.webSocketMessages
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

  @override
  Stream<WebSocketState> get webSocketState => remoteApiService.webSocketState;

  @override
  void subscribePresencePeers(List<String> peerIds) =>
      remoteApiService.webSocketSend(
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

  @override
  void subscribeToUpdates({
    required DateTime fromMoment,
    required int batchSize,
  }) => remoteApiService.webSocketSend(
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

  @override
  void sendTyping({
    required String receiverId,
  }) => remoteApiService.webSocketSend(
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

  @override
  Future<void> sendMessage({
    required String receiverId,
    required String clientId,
    required String content,
  }) async => remoteApiService.webSocketSend(
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

  @override
  Future<void> setMessageSeen({
    required ChatMessageEntity message,
  }) async => remoteApiService.webSocketSend(
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

  @override
  void fetchHistory({
    required String peerId,
    required DateTime before,
    int limit = 20,
  }) => remoteApiService.webSocketSend(
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
