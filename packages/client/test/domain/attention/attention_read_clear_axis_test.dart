import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/attention_group_projection.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/attention_axis_contract.dart';
import '../../support/test_realtime_sync.dart';
import 'attention_case_test_support.dart';

/// R2 — reading must stop moving the clear axis, and the optimistic sweep
/// must use genuinely dismissible membership (owner decision A).
///
/// Every quantity asserted here is a quantity the **server** defines. None of
/// them is hand-built: they come from
/// `docs/contracts/attention-active-attention-axis.json`, which transcribes
/// `AttentionDismissibleSql` and the totals
/// `attention_active_attention_axis_pg_test.dart` asserts against real
/// Postgres. The first test in this file fails if that transcription and the
/// server source ever stop agreeing.
void main() {
  final contract = AttentionAxisContract.load();

  test('the shared axis contract still matches the server SQL', () {
    contract.assertServerPredicatesUnchanged();
  });

  group('reading does not move the clear axis', () {
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
        Logger('attention-read-clear-axis-test'),
      );
    });

    tearDown(() async {
      await attention.dispose();
      await accounts.dispose();
      await realtimePort.dispose();
    });

    /// Signs in with [items] on the activity stream and the server's
    /// authoritative surface totals, then stops the clock: every later
    /// summary read is held so a test can sample the intermediate frame.
    Future<void> signIn({
      required List<AttentionReceipt> items,
      required int activityTotal,
      required int myWorkTotal,
      int needsYouTotal = 0,
    }) async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      final head = Completer<AttentionFeed>();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.add(head);
      repository.pendingSurfaceSummaries.add(summary);
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      head.complete(
        AttentionFeed(
          summary: AttentionSummary(
            unreadTotal: activityTotal + myWorkTotal,
            needsYouTotal: needsYouTotal,
          ),
          page: AttentionFeedPage(items: items),
        ),
      );
      summary.complete(
        AttentionSurfaceSummary(
          activityUnreadTotal: activityTotal,
          myWorkUnreadTotal: myWorkTotal,
          needsYouTotal: needsYouTotal,
        ),
      );
      await attentionCaseTestSettle();
      // Every refresh from here on stays pending, so nothing the server says
      // later can paper over the optimistic frame under test.
      repository.pendingSurfaceSummaries.add(
        Completer<AttentionSurfaceSummary>(),
      );
      repository.pendingFetches.add(Completer<AttentionFeed>());
    }

    test('markSeen leaves the surface totals where the server put them',
        () async {
      // The server's own case: seen but uncleared still asks for attention.
      final axisCase =
          contract.axisCase('seen but uncleared optional receipt still asks '
              'for attention');
      final expected = axisCase['myWorkUnreadTotal']! as int;

      await signIn(
        items: [_optional(id: 'r-1', surface: AttentionSurface.myWork)],
        activityTotal: 0,
        myWorkTotal: expected,
      );

      final commit = Completer<int>();
      repository.pendingMarkSeen.add(commit);
      unawaited(attention.markSeen(const ['r-1']).catchError((_) {}));
      await attentionCaseTestSettle();

      expect(
        attention.surfaceSummarySnapshot.myWorkUnreadTotal,
        expected,
        reason: axisCase['note'] as String? ??
            'reading is not clearing (D02)',
      );
      expect(
        attention.snapshot.summary.unreadTotal,
        expected,
        reason: 'unreadTotal is an active-attention count on the server too',
      );
      commit.complete(1);
      await attentionCaseTestSettle();
    });

    test('markAllSeen does not zero a surface it only read', () async {
      await signIn(
        items: [
          _optional(id: 'r-1'),
          _optional(id: 'r-2'),
        ],
        activityTotal: 2,
        myWorkTotal: 3,
      );

      final commit = Completer<int>();
      repository.pendingMarkAllSeen.add(commit);
      unawaited(attention.markAllSeen().catchError((_) {}));
      await attentionCaseTestSettle();

      expect(
        attention.surfaceSummarySnapshot.activityUnreadTotal,
        2,
        reason: 'markAllSeen is a read; it clears nothing (§3, D02)',
      );
      expect(attention.surfaceSummarySnapshot.myWorkUnreadTotal, 3);
      commit.complete(2);
      await attentionCaseTestSettle();
    });

    test(
      'the optimistic sweep never removes what awaits a decision (owner '
      'decision A)',
      () async {
        // One genuinely dismissible row, and four the server's Set R / Set O
        // exclude. The excluded ones are exactly the list in the contract.
        final items = [
          _optional(id: 'sweepable'),
          _obligation(id: 'obligation'),
          _optional(id: 'desk-work', surface: AttentionSurface.myWork),
          _pendingForward(id: 'unanswered-forward'),
          _optional(id: 'relay-shell', presentationKey: 'relay_received'),
        ];
        await signIn(items: items, activityTotal: 4, myWorkTotal: 1);

        final held = Completer<AttentionDismissAllResult>();
        repository.pendingDismissAll.add(held);
        unawaited(attention.dismissAll().catchError((_) {}));
        await attentionCaseTestSettle();

        // The intermediate frame — the only frame the user actually sees
        // before the server answers.
        final session =
            attention.feedSession(AttentionFeedDestinationId.activityStream);
        final page = session.pages[session.activeView]!;
        final cleared = {
          for (final r in page.items)
            if (r.isCleared) r.id,
        };
        expect(
          cleared,
          {'sweepable'},
          reason: 'Set R is: activity surface, not an obligation, uncleared, '
              'not a relay_received shell — and Set O excludes anything in '
              'eligible_pinned, i.e. an unanswered forward',
        );
        expect(
          attention.surfaceSummarySnapshot.activityUnreadTotal,
          3,
          reason: 'exactly one dismissible row left the activity total',
        );
        expect(
          attention.surfaceSummarySnapshot.myWorkUnreadTotal,
          1,
          reason: 'a sweep of For You never touches My Desk',
        );

        held.complete(
          const AttentionDismissAllResult(
            operationId: 'op',
            status: AttentionOperationStatus.complete,
            appliedReceiptIds: ['sweepable'],
            appliedCount: 1,
          ),
        );
        await attentionCaseTestSettle();
      },
    );
  });

  group('group projection counts the clear axis, not the read axis', () {
    test('a child read optimistically still counts', () {
      final children = [_optional(id: 'c-1'), _optional(id: 'c-2')];
      final projection = projectAttentionGroup(
        eventTotal: 2,
        eventUnseenCount: 2,
        eventsPreview: children,
        unseen: true,
        // The caller's read overlay: c-1 was just marked seen locally.
        overlay: (child) => child.id == 'c-1'
            ? child.copyWith(seenAt: DateTime.utc(2026, 2))
            : child,
      );
      expect(
        projection.eventUnseenCount,
        2,
        reason: 'the server defines eventUnseenCount as active *optional* '
            'attention; seen_at is not in it',
      );
      expect(projection.unseen, isTrue);
    });

    test('a cleared child is the only thing that lowers the count', () {
      final children = [
        _optional(id: 'c-1').copyWith(
          seenAt: DateTime.utc(2026, 2),
          clearedAt: DateTime.utc(2026, 3),
        ),
        _optional(id: 'c-2').copyWith(seenAt: DateTime.utc(2026, 2)),
      ];
      final projection = projectAttentionGroup(
        eventTotal: 2,
        eventUnseenCount: 2,
        eventsPreview: children,
        unseen: true,
        overlay: (child) => child,
      );
      expect(projection.eventTotal, 1);
      expect(projection.eventUnseenCount, 1);
      expect(projection.eventsPreview.map((c) => c.id), ['c-2']);
    });
  });
}

AttentionReceipt _base({
  required String id,
  AttentionSurface surface = AttentionSurface.activity,
}) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: id,
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  beaconId: 'B$id',
  surface: surface,
);

AttentionReceipt _optional({
  required String id,
  AttentionSurface surface = AttentionSurface.activity,
  String? presentationKey,
}) => _base(id: id, surface: surface).copyWith(
  presentationKey: presentationKey,
);

AttentionReceipt _obligation({required String id}) =>
    _base(id: id).copyWith(requiresAction: true);

AttentionReceipt _pendingForward({required String id}) => _base(id: id)
    .copyWith(itemKind: AttentionItemKind.forward);
