import 'package:tentura_server/domain/entity/p2p_message_entity.dart';

import '../database/tentura_db.dart';

P2pMessageEntity p2pMessageModelToEntity(P2pMessage model) => P2pMessageEntity(
  clientId: model.clientId.uuid,
  serverId: model.serverId.uuid,
  content: model.content,
  senderId: model.senderId,
  receiverId: model.receiverId,
  createdAt: model.createdAt.dateTime,
  deliveredAt: model.deliveredAt?.dateTime,
);
