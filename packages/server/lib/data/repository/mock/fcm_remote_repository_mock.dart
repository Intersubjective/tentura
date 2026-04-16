import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';

@Singleton(
  as: FcmRemoteRepositoryPort,
  env: [
    Environment.dev,
    Environment.test,
  ],
  order: 1,
)
class FcmRemoteRepositoryMock implements FcmRemoteRepositoryPort {
  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async => [];
}
