import 'package:tentura_server/domain/entity/fcm_message_entity.dart';

// ignore: one_member_abstracts -- injectable port with a single remote call
abstract class FcmRemoteRepositoryPort {
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  });
}
