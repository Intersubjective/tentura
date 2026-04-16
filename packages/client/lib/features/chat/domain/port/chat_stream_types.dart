import 'package:tentura/features/chat/domain/entity/chat_message_entity.dart';

export 'package:tentura_root/domain/enums.dart' show WebSocketState;

typedef MessageAck = ({String clientId, String serverId, DateTime createdAt});
typedef HistoryResponse = ({
  Iterable<ChatMessageEntity> messages,
  bool hasMore,
});
typedef TypingEvent = ({String senderId, String receiverId});
