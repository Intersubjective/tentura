import 'package:tentura_server/domain/attention/attention_models.dart';

/// Persists one recipient-owned obligation outcome after authorization.
// A named port keeps the settlement use case independent from the database.
// ignore: one_member_abstracts
abstract interface class AttentionSettlementPort {
  Future<int> settle({
    required String accountId,
    required String receiptId,
    required AttentionSettlementKind kind,
  });
}
