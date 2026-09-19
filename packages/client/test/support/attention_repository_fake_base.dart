import 'package:tentura/domain/attention/entity/activity_beacon_attention.dart';
import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
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

  // The clear axis has no safe default: a fake that silently answered
  // "complete" would let a test sweep attention without saying so. Override
  // deliberately, or fail loudly.
  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async =>
      throw UnimplementedError('clearSnapshot');

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) async =>
      throw UnimplementedError('clear');

  @override
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
  }) async =>
      throw UnimplementedError('dismissAll');

  @override
  Future<AttentionUndoResult> undo({
    required String operationId,
    required String undoToken,
  }) async =>
      throw UnimplementedError('undo');

  @override
  Future<AttentionReconcileResult> reconcile() async =>
      throw UnimplementedError('reconcile');

  @override
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async =>
      throw UnimplementedError('requestHistory');
}
