import '../entity/attention_feed.dart';
import '../entity/attention_summary.dart';
import '../entity/my_work_beacon_attention.dart';

abstract interface class AttentionRepositoryPort {
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  });

  /// Returns the unread subset of a bounded set of authorized Beacon ids.
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds);

  /// Authorized beacon ids where the viewer holds an unsettled requires-action receipt.
  Future<Set<String>> liveObligationBeacons();

  Future<int> markSeen(List<String> ids);

  Future<int> markUnseen(List<String> ids);

  Future<int> markAllSeen({AttentionSurface? surface});

  Future<AttentionSurfaceSummary> surfaceSummary();

  Future<int> markSeenForBeacon(String beaconId);

  Future<List<MyWorkBeaconAttention>> myWorkAttention(Set<String> beaconIds);

  Future<int> settle({required String receiptId, required String kind});
}
