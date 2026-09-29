import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/inbox_item_entity.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';

@Injectable(
  as: InboxRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class InboxRepositoryMock implements InboxRepositoryPort {
  @override
  Future<List<InboxItemEntity>> fetchByUserId(
    String userId, {
    String? context,
    int limit = 50,
    int offset = 0,
  }) => Future.value(const []);

  @override
  Future<List<String>> fetchRejectedUserIdsByBeacon(String beaconId) =>
      Future.value(const []);

  @override
  Future<List<String>> fetchWatchingUserIdsByBeacon(String beaconId) =>
      Future.value(const []);

  @override
  Future<void> applyTombstoneAfterWithdraw({
    required String userId,
    required String beaconId,
  }) => Future.value();

  @override
  Future<void> upsertWatchingForSender({
    required String senderId,
    required String beaconId,
    String? context,
    bool touchForwardOrdering = true,
  }) => Future.value();

  @override
  Future<void> setStatus({
    required String userId,
    required String beaconId,
    required int status,
    required String rejectionMessage,
  }) => Future.value();

  @override
  Future<void> markForwardCancelledForRecipient({
    required String beaconId,
    required String recipientId,
  }) => Future.value();
}
