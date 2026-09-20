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

void main() {
  late _ClearRepository repository;
  late AttentionCaseTestAccounts accounts;
  late TestRealtimeSyncPort realtimePort;
  late AttentionCase attention;

  AttentionCase buildCase(_ClearRepository repo) => AttentionCase(
    repo,
    accounts,
    buildTestRealtimeSync().case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('AttentionClearCaseTest'),
    qaLatencyMeasurementEnabled: false,
  );

  Future<void> signIn(AttentionCase target, {
    List<AttentionReceipt>? items,
  }) async {
    target.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();
    repository.completeFetches(items ?? _threeReceipts);
    await attentionCaseTestSettle();
  }

  List<AttentionReceipt> pageItems(AttentionCase target) =>
      target.feedSession(attentionCaseTestFeedDest).pages[AttentionView.all]
          ?.items ??
      const [];

  Set<String> clearedIds(AttentionCase target) => {
    for (final item in pageItems(target))
      if (item.isCleared) item.id,
  };

  setUp(() {
    repository = _ClearRepository();
    accounts = AttentionCaseTestAccounts();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    attention = buildCase(repository);
  });

  tearDown(() async {
    await attention.dispose();
    await accounts.dispose();
    await realtimePort.dispose();
  });

  test('a partial clear commits only the applied members', () async {
    await signIn(attention);
    repository.snapshot = const AttentionClearSnapshot(
      snapshotToken: 'snap-1',
      receiptIds: ['r-1', 'r-2', 'r-3'],
    );
    repository.clearResult = (operationId) => AttentionClearResult(
      operationId: operationId,
      status: AttentionOperationStatus.partial,
      appliedReceiptIds: const ['r-1'],
      skippedReceiptIds: const ['r-2'],
      deniedReceiptIds: const ['r-3'],
    );
    final result = await attention.clearRequestOpen(beaconId: 'B1');
    await attentionCaseTestSettle();

    expect(result.status, AttentionOperationStatus.partial);
    expect(result.isComplete, isFalse);
    expect(clearedIds(attention), {'r-1'});
  });

  test('a partial sweep leaves skipped and pending members untouched',
      () async {
    await signIn(attention);
    repository.dismissAllResult = (operationId) => AttentionDismissAllResult(
      operationId: operationId,
      status: AttentionOperationStatus.partial,
      appliedReceiptIds: const ['r-1'],
      appliedCount: 1,
      skipped: const [
        AttentionSweepMember(
          id: 'r-2',
          kind: AttentionSweepMemberKind.receipt,
          reason: AttentionSweepSkipReason.awaitingDecision,
        ),
      ],
      pendingCount: 1,
    );
    final result = await attention.dismissAll();
    await attentionCaseTestSettle();

    expect(result.isComplete, isFalse, reason: 'pendingCount > 0');
    expect(result.needsResume, isTrue);
    expect(clearedIds(attention), {'r-1'});
  });

  test('a failed clear rolls its own optimism back and reports the failure',
      () async {
    await signIn(attention);
    repository.snapshot = const AttentionClearSnapshot(
      snapshotToken: 'snap-1',
      receiptIds: ['r-1'],
    );
    repository.clearError = StateError('offline');

    await expectLater(
      attention.clearReceipt(receiptId: 'r-1'),
      throwsA(isA<StateError>()),
    );
    await attentionCaseTestSettle();
    expect(clearedIds(attention), isEmpty);
  });

  test('a page fetch started before a clear cannot overwrite its result',
      () async {
    // Both the sign-in summary fetch and a head refresh are left in flight,
    // so that they land only after the clear has committed.
    repository.holdSummaries = true;
    await signIn(attention);
    expect(attention.snapshot.summary.unreadTotal, 3);
    unawaited(attention.refresh(destinationId: attentionCaseTestFeedDest));
    await attentionCaseTestSettle();

    repository.snapshot = const AttentionClearSnapshot(
      snapshotToken: 'snap-1',
      receiptIds: ['r-1', 'r-2', 'r-3'],
    );
    repository.clearResult = (operationId) => AttentionClearResult(
      operationId: operationId,
      status: AttentionOperationStatus.complete,
      appliedReceiptIds: const ['r-1', 'r-2', 'r-3'],
    );
    await attention.clearRequestOpen(beaconId: 'B1');
    await attentionCaseTestSettle();
    expect(clearedIds(attention), {'r-1', 'r-2', 'r-3'});
    expect(attention.snapshot.summary.unreadTotal, 0);

    // The stale page and the stale summary land now, both describing the
    // world as it was before the clear. Neither may win.
    repository.completeFirstFetch(_threeReceipts, unread: 3);
    // CHANGES IN U18c: the stale summary used to carry
    // `activityUnreadTotal: 3`. It carries a lit `forYouDot` instead — a
    // §6 field, and still a value the post-clear world does not have.
    repository.completeFirstSummary(
      const AttentionSurfaceSummary(forYouDot: true),
    );
    await attentionCaseTestSettle();

    expect(
      attention.snapshot.summary.unreadTotal,
      0,
      reason: 'a page fetched before the clear cannot restore its total',
    );
    final surface = await attention.surfaceSummary.first;
    expect(
      surface.forYouDot,
      isFalse,
      reason: 'nor can a summary fetched before the clear',
    );
    expect(clearedIds(attention), {'r-1', 'r-2', 'r-3'});
  });

  test('a second session clearing the same rows converges, never resurrects',
      () async {
    await signIn(attention);
    final second = buildCase(repository);
    second.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();
    repository.completeFetches(_threeReceipts);
    await attentionCaseTestSettle();

    repository.snapshot = const AttentionClearSnapshot(
      snapshotToken: 'snap-1',
      receiptIds: ['r-1'],
    );
    repository.clearResult = (operationId) => AttentionClearResult(
      operationId: operationId,
      status: AttentionOperationStatus.complete,
      appliedReceiptIds: const ['r-1'],
    );
    await attention.clearReceipt(receiptId: 'r-1');
    await attentionCaseTestSettle();

    // The second device clears the same row; the server already applied it,
    // so it answers with a skip, not an apply.
    repository.clearResult = (operationId) => AttentionClearResult(
      operationId: operationId,
      status: AttentionOperationStatus.partial,
      skippedReceiptIds: const ['r-1'],
    );
    await second.clearReceipt(receiptId: 'r-1');
    await attentionCaseTestSettle();
    // Both sessions refetch; the server's truth is that r-1 is cleared.
    repository.completeFetches(_threeReceiptsWithCleared);
    await attentionCaseTestSettle();

    expect(clearedIds(attention), {'r-1'});
    expect(
      clearedIds(second),
      {'r-1'},
      reason: 'rolling back its own skip must not un-clear server truth',
    );
    await second.dispose();
  });

  group('the sweep reward channel (D18)', () {
    // The reward the cleared state may show is a *presentation* of the last
    // explicit sweep, so the case publishes the sweep's own result and
    // decides nothing about copy. What it does decide is when the reward is
    // no longer about anything: a sweep that threw, an undo that put the rows
    // back, and an account that is no longer this one.
    AttentionDismissAllResult complete(String operationId) =>
        AttentionDismissAllResult(
          operationId: operationId,
          status: AttentionOperationStatus.complete,
          appliedReceiptIds: const ['r-1'],
          appliedCount: 1,
          undoToken: 'undo-1',
          undoDeadline: DateTime.utc(2026, 9, 19, 10),
        );

    test('a complete sweep publishes what it achieved', () async {
      await signIn(attention);
      repository.dismissAllResult = complete;

      final seen = <AttentionDismissAllResult?>[];
      final sub = attention.lastSweepOutcome.listen(seen.add);
      addTearDown(sub.cancel);
      await attentionCaseTestSettle();
      expect(seen, [null], reason: 'no sweep yet is no reward');

      await attention.dismissAll();
      await attentionCaseTestSettle();

      expect(seen.last?.appliedCount, 1);
      expect(seen.last?.isComplete, isTrue);
    });

    test('a partial sweep is published as partial, not hidden', () async {
      // The presentation withdraws the celebration; the case must not lie
      // about the sweep to make that happen, or a resumed sweep would have
      // nothing to report either.
      await signIn(attention);
      repository.dismissAllResult = (operationId) => AttentionDismissAllResult(
        operationId: operationId,
        status: AttentionOperationStatus.partial,
        appliedReceiptIds: const ['r-1'],
        appliedCount: 1,
        pendingCount: 2,
      );

      await attention.dismissAll();
      await attentionCaseTestSettle();

      final published = await attention.lastSweepOutcome.first;
      expect(published?.needsResume, isTrue);
      expect(published?.appliedCount, 1);
    });

    test('a sweep that threw leaves no reward behind', () async {
      await signIn(attention);
      repository.dismissAllResult = complete;
      await attention.dismissAll();
      await attentionCaseTestSettle();
      expect(await attention.lastSweepOutcome.first, isNotNull);

      repository.dismissAllError = StateError('offline');
      await expectLater(attention.dismissAll(), throwsA(isA<StateError>()));
      await attentionCaseTestSettle();

      expect(
        await attention.lastSweepOutcome.first,
        isNull,
        reason: 'a failed sweep may not leave the previous count on screen',
      );
    });

    test('an undo takes the reward back with the rows', () async {
      await signIn(attention);
      repository.dismissAllResult = complete;
      repository.undoResult = (operationId) => AttentionUndoResult(
        operationId: operationId,
        status: AttentionOperationStatus.complete,
        restoredReceiptIds: const ['r-1'],
      );

      final sweep = await attention.dismissAll();
      await attentionCaseTestSettle();
      expect(await attention.lastSweepOutcome.first, isNotNull);

      await attention.undoDismissAll(
        operationId: sweep.operationId,
        undoToken: sweep.undoToken!,
      );
      await attentionCaseTestSettle();

      expect(
        await attention.lastSweepOutcome.first,
        isNull,
        reason: 'undoing the sweep un-clears what the number counted',
      );
    });

    test('a refused undo leaves the reward standing', () async {
      await signIn(attention);
      repository.dismissAllResult = complete;
      repository.undoResult = (operationId) => AttentionUndoResult(
        operationId: operationId,
        status: AttentionOperationStatus.denied,
        refusal: AttentionUndoRefusal.expired,
      );

      final sweep = await attention.dismissAll();
      await attentionCaseTestSettle();
      await attention.undoDismissAll(
        operationId: sweep.operationId,
        undoToken: sweep.undoToken!,
      );
      await attentionCaseTestSettle();

      expect(
        (await attention.lastSweepOutcome.first)?.appliedCount,
        1,
        reason: 'nothing moved, so the rows are still cleared',
      );
    });

    test('another account inherits no reward', () async {
      await signIn(attention);
      repository.dismissAllResult = complete;
      await attention.dismissAll();
      await attentionCaseTestSettle();
      expect(await attention.lastSweepOutcome.first, isNotNull);

      accounts.emit('account-2');
      await attentionCaseTestSettle();

      expect(await attention.lastSweepOutcome.first, isNull);
    });
  });

  test('an expired undo surfaces as a refusal and restores nothing', () async {
    await signIn(attention);
    repository.undoResult = (operationId) => AttentionUndoResult(
      operationId: operationId,
      status: AttentionOperationStatus.denied,
      refusal: AttentionUndoRefusal.expired,
    );
    repository.dismissAllResult = (operationId) => AttentionDismissAllResult(
      operationId: operationId,
      status: AttentionOperationStatus.complete,
      appliedReceiptIds: const ['r-1'],
      appliedCount: 1,
      undoToken: 'undo-1',
      undoDeadline: DateTime.utc(2026, 9, 19, 10),
    );
    final sweep = await attention.dismissAll();
    await attentionCaseTestSettle();
    expect(clearedIds(attention), {'r-1'});

    final undo = await attention.undoDismissAll(
      operationId: sweep.operationId,
      undoToken: sweep.undoToken!,
    );
    await attentionCaseTestSettle();

    expect(undo.isRefused, isTrue);
    expect(undo.refusal, AttentionUndoRefusal.expired);
    expect(undo.isComplete, isFalse);
    expect(
      clearedIds(attention),
      {'r-1'},
      reason: 'a refused undo is not a silent success',
    );
  });

  test('an undo restores only the members it actually put back', () async {
    await signIn(attention);
    repository.dismissAllResult = (operationId) => AttentionDismissAllResult(
      operationId: operationId,
      status: AttentionOperationStatus.complete,
      appliedReceiptIds: const ['r-1', 'r-2'],
      appliedCount: 2,
      undoToken: 'undo-1',
      undoDeadline: DateTime.utc(2026, 9, 19, 10),
    );
    final sweep = await attention.dismissAll();
    await attentionCaseTestSettle();
    expect(clearedIds(attention), {'r-1', 'r-2'});

    repository.undoResult = (operationId) => AttentionUndoResult(
      operationId: operationId,
      status: AttentionOperationStatus.partial,
      restoredReceiptIds: const ['r-1'],
      skipped: const [
        AttentionUndoMember(
          id: 'r-2',
          kind: AttentionSweepMemberKind.receipt,
          reason: AttentionUndoSkipReason.clearedByAnotherOperation,
        ),
      ],
    );
    final undo = await attention.undoDismissAll(
      operationId: sweep.operationId,
      undoToken: sweep.undoToken!,
    );
    await attentionCaseTestSettle();

    expect(undo.isComplete, isFalse);
    expect(clearedIds(attention), {'r-2'});
  });

  test('reconcile publishes the returned summary and refetches', () async {
    await signIn(attention);
    final fetchesBefore = repository.fetchCalls;
    repository.reconcileResult = const AttentionReconcileResult(
      summary: AttentionSurfaceSummary(myDeskCount: 3),
      unrepairableObligationCount: 1,
    );
    final summaries = <AttentionSurfaceSummary>[];
    final sub = attention.surfaceSummary.listen(summaries.add);

    final result = await attention.reconcile();
    await attentionCaseTestSettle();

    expect(result.isFullyRepaired, isFalse);
    expect(
      summaries.any((summary) => summary.myDeskCount == 3),
      isTrue,
      reason: 'the returned summary is adopted immediately',
    );
    expect(
      repository.fetchCalls,
      greaterThan(fetchesBefore),
      reason: 'the server does not invalidate sessions — the client refetches',
    );
    await sub.cancel();
  });
}

final _threeReceipts = [
  for (final id in ['r-1', 'r-2', 'r-3']) attentionCaseTestReceipt(id: id),
];

final _threeReceiptsWithCleared = [
  attentionCaseTestReceipt(id: 'r-1').copyWith(
    clearedAt: DateTime.utc(2026, 9, 19),
    clearReason: AttentionClearReason.explicit,
  ),
  attentionCaseTestReceipt(id: 'r-2'),
  attentionCaseTestReceipt(id: 'r-3'),
];

final class _ClearRepository extends AttentionRepositoryFake {
  final List<Completer<AttentionFeed>> _pendingFetches = [];
  int fetchCalls = 0;

  AttentionClearSnapshot snapshot = const AttentionClearSnapshot(
    snapshotToken: 'snap-1',
  );
  Object? clearError;
  Object? dismissAllError;
  AttentionClearResult Function(String operationId)? clearResult;
  AttentionDismissAllResult Function(String operationId)? dismissAllResult;
  AttentionUndoResult Function(String operationId)? undoResult;
  AttentionReconcileResult? reconcileResult;

  final List<Completer<AttentionSurfaceSummary>> _pendingSummaries = [];
  bool holdSummaries = false;

  /// Completes exactly one in-flight fetch, leaving any later one pending —
  /// which is how a stale response is made to land *after* a mutation.
  void completeFirstFetch(List<AttentionReceipt> items, {int? unread}) {
    final completer = _pendingFetches.removeAt(0);
    completer.complete(
      AttentionFeed(
        summary: AttentionSummary(unreadTotal: unread ?? items.length),
        page: AttentionFeedPage(items: items),
      ),
    );
  }

  void completeFirstSummary(AttentionSurfaceSummary summary) =>
      _pendingSummaries.removeAt(0).complete(summary);

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() {
    if (!holdSummaries) return super.surfaceSummary();
    final completer = Completer<AttentionSurfaceSummary>();
    _pendingSummaries.add(completer);
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
    fetchCalls++;
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
  }) async {
    if (clearError != null) throw clearError!;
    return clearResult?.call(operationId) ??
        AttentionClearResult(
          operationId: operationId,
          status: AttentionOperationStatus.complete,
          appliedReceiptIds: snapshot.receiptIds,
        );
  }

  @override
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
  }) async {
    final error = dismissAllError;
    if (error != null) throw error;
    return dismissAllResult?.call(operationId) ??
        AttentionDismissAllResult(
          operationId: operationId,
          status: AttentionOperationStatus.complete,
        );
  }

  @override
  Future<AttentionUndoResult> undo({
    required String operationId,
    required String undoToken,
  }) async =>
      undoResult?.call(operationId) ??
      AttentionUndoResult(
        operationId: operationId,
        status: AttentionOperationStatus.complete,
      );

  @override
  Future<AttentionReconcileResult> reconcile() async =>
      reconcileResult ??
      const AttentionReconcileResult(
        summary: AttentionSurfaceSummary(
        ),
      );
}
