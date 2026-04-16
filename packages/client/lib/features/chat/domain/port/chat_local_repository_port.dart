import 'package:tentura/features/chat/domain/entity/chat_message_entity.dart';

abstract class ChatLocalRepositoryPort {
  Future<void> saveMessages({
    required Iterable<ChatMessageEntity> messages,
  });

  Future<Iterable<ChatMessageEntity>> getChatMessagesForPair({
    required String senderId,
    required String receiverId,
  });

  Future<Iterable<ChatMessageEntity>> getAllNewMessagesFor({
    required String userId,
  });

  Future<DateTime> getMostRecentMessageTimestamp({
    required String userId,
  });

  Future<void> deleteMessageForMe({
    required String clientId,
    required String serverId,
  });
}
