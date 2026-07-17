import 'package:tentura_server/domain/attention/attention_models.dart';

abstract interface class AttentionChannelDeliveryPort {
  Future<List<AttentionChannelDelivery>> claimDue({
    required String workerId,
    required DateTime now,
    required int limit,
  });

  Future<void> markDelivered({required String id, required String workerId});

  Future<void> retryOrDeadLetter({
    required String id,
    required String workerId,
    required DateTime now,
    required Object error,
  });
}
