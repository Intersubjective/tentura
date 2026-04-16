import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/p2p_message_entity.dart';

abstract class P2pMessageRepositoryPort {
  Future<P2pMessageEntity> create({
    required String content,
    required String senderId,
    required String receiverId,
    required UuidValue clientId,
  });

  Future<void> markAsDelivered({
    required String clientId,
    required String serverId,
    required String receiverId,
  });

  Future<Iterable<P2pMessageEntity>> fetchByUserId({
    required DateTime from,
    required String id,
    required int limit,
  });

  Future<Iterable<P2pMessageEntity>> fetchHistoryForPair({
    required String userId,
    required String peerId,
    required DateTime before,
    required int limit,
  });
}
