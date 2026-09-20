import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import 'attention_case_test_support.dart';

/// U13c step 3 — realtime invalidation for clear state, outcome generation and
/// **surface moves**.
///
/// The surface move is the subtle one. When responsibility changes, a Request
/// leaves For You and lands on My Desk. The old surface must drop it and the
/// new one must gain it with no moment in between where it is on both, or on
/// neither -- so what is asserted here is the transition, sampled at every
/// emission, not the two endpoints.
void main() {
  late _RealtimeRepository repository;
  late AttentionCaseTestAccounts accounts;
  late TestRealtimeSyncPort realtimePort;
  late AttentionCase attention;

  AttentionReceipt row(String beaconId) =>
      attentionCaseTestReceipt(id: 'row-$beaconId').copyWith(
        beaconId: beaconId,
        itemKind: AttentionItemKind.requestActivity,
      );

  setUp(() {
    repository = _RealtimeRepository();
    accounts = AttentionCaseTestAccounts();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    attention = AttentionCase(
      repository,
      accounts,
      realtime.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('AttentionRealtimeInvalidationTest'),
      qaLatencyMeasurementEnabled: false,
    );
  });

  tearDown(() async {
    await attention.dispose();
    await accounts.dispose();
    await realtimePort.dispose();
  });

  test('a surface move never shows the Request on both surfaces, or neither',
      () async {
    // For You holds B1; the account summary counts it there.
    repository.feedRows = [row('B1')];
    repository.summary = const AttentionSurfaceSummary(forYouDot: true);
    attention.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();

    // CHANGES IN U18c: the two legacy totals this record sampled are retired.
    // §6's dots say the same thing the two counts said here — "the account
    // summary places B1 on this surface" — and are what the nav actually
    // reads.
    ({bool onForYou, bool forYouDot, bool deskDot}) sample() {
      final items = attention
              .feedSession(attentionCaseTestFeedDest)
              .pages[AttentionView.all]
              ?.items ??
          const <AttentionReceipt>[];
      return (
        onForYou: items.any((item) => item.beaconId == 'B1'),
        forYouDot: attention.surfaceSummarySnapshot.forYouDot,
        deskDot: attention.surfaceSummarySnapshot.myDeskDot,
      );
    }

    expect(sample(), (onForYou: true, forYouDot: true, deskDot: false));

    // Responsibility changed: the server now answers For You without B1 and
    // counts it on My Desk instead. The two answers are held apart on
    // purpose -- that gap is where a two-step refresh shows the broken
    // in-between state, and it is the transition this test is about.
    repository.feedRows = const [];
    repository.summary = const AttentionSurfaceSummary(
      myDeskDot: true,
      myDeskCount: 1,
    );
    repository.hold = true;
    realtimePort.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.beacon,
        aggregateId: 'B1',
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );
    await attentionCaseTestSettle();

    // The new counters land first; the page has not answered yet.
    repository.releaseSummaries();
    await attentionCaseTestSettle();
    final midway = sample();
    expect(
      midway.onForYou && midway.deskDot,
      isFalse,
      reason: 'on For You and already counted on My Desk at once: $midway',
    );
    expect(
      !midway.onForYou && midway.forYouDot,
      isFalse,
      reason: 'dropped from For You while still counted there: $midway',
    );

    repository.releaseFetches();
    await attentionCaseTestSettle();
    await attentionCaseTestSettle();

    final settled = sample();
    expect(settled.onForYou, isFalse);
    expect(settled.deskDot, isTrue);
    expect(settled.forYouDot, isFalse);
  });

  test('a surface move invalidates the Request for projection owners',
      () async {
    repository.feedRows = [row('B1')];
    attention.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();

    final invalidated = <String>[];
    final sub = attention.requestInvalidations.listen(invalidated.add);
    addTearDown(sub.cancel);

    realtimePort.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.beacon,
        aggregateId: 'B1',
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );
    await attentionCaseTestSettle();

    expect(invalidated, contains('B1'));
  });

  test('clearing a Request invalidates it, and an outcome hint invalidates too',
      () async {
    repository.feedRows = [row('B1')];
    attention.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();

    final invalidated = <String>[];
    final sub = attention.requestInvalidations.listen(invalidated.add);
    addTearDown(sub.cancel);

    repository.snapshot = const AttentionClearSnapshot(
      snapshotToken: 'snap-1',
      receiptIds: ['row-B1'],
    );
    await attention.clearRequestOpen(beaconId: 'B1');
    await attentionCaseTestSettle();
    expect(invalidated, contains('B1'));

    invalidated.clear();
    realtimePort.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.notification,
        aggregateId: 'n-1',
        operation: RealtimeOperation.insert,
        source: RealtimeChangeSource.serverInvalidation,
        childId: 'B2',
      ),
    );
    await attentionCaseTestSettle();
    expect(
      invalidated,
      contains('B2'),
      reason: 'outcome generation arrives as a notification hint',
    );
  });
}

final class _RealtimeRepository extends AttentionRepositoryFake {
  List<AttentionReceipt> feedRows = const [];
  AttentionSurfaceSummary summary = const AttentionSurfaceSummary(
  );
  AttentionClearSnapshot snapshot = const AttentionClearSnapshot(
    snapshotToken: 'snap-1',
  );

  bool hold = false;
  final List<Completer<AttentionFeed>> _heldFetches = [];
  final List<Completer<AttentionSurfaceSummary>> _heldSummaries = [];

  void releaseFetches() {
    final pending = List.of(_heldFetches);
    _heldFetches.clear();
    for (final completer in pending) {
      completer.complete(
        AttentionFeed(
          summary: AttentionSummary(unreadTotal: feedRows.length),
          page: AttentionFeedPage(items: feedRows),
        ),
      );
    }
  }

  void releaseSummaries() {
    final pending = List.of(_heldSummaries);
    _heldSummaries.clear();
    for (final completer in pending) {
      completer.complete(summary);
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
    if (hold) {
      final completer = Completer<AttentionFeed>();
      _heldFetches.add(completer);
      return completer.future;
    }
    return Future.value(
      AttentionFeed(
        summary: AttentionSummary(unreadTotal: feedRows.length),
        page: AttentionFeedPage(items: feedRows),
      ),
    );
  }

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() {
    if (hold) {
      final completer = Completer<AttentionSurfaceSummary>();
      _heldSummaries.add(completer);
      return completer.future;
    }
    return Future.value(summary);
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
