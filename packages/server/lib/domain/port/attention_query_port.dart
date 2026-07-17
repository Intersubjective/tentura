import 'package:tentura_server/domain/attention/attention_models.dart';

// Feed and summary are one atomic read operation by contract.
// ignore: one_member_abstracts
abstract interface class AttentionQueryPort {
  /// Returns unread summary and one authorized page from one database statement.
  Future<AttentionFeed> attentionFeed({
    required String accountId,
    required AttentionFeedView view,
    AttentionCursor? cursor,
    String? search,
    int limit = 50,
  });
}
