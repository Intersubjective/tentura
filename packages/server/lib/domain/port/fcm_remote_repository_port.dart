import 'package:tentura_server/domain/entity/fcm_message_entity.dart';

abstract class FcmRemoteRepositoryPort {
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  });
}
