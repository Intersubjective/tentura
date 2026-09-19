import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';
import 'attention_case_test_support.dart';

const _surfaceSummaryZero = AttentionSurfaceSummary(
  activityUnreadTotal: 0,
  myWorkUnreadTotal: 0,
  needsYouTotal: 0,
);

AttentionSurfaceSummary _surfaceSummary({
  int activity = 0,
  int myWork = 0,
  int needsYou = 0,
}) => AttentionSurfaceSummary(
  activityUnreadTotal: activity,
  myWorkUnreadTotal: myWork,
  needsYouTotal: needsYou,
);

void main() {
  group('surfaceForDestination', () {
    test('maps activity stream to activity surface', () {
      expect(
        surfaceForDestination(AttentionFeedDestinationId.activityStream),
        AttentionSurface.activity,
      );
    });

    test('maps history to unscoped fetch', () {
      expect(surfaceForDestination(AttentionFeedDestinationId.history), isNull);
    });

    test('unknown destination ids use unscoped fetch', () {
      expect(surfaceForDestination('future_destination'), isNull);
    });
  });

  group('AttentionCase surface summary', () {
    late AttentionCaseTestRepository repository;
    late AttentionCaseTestAccounts accounts;
    late TestRealtimeSyncPort realtimePort;
    late RealtimeSyncCase realtimeCase;
    late FeedSessionRegistry feedSessions;
    late AttentionCase attention;
    late List<AttentionSurfaceSummary> surfaceSummaries;

    setUp(() {
      repository = AttentionCaseTestRepository();
      accounts = AttentionCaseTestAccounts();
      feedSessions = FeedSessionRegistry();
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      realtimeCase = realtime.case_;
      attention = AttentionCase(
        repository,
        accounts,
        realtimeCase,
        noopBlockCase(),
        feedSessions,
        Logger('attention-surfaces-test'),
      );
      surfaceSummaries = [];
      attention.surfaceSummary.listen(surfaceSummaries.add);
    });

    tearDown(() async {
      await attention.dispose();
      await accounts.dispose();
      await realtimePort.dispose();
    });

    Future<void> signInAndCompleteHead() async {
      final head = Completer<AttentionFeed>();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.add(head);
      repository.pendingSurfaceSummaries.add(summary);
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      head.complete(attentionCaseTestFeed());
      summary.complete(_surfaceSummary(activity: 1));
      await attentionCaseTestSettle();
      surfaceSummaries.clear();
    }

    test('refreshes on account change', () async {
      final head = Completer<AttentionFeed>();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.add(head);
      repository.pendingSurfaceSummaries.add(summary);
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(activity: 2));
      head.complete(attentionCaseTestFeed());
      await attentionCaseTestSettle();
      expect(surfaceSummaries, contains(_surfaceSummary(activity: 2)));
    });

    test('refreshes on notification events', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      await signInAndCompleteHead();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(summary);
      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.notification,
          aggregateId: 'account-a',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(myWork: 3));
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last, _surfaceSummary(myWork: 3));
    });

    test('refreshes on helpOffer events', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      await signInAndCompleteHead();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(summary);
      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.helpOffer,
          aggregateId: 'beacon-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(activity: 4));
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last, _surfaceSummary(activity: 4));
    });

    test('refreshes on inboxItem events', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      await signInAndCompleteHead();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(summary);
      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.inboxItem,
          aggregateId: 'beacon-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(activity: 5));
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last, _surfaceSummary(activity: 5));
    });

    test('refreshes on catch-up', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      await signInAndCompleteHead();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(summary);
      realtimePort.emitCatchUp();
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(needsYou: 2));
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last, _surfaceSummary(needsYou: 2));
    });

    test('refreshes on block changes', () async {
      final blockCase = ControllableBlockCase();
      final blockAttention = AttentionCase(
        repository,
        accounts,
        realtimeCase,
        blockCase,
        feedSessions,
        Logger('attention-surfaces-block'),
      );
      final blockSummaries = <AttentionSurfaceSummary>[];
      blockAttention.surfaceSummary.listen(blockSummaries.add);
      blockAttention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      addTearDown(blockAttention.dispose);
      addTearDown(blockCase.dispose);

      final head = Completer<AttentionFeed>();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.add(head);
      repository.pendingSurfaceSummaries.add(summary);
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      head.complete(attentionCaseTestFeed());
      summary.complete(_surfaceSummary());
      await attentionCaseTestSettle();
      blockSummaries.clear();

      final afterBlock = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(afterBlock);
      blockCase.emitBlock();
      await attentionCaseTestSettle();
      afterBlock.complete(_surfaceSummary(activity: 7));
      await attentionCaseTestSettle();
      expect(blockSummaries.last, _surfaceSummary(activity: 7));
    });

    test('refreshes after mark-seen ack', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      final initial = Completer<AttentionFeed>();
      final afterAckHead = Completer<AttentionFeed>();
      final initialSummary = Completer<AttentionSurfaceSummary>();
      final afterAckSummary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.addAll([initial, afterAckHead]);
      repository.pendingSurfaceSummaries.addAll([initialSummary, afterAckSummary]);
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      initial.complete(attentionCaseTestFeed());
      initialSummary.complete(_surfaceSummary(activity: 1));
      await attentionCaseTestSettle();

      final markSeen = Completer<int>();
      repository.pendingMarkSeen.add(markSeen);
      final command = attention.markSeen(['receipt-1']);
      await attentionCaseTestSettle();
      markSeen.complete(1);
      await command;
      await attentionCaseTestSettle();
      afterAckHead.complete(attentionCaseTestFeed(unread: 0));
      afterAckSummary.complete(_surfaceSummary());
      await attentionCaseTestSettle();
      expect(repository.surfaceSummaryCalls, greaterThanOrEqualTo(2));
      expect(surfaceSummaries.last, _surfaceSummary());
    });

    test('drops stale surface summary responses', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      final head = Completer<AttentionFeed>();
      final stale = Completer<AttentionSurfaceSummary>();
      final fresh = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.add(head);
      repository.pendingSurfaceSummaries.addAll([stale, fresh]);
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      head.complete(attentionCaseTestFeed());
      await attentionCaseTestSettle();

      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.notification,
          aggregateId: 'account-a',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();

      stale.complete(_surfaceSummary(activity: 99));
      fresh.complete(_surfaceSummary(activity: 1));
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last.activityUnreadTotal, 1);
    });

    test('helpOffer refreshes activity stream head only', () async {
      await attention.dispose();
      const streamDest = AttentionFeedDestinationId.activityStream;
      const historyDest = AttentionFeedDestinationId.history;
      final scopedAttention = AttentionCase(
        repository,
        accounts,
        realtimeCase,
        noopBlockCase(),
        feedSessions,
        Logger('attention-surfaces-help-offer'),
      );
      scopedAttention.attachFeedSession(streamDest);
      scopedAttention.attachFeedSession(historyDest);
      addTearDown(scopedAttention.dispose);

      final streamHead = Completer<AttentionFeed>();
      final historyHead = Completer<AttentionFeed>();
      final signInSummary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.addAll([streamHead, historyHead]);
      repository.pendingSurfaceSummaries.add(signInSummary);
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      streamHead.complete(attentionCaseTestFeed());
      historyHead.complete(attentionCaseTestFeed());
      signInSummary.complete(_surfaceSummary());
      await attentionCaseTestSettle();
      final fetchCallsBefore = repository.fetchCalls;

      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.helpOffer,
          aggregateId: 'beacon-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      expect(repository.fetchCalls, fetchCallsBefore + 1);
      expect(repository.fetches.last.surface, AttentionSurface.activity);
      expect(
        repository.fetches.last.view,
        AttentionView.all,
      );
    });

    test('activity stream fetch passes activity surface', () async {
      await attention.dispose();
      const streamDest = AttentionFeedDestinationId.activityStream;
      final streamOnly = AttentionCase(
        repository,
        accounts,
        realtimeCase,
        noopBlockCase(),
        feedSessions,
        Logger('attention-surfaces-stream-fetch'),
      );
      streamOnly.attachFeedSession(streamDest);
      addTearDown(streamOnly.dispose);

      final head = Completer<AttentionFeed>();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.add(head);
      repository.pendingSurfaceSummaries.add(summary);
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      expect(repository.fetches.single.surface, AttentionSurface.activity);
      head.complete(attentionCaseTestFeed());
      summary.complete(_surfaceSummary());
      await attentionCaseTestSettle();
    });

    test(
      'round trip activityStream → history → activityStream keeps session state',
      () async {
        await attention.dispose();
        const streamDest = AttentionFeedDestinationId.activityStream;
        const historyDest = AttentionFeedDestinationId.history;
        final roundTripAttention = AttentionCase(
          repository,
          accounts,
          realtimeCase,
          noopBlockCase(),
          feedSessions,
          Logger('attention-surfaces-round-trip'),
        );
        roundTripAttention.attachFeedSession(streamDest);
        addTearDown(roundTripAttention.dispose);

        final streamHead = Completer<AttentionFeed>();
        final signInSummary = Completer<AttentionSurfaceSummary>();
        repository.pendingFetches.add(streamHead);
        repository.pendingSurfaceSummaries.add(signInSummary);
        accounts.emit('account-a');
        await attentionCaseTestSettle();
        streamHead.complete(
          AttentionFeed(
            summary: const AttentionSummary(unreadTotal: 1),
            page: AttentionFeedPage(
              items: [attentionCaseTestReceipt(id: 'stream-item')],
              nextCursor: 'cursor-1',
            ),
          ),
        );
        signInSummary.complete(_surfaceSummary());
        await attentionCaseTestSettle();

        final unreadRefresh = Completer<AttentionFeed>();
        final searchRefresh = Completer<AttentionFeed>();
        repository.pendingFetches.addAll([unreadRefresh, searchRefresh]);
        roundTripAttention.setActiveView(streamDest, AttentionView.unread);
        await attentionCaseTestSettle();
        unreadRefresh.complete(attentionCaseTestFeed(items: [attentionCaseTestReceipt(id: 'stream-item')]));
        await attentionCaseTestSettle();
        roundTripAttention.setSearch(streamDest, 'needle');
        await attentionCaseTestSettle();
        searchRefresh.complete(
          AttentionFeed(
            summary: const AttentionSummary(unreadTotal: 1),
            page: AttentionFeedPage(
              items: [attentionCaseTestReceipt(id: 'stream-item')],
              nextCursor: 'cursor-1',
            ),
          ),
        );
        await attentionCaseTestSettle();

        roundTripAttention.detachFeedSession(streamDest);
        roundTripAttention.attachFeedSession(historyDest);
        final historyHead = Completer<AttentionFeed>();
        repository.pendingFetches.add(historyHead);
        realtimePort.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.notification,
            aggregateId: 'account-a',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await attentionCaseTestSettle();
        historyHead.complete(attentionCaseTestFeed(items: [attentionCaseTestReceipt(id: 'history-item')]));
        await attentionCaseTestSettle();
        expect(repository.fetches.last.surface, isNull);

        roundTripAttention.detachFeedSession(historyDest);
        roundTripAttention.attachFeedSession(streamDest);
        final session = roundTripAttention.feedSession(streamDest);
        expect(session.activeView, AttentionView.unread);
        expect(session.searchText, 'needle');
        expect(
          session.pages[AttentionView.unread]?.nextCursor,
          'cursor-1',
        );
      },
    );

    // CHANGES IN U15R-c (was: "mark-seen adjusts surface totals by receipt
    // surface"). It must not adjust them at all: both surface totals are
    // `active attention` server-side, and reading is not clearing (R2/D02).
    test('mark-seen leaves both surface totals where the server put them',
        () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      final initial = Completer<AttentionFeed>();
      final initialSummary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.add(initial);
      repository.pendingSurfaceSummaries.add(initialSummary);
      repository.pendingMarkSeen.add(Completer<int>());
      accounts.emit('account-a');
      await attentionCaseTestSettle();
      initial.complete(
        attentionCaseTestFeed(
          items: [
            attentionCaseTestReceipt(id: 'a').copyWith(surface: AttentionSurface.activity),
            attentionCaseTestReceipt(id: 'b').copyWith(surface: AttentionSurface.myWork),
          ],
        ),
      );
      initialSummary.complete(_surfaceSummary(activity: 2, myWork: 1));
      await attentionCaseTestSettle();

      final summaries = <AttentionSurfaceSummary>[];
      final sub = attention.surfaceSummary.listen(summaries.add);
      attention.markSeen(['a']);
      await attentionCaseTestSettle();
      expect(
        attention.surfaceSummarySnapshot,
        _surfaceSummary(activity: 2, myWork: 1),
      );
      await sub.cancel();
    });
  });
}
