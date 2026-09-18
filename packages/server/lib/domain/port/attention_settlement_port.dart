import 'package:tentura_server/domain/attention/attention_models.dart';

/// Persists one recipient-owned obligation outcome after authorization.
abstract interface class AttentionSettlementPort {
  /// Occurrence [event_type] for a visible live obligation, or null if none.
  Future<String?> liveObligationEventType({
    required String accountId,
    required String receiptId,
  });

  Future<int> settle({
    required String accountId,
    required String receiptId,
    required AttentionSettlementKind kind,
  });
}
