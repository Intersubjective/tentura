import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

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
  FcmRemoteRepositoryMock(this._logger);

  final Logger _logger;

  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async {
    _logger.info(
      '[FCM] mock send (injectable dev/test — no Firebase HTTP) '
      'devices=${fcmTokens.length} title="${message.title}"',
    );
    return [];
  }
}
