import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/p2p_message_entity.dart';

import 'package:tentura_server/domain/port/p2p_message_repository_port.dart';

@Injectable(
  as: P2pMessageRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class P2pMessageRepositoryMock implements P2pMessageRepositoryPort {
  @override
  Future<P2pMessageEntity> create({
    required String content,
    required String senderId,
    required String receiverId,
    required UuidValue clientId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Iterable<P2pMessageEntity>> fetchByUserId({
    required DateTime from,
    required String id,
    required int limit,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markAsDelivered({
    required String clientId,
    required String serverId,
    required String receiverId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Iterable<P2pMessageEntity>> fetchHistoryForPair({
    required String userId,
    required String peerId,
    required DateTime before,
    required int limit,
  }) {
    throw UnimplementedError();
  }
}
