import '../entity/attention_feed.dart';

abstract interface class AttentionRepositoryPort {
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  });

  Future<int> markSeen(List<String> ids);

  Future<int> markAllSeen();

  Future<int> settle({required String receiptId, required String kind});
}
