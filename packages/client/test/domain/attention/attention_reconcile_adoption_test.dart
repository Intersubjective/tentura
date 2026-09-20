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
import '../../support/test_realtime_sync.dart';
import 'attention_case_test_support.dart';

/// D15 step 6 — "replace client cached indicators with the returned
/// authoritative snapshot".
///
/// *Replace*, not merge. U17b's defect was a client overlay folded into a
/// server number; the same shape here would let a half-finished gesture
/// survive the repair that was meant to end it.
void main() {
  late AttentionCaseTestRepository repository;
  late AttentionCaseTestAccounts accounts;
  late TestRealtimeSyncPort realtimePort;
  late FeedSessionRegistry feedSessions;
  late AttentionCase attention;

  setUp(() {
    repository = AttentionCaseTestRepository();
    accounts = AttentionCaseTestAccounts();
    feedSessions = FeedSessionRegistry();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    attention = AttentionCase(
      repository,
      accounts,
      realtime.case_,
      noopBlockCase(),
      feedSessions,
      Logger('attention-reconcile-adoption-test'),
    );
  });

  tearDown(() async {
    await attention.dispose();
    await accounts.dispose();
    await realtimePort.dispose();
  });

  Future<void> signIn(List<AttentionReceipt> items) async {
    attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
    final head = Completer<AttentionFeed>();
    final summary = Completer<AttentionSurfaceSummary>();
    repository.pendingFetches.add(head);
    repository.pendingSurfaceSummaries.add(summary);
    accounts.emit('account-a');
    await attentionCaseTestSettle();
    head.complete(
      AttentionFeed(
        summary: AttentionSummary(unreadTotal: items.length),
        page: AttentionFeedPage(items: items),
      ),
    );
    summary.complete(const AttentionSurfaceSummary(forYouDot: true));
    await attentionCaseTestSettle();
    // Everything queued from here stays pending, so only the reconcile's own
    // adoption can move the numbers under test.
    repository.pendingSurfaceSummaries.add(
      Completer<AttentionSurfaceSummary>(),
    );
    repository.pendingFetches.add(Completer<AttentionFeed>());
  }

  const authoritative = AttentionSurfaceSummary(
    myDeskDot: true,
    myDeskCount: 4,
    forYouDot: true,
    forYouSweepEligible: true,
  );

  test(
    'reconcile adopts the returned summary whole, including the §6 indicators',
    () async {
      await signIn([_optional(id: 'r-1'), _optional(id: 'r-2')]);
      expect(
        attention.surfaceSummarySnapshot.myDeskCount,
        0,
        reason: 'the fixture starts where the adopted value is not already true',
      );

      final reconciled = Completer<AttentionReconcileResult>();
      repository.pendingReconciles.add(reconciled);
      unawaited(attention.reconcile().catchError((_) => _result()));
      await attentionCaseTestSettle();
      reconciled.complete(_result());
      await attentionCaseTestSettle();

      expect(attention.surfaceSummarySnapshot, authoritative);
    },
  );

  test(
    'an in-flight clear cannot survive a reconcile, nor re-corrupt its numbers',
    () async {
      // The stale-overlay hazard, end to end: a sweep is optimistically
      // applied (row off the list), the repair lands, and only then does the
      // sweep answer. A client that merged instead of adopting would show the
      // swept row still gone and the adopted summary disturbed afterwards.
      await signIn([_optional(id: 'r-1'), _optional(id: 'r-2')]);

      final sweep = Completer<AttentionDismissAllResult>();
      repository.pendingDismissAll.add(sweep);
      unawaited(attention.dismissAll().catchError((_) {}));
      await attentionCaseTestSettle();

      final session = attention.feedSession(
        AttentionFeedDestinationId.activityStream,
      );
      expect(
        session.pages[session.activeView]!.items
            .every((receipt) => receipt.isCleared),
        isTrue,
        reason: 'the optimistic sweep is the premise this test undoes',
      );
      // CHANGES IN U18c: an `activityUnreadTotal == 0` line stood here, and
      // the behaviour it asserted — an optimistic surface-summary delta — is
      // itself retired by this unit. Nothing replaces it: the optimistic
      // frame the user sees is the list above, and §6's indicators are
      // server-composed. The final assertion below still proves what this
      // test is about, that a late sweep answer cannot disturb the adopted
      // summary.

      final reconciled = Completer<AttentionReconcileResult>();
      repository.pendingReconciles.add(reconciled);
      unawaited(attention.reconcile().catchError((_) => _result()));
      await attentionCaseTestSettle();
      reconciled.complete(_result());
      await attentionCaseTestSettle();

      final adopted = attention.feedSession(
        AttentionFeedDestinationId.activityStream,
      );
      final items = adopted.pages[adopted.activeView]!.items;
      expect(
        items.map((receipt) => receipt.id),
        ['r-1', 'r-2'],
        reason: 'both rows are back: the server says nothing was cleared',
      );
      expect(
        items.every((receipt) => !receipt.isCleared),
        isTrue,
        reason: 'the optimistic clear overlay is dropped, not merged',
      );
      expect(attention.surfaceSummarySnapshot, authoritative);

      // Now the sweep answers, late.
      sweep.complete(
        const AttentionDismissAllResult(
          operationId: 'op',
          status: AttentionOperationStatus.complete,
          appliedReceiptIds: ['r-1'],
          appliedCount: 1,
        ),
      );
      await attentionCaseTestSettle();

      expect(
        attention.surfaceSummarySnapshot,
        authoritative,
        reason: 'a withdrawn operation may not post deltas onto the adopted '
            'snapshot afterwards',
      );
    },
  );
}

AttentionReconcileResult _result() => const AttentionReconcileResult(
  summary: AttentionSurfaceSummary(
    myDeskDot: true,
    myDeskCount: 4,
    forYouDot: true,
    forYouSweepEligible: true,
  ),
  createdObligationCount: 1,
  settledObligationCount: 2,
);

AttentionReceipt _optional({required String id}) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: 'Title $id',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
);
