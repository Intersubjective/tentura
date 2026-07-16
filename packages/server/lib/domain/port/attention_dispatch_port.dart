import 'package:tentura_server/domain/attention/attention_models.dart';

// This intentionally narrow port isolates transactional receipt persistence.
// ignore: one_member_abstracts
abstract interface class AttentionDispatchPort {
  /// Materializes every recipient receipt inside the caller-owned transaction.
  Future<List<AttentionChannelDecision>> record(AttentionDispatchIntent intent);
}
