import 'package:tentura_server/domain/entity/fcm_message_entity.dart';

/// Outbound FCM batching (implemented by `data/service/fcm_batch_queue.dart`).
abstract class FcmBatchQueuePort {
  void enqueue({
    required String receiverId,
    required Set<String> fcmTokens,
    required FcmNotificationEntity message,
  });

  /// Stops periodic flush (implemented on [FcmBatchQueue]).
  void dispose();
}
