import 'package:logging/logging.dart';

import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/port/op_id_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';

import '../features/block/support/controllable_block_case.dart';
import 'attention_repository_fake_base.dart';
import 'test_realtime_sync.dart';

AttentionCase buildAttentionCase({
  AttentionRepositoryPort? repository,
  AttentionAccountPort? accounts,
  RealtimeSyncCase? realtimeSyncCase,
  BlockCase? blockCase,
  FeedSessionRegistry? feedSessions,
  Logger? logger,
  bool? qaLatencyMeasurementEnabled,
  OpIdPort? opIds,
}) => AttentionCase(
  repository ?? StubAttentionRepository(),
  accounts ?? _StubAttentionAccounts(),
  realtimeSyncCase ?? buildTestRealtimeSync().case_,
  blockCase ?? noopBlockCase(),
  feedSessions ?? FeedSessionRegistry(),
  logger ?? Logger('my-work-test-attention'),
  opIds ?? OpIdService(),
  qaLatencyMeasurementEnabled: qaLatencyMeasurementEnabled ?? false,
);

class StubAttentionRepository extends AttentionRepositoryFake {
  Set<String> obligationBeaconIds = const {};

  int myWorkAttentionCallCount = 0;

  List<Set<String>> myWorkAttentionCalls = [];

  Duration myWorkAttentionDelay = Duration.zero;

  Object? myWorkAttentionError;

  List<MyWorkBeaconAttention> myWorkAttentionResult = const [];

  final markSeenForBeaconCalls = <String>[];

  final settleCalls = <String>[];

  /// The clear axis (U10b). Recorded so a test can prove the × writes here and
  /// nowhere else.
  final clearSnapshotCalls = <String>[];
  final clearCalls = <String>[];

  /// What the server answers a clear with. The default is the honest one: a
  /// `complete` that applied the receipt it was given. A test that wants a
  /// refusal says so (U15R-c/R6).
  AttentionClearResult Function(String operationId, String? receiptId)?
  clearResultBuilder;

  /// Fails the clear command outright.
  Object? clearError;

  /// The projection the server returns **after** a successful clear, when the
  /// test needs to say what the card previews next. Left null, the stub
  /// models the server itself: the cleared receipt leaves the projection.
  List<MyWorkBeaconAttention>? myWorkAttentionAfterClear;

  String? _lastClearReceiptId;

  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async {
    clearSnapshotCalls.add(receiptId ?? beaconId ?? '');
    _lastClearReceiptId = receiptId;
    return AttentionClearSnapshot(
      snapshotToken: 'token-${clearSnapshotCalls.length}',
      receiptIds: [?receiptId],
    );
  }

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) async {
    clearCalls.add(snapshotToken);
    final error = clearError;
    if (error != null) throw error;
    final build = clearResultBuilder;
    final result = build != null
        ? build(operationId, _lastClearReceiptId)
        : AttentionClearResult(
            operationId: operationId,
            status: AttentionOperationStatus.complete,
            appliedReceiptIds: [?_lastClearReceiptId],
          );
    if (result.appliedReceiptIds.isNotEmpty) {
      // The server's side of the clear axis, modelled: an applied receipt is
      // gone from the next projection. A fake that kept answering with the
      // pre-clear row would let a broken re-read look correct (U15R-c/R6).
      final applied = result.appliedReceiptIds.toSet();
      myWorkAttentionResult =
          myWorkAttentionAfterClear ??
          [
            for (final row in myWorkAttentionResult)
              if (applied.contains(row.latestUnseen?.id))
                row.copyWith(
                  latestUnseen: null,
                  unseenCount: row.unseenCount > 0 ? row.unseenCount - 1 : 0,
                )
              else
                row,
          ];
    }
    return result;
  }

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention(
    Set<String> beaconIds,
  ) async {
    myWorkAttentionCallCount++;
    myWorkAttentionCalls.add(beaconIds);
    if (myWorkAttentionDelay > Duration.zero) {
      await Future<void>.delayed(myWorkAttentionDelay);
    }
    final error = myWorkAttentionError;
    if (error != null) {
      throw error;
    }
    return myWorkAttentionResult;
  }

  @override
  Future<int> markSeenForBeacon(String beaconId) async {
    markSeenForBeaconCalls.add(beaconId);
    return 0;
  }

  @override
  Future<Set<String>> liveObligationBeacons() async => obligationBeaconIds;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => throw UnimplementedError();

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      throw UnimplementedError();

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async =>
      throw UnimplementedError();

  @override
  Future<int> markSeen(List<String> ids) async => throw UnimplementedError();

  @override
  Future<int> markUnseen(List<String> ids) async => throw UnimplementedError();

  @override
  Future<int> settle({required String receiptId, required String kind}) async {
    settleCalls.add(receiptId);
    return 1;
  }
}

class _StubAttentionAccounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}
