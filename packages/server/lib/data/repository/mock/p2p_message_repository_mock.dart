import 'package:injectable/injectable.dart';
import 'package:uuid/uuid_value.dart';

import 'package:tentura_server/domain/entity/p2p_message_entity.dart';

import '../p2p_message_repository.dart';

@Injectable(
  as: P2pMessageRepository,
  env: [Environment.test],
  order: 1,
)
class P2pMessageRepositoryMock implements P2pMessageRepository {
  @override
  Future<void> create({
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
  Future<int> markAsDelivered({
    required String clientId,
    required String serverId,
    required String receiverId,
  }) {
    throw UnimplementedError();
  }
}
