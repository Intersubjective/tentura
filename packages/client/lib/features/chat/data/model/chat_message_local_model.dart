import 'package:tentura/data/database/database.dart';

import '../../domain/entity/chat_message_entity.dart';

extension type const ChatMessageLocalModel(P2pMessage i) implements P2pMessage {
  ChatMessageEntity toEntity() => ChatMessageEntity(
    clientId: i.clientId,
    serverId: i.serverId,
    senderId: i.senderId,
    receiverId: i.receiverId,
    createdAt: i.createdAt,
    deliveredAt: i.deliveredAt,
    content: i.content,
    status: i.status,
  );
}
