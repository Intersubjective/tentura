import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import 'attention_case_test_support.dart';

/// U13c step 1 — a child × inside a grouped card must update the card's
/// **preview and its counts**. Before this unit the ack/clear stores only ever
/// saw top-level feed ids and silently skipped unknown child ids (U10b), so a
/// dismissed event stayed in the preview and the counts never moved.
void main() {
  late _GroupRepository repository;
  late AttentionCaseTestAccounts accounts;
  late TestRealtimeSyncPort realtimePort;
  late AttentionCase attention;

  AttentionReceipt child(String id, {bool seen = false}) =>
      attentionCaseTestReceipt(id: id).copyWith(
        beaconId: 'B1',
        seenAt: seen ? DateTime.utc(2026, 1, 2) : null,
      );

  AttentionReceipt group({
    required List<AttentionReceipt> children,
    int? eventTotal,
    int? eventUnseenCount,
  }) =>
      attentionCaseTestReceipt(id: 'beacon:B1').copyWith(
        beaconId: 'B1',
        itemKind: AttentionItemKind.requestActivity,
        eventTotal: eventTotal ?? children.length,
        eventUnseenCount: eventUnseenCount ??
            children.where((event) => !event.isSeen).length,
        eventsPreview: children,
      );

  Future<void> signIn(List<AttentionReceipt> items) async {
    attention.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();
    repository.completeFetches(items);
    await attentionCaseTestSettle();
  }

  AttentionReceipt row(String id) =>
      (attention
              .feedSession(attentionCaseTestFeedDest)
              .pages[AttentionView.all]
              ?.items ??
          const <AttentionReceipt>[])
          .firstWhere((item) => item.id == id);

  setUp(() {
    repository = _GroupRepository();
    accounts = AttentionCaseTestAccounts();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    attention = AttentionCase(
      repository,
      accounts,
      realtime.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('AttentionGroupProjectionTest'),
      qaLatencyMeasurementEnabled: false,
    );
  });

  tearDown(() async {
    await attention.dispose();
    await accounts.dispose();
    await realtimePort.dispose();
  });

  test('dismissing one child updates the card preview and its counts',
      () async {
    await signIn([
      group(
        children: [child('e-1'), child('e-2'), child('e-3', seen: true)],
      ),
    ]);

    expect(row('beacon:B1').eventsPreview, hasLength(3));
    expect(row('beacon:B1').eventTotal, 3);
    expect(row('beacon:B1').eventUnseenCount, 2);

    repository.snapshot = const AttentionClearSnapshot(
      snapshotToken: 'snap-1',
      receiptIds: ['e-1'],
    );
    await attention.clearReceipt(receiptId: 'e-1');
    await attentionCaseTestSettle();

    final projected = row('beacon:B1');
    expect(
      projected.eventsPreview.map((event) => event.id),
      ['e-2', 'e-3'],
      reason: 'the dismissed event leaves the preview',
    );
    expect(projected.eventTotal, 2, reason: 'the total follows the preview');
    expect(
      projected.eventUnseenCount,
      1,
      reason: 'an unseen event was dismissed, so the unseen count drops too',
    );
  });

  test('dismissing a seen child leaves the unseen count alone', () async {
    await signIn([
      group(children: [child('e-1'), child('e-2', seen: true)]),
    ]);
    repository.snapshot = const AttentionClearSnapshot(
      snapshotToken: 'snap-2',
      receiptIds: ['e-2'],
    );
    await attention.clearReceipt(receiptId: 'e-2');
    await attentionCaseTestSettle();

    expect(row('beacon:B1').eventTotal, 1);
    expect(row('beacon:B1').eventUnseenCount, 1);
  });

  test('a child id is known to the case, so its surface delta is counted',
      () async {
    await signIn([
      group(children: [child('e-1'), child('e-2')]),
    ]);
    expect(attention.knowsReceipt('e-1'), isTrue);
  });

  /// U13c remediation — the two indexes are load-bearing, not decorative.
  /// `dismissAll` sweeps **top-level rows only**: a grouped card and the
  /// children indexed out of its preview share one surface, so folding
  /// `_childReceiptsById` into the sweep's membership would decrement that
  /// surface once per child on top of the parent row.
  test('dismissAll decrements a grouped card\'s surface exactly once',
      () async {
    repository.activityUnreadTotal = 3;
    await signIn([
      group(children: [child('e-1'), child('e-2')]),
    ]);
    expect(
      (await attention.surfaceSummary.first).activityUnreadTotal,
      3,
      reason: 'the server total the optimistic delta is applied to',
    );

    repository.holdDismissAll = true;
    unawaited(attention.dismissAll());
    await attentionCaseTestSettle();

    expect(
      (await attention.surfaceSummary.first).activityUnreadTotal,
      2,
      reason: 'one card swept is one decrement — not one per indexed child',
    );

    repository.releaseDismissAll();
    await attentionCaseTestSettle();
  });
}

final class _GroupRepository extends AttentionRepositoryFake {
  final List<Completer<AttentionFeed>> _pendingFetches = [];

  AttentionClearSnapshot snapshot = const AttentionClearSnapshot(
    snapshotToken: 'snap-1',
  );

  int activityUnreadTotal = 0;
  bool holdDismissAll = false;
  final List<Completer<AttentionDismissAllResult>> _pendingSweeps = [];

  void releaseDismissAll() {
    final pending = List.of(_pendingSweeps);
    _pendingSweeps.clear();
    for (final completer in pending) {
      completer.complete(
        const AttentionDismissAllResult(
          operationId: 'sweep-1',
          status: AttentionOperationStatus.complete,
        ),
      );
    }
  }

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async =>
      AttentionSurfaceSummary(
        activityUnreadTotal: activityUnreadTotal,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
      );

  @override
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
  }) {
    if (!holdDismissAll) {
      return Future.value(
        AttentionDismissAllResult(
          operationId: operationId,
          status: AttentionOperationStatus.complete,
        ),
      );
    }
    final completer = Completer<AttentionDismissAllResult>();
    _pendingSweeps.add(completer);
    return completer.future;
  }

  void completeFetches(List<AttentionReceipt> items) {
    final pending = List.of(_pendingFetches);
    _pendingFetches.clear();
    for (final completer in pending) {
      completer.complete(
        AttentionFeed(
          summary: AttentionSummary(unreadTotal: items.length),
          page: AttentionFeedPage(items: items),
        ),
      );
    }
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) {
    final completer = Completer<AttentionFeed>();
    _pendingFetches.add(completer);
    return completer.future;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => const {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markSeen(List<String> ids) async => ids.length;

  @override
  Future<int> markUnseen(List<String> ids) async => ids.length;

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;

  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async => snapshot;

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) async => AttentionClearResult(
    operationId: operationId,
    status: AttentionOperationStatus.complete,
    appliedReceiptIds: snapshot.receiptIds,
  );
}