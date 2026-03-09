import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/fcm_message_entity.dart';

import '../fcm_remote_repository.dart';

@Singleton(
  as: FcmRemoteRepository,
  env: [
    Environment.dev,
    Environment.test,
  ],
  order: 1,
)
class FcmRemoteRepositoryMock implements FcmRemoteRepository {
  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async => [];
}
