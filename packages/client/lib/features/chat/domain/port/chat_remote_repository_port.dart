import 'package:tentura/features/chat/domain/entity/chat_message_entity.dart';
import 'package:tentura/features/chat/domain/entity/peer_presence_entity.dart';

import 'chat_stream_types.dart';

abstract class ChatRemoteRepositoryPort {
  Stream<Iterable<ChatMessageEntity>> get updates;

  Stream<Iterable<PeerPresenceEntity>> get presenceUpdates;

  Stream<TypingEvent> get typingUpdates;

  Stream<MessageAck> get messageAcks;

  Stream<HistoryResponse> get historyResponses;

  Stream<WebSocketState> get webSocketState;

  void subscribePresencePeers(List<String> peerIds);

  void subscribeToUpdates({
    required DateTime fromMoment,
    required int batchSize,
  });

  void sendTyping({
    required String receiverId,
  });

  Future<void> sendMessage({
    required String receiverId,
    required String clientId,
    required String content,
  });

  Future<void> setMessageSeen({
    required ChatMessageEntity message,
  });

  void fetchHistory({
    required String peerId,
    required DateTime before,
    int limit = 20,
  });
}
