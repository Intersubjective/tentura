import 'package:tentura/domain/attention/entity/activity_beacon_attention.dart';
import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';

/// Default no-op implementations for newly widened [AttentionRepositoryPort] APIs.
abstract class AttentionRepositoryFake implements AttentionRepositoryPort {
  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async =>
      const AttentionSurfaceSummary(
        activityUnreadTotal: 0,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
      );

  @override
  Future<int> markSeenForBeacon(String beaconId) async => 0;

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention(
    Set<String> beaconIds,
  ) async =>
      const [];

  @override
  Future<ActivityOfferPage> activityOffers({
    String? cursor,
    int limit = 20,
  }) async =>
      const ActivityOfferPage();

  @override
  Future<ActivityBeaconAttention> activityAttention({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async =>
      ActivityBeaconAttention(
        beaconId: beaconId,
        eventTotal: 0,
        unseenCount: 0,
        latestAt: DateTime.utc(1970),
      );
}
