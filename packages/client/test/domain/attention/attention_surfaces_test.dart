import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';
import 'attention_case_test_support.dart';

/// A distinguishable §6 surface summary.
///
/// CHANGES IN U18c: every test below uses a summary only to tell one
/// published value from another, and the three legacy totals they varied are
/// retired. §6 leaves one integer on this object (`my desk.count`) and three
/// booleans, so `deskCount` is the discriminator and the dots ride along —
/// which also means a published summary that differed only in a dot still
/// differs here.
AttentionSurfaceSummary _surfaceSummary({
  int deskCount = 0,
  bool myDeskDot = false,
  bool forYouDot = false,
}) => AttentionSurfaceSummary(
  myDeskCount: deskCount,
  myDeskDot: myDeskDot,
  forYouDot: forYouDot,
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
      summary.complete(_surfaceSummary(deskCount: 1, forYouDot: true));
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
      summary.complete(_surfaceSummary(deskCount: 2, forYouDot: true));
      head.complete(attentionCaseTestFeed());
      await attentionCaseTestSettle();
      expect(surfaceSummaries, contains(_surfaceSummary(deskCount: 2, forYouDot: true)));
    });

    test('refreshes on notification events', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      await signInAndCompleteHead();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(summary);
      // CHANGES IN U15R-d: the same U15R-c change, on the fourth kind. A
      // notification hint is a transition too — clear state and outcome
      // generation move a Request between surfaces — so the page and the
      // totals are fetched together and committed once (R5, D14), and this
      // path reads a page.
      final page = Completer<AttentionFeed>();
      repository.pendingFetches.add(page);
      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.notification,
          aggregateId: 'account-a',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(deskCount: 3, myDeskDot: true));
      page.complete(attentionCaseTestFeed());
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last, _surfaceSummary(deskCount: 3, myDeskDot: true));
    });

    test('refreshes on helpOffer events', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      await signInAndCompleteHead();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(summary);
      // CHANGES IN U15R-c: the page and the totals are now fetched together
      // and committed once, so this path reads a page too (R5).
      final page = Completer<AttentionFeed>();
      repository.pendingFetches.add(page);
      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.helpOffer,
          aggregateId: 'beacon-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(deskCount: 4, forYouDot: true));
      page.complete(attentionCaseTestFeed());
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last, _surfaceSummary(deskCount: 4, forYouDot: true));
    });

    test('refreshes on inboxItem events', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      await signInAndCompleteHead();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(summary);
      // CHANGES IN U15R-c: the page and the totals are now fetched together
      // and committed once, so this path reads a page too (R5).
      final page = Completer<AttentionFeed>();
      repository.pendingFetches.add(page);
      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.inboxItem,
          aggregateId: 'beacon-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(deskCount: 5, forYouDot: true));
      page.complete(attentionCaseTestFeed());
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last, _surfaceSummary(deskCount: 5, forYouDot: true));
    });

    test('refreshes on catch-up', () async {
      attention.attachFeedSession(AttentionFeedDestinationId.activityStream);
      await signInAndCompleteHead();
      final summary = Completer<AttentionSurfaceSummary>();
      repository.pendingSurfaceSummaries.add(summary);
      realtimePort.emitCatchUp();
      await attentionCaseTestSettle();
      summary.complete(_surfaceSummary(deskCount: 2));
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last, _surfaceSummary(deskCount: 2));
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
      afterBlock.complete(_surfaceSummary(deskCount: 7, forYouDot: true));
      await attentionCaseTestSettle();
      expect(blockSummaries.last, _surfaceSummary(deskCount: 7, forYouDot: true));
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
      initialSummary.complete(_surfaceSummary(deskCount: 1, forYouDot: true));
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
      // CHANGES IN U15R-d: a notification hint now refetches the mounted page
      // alongside the totals (R5), so the transition needs a second head.
      final afterHint = Completer<AttentionFeed>();
      repository.pendingFetches.addAll([head, afterHint]);
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

      stale.complete(_surfaceSummary(deskCount: 99, forYouDot: true));
      fresh.complete(_surfaceSummary(deskCount: 1, forYouDot: true));
      afterHint.complete(attentionCaseTestFeed());
      await attentionCaseTestSettle();
      expect(surfaceSummaries.last.myDeskCount, 1);
    });

    // CHANGES IN U15R-c (was: "helpOffer refreshes activity stream head
    // only"). A help-offer flips responsibility, so it is a transition, and
    // R5 puts every mounted surface and the totals in one commit rather than
    // refreshing the Activity page on its own. What survives unchanged is
    // that the Activity page is still fetched *as* the activity surface.
    test('helpOffer commits every mounted surface in one move', () async {
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
      final transitionStreamHead = Completer<AttentionFeed>();
      final transitionHistoryHead = Completer<AttentionFeed>();
      final transitionSummary = Completer<AttentionSurfaceSummary>();
      repository.pendingFetches.addAll([
        transitionStreamHead,
        transitionHistoryHead,
      ]);
      repository.pendingSurfaceSummaries.add(transitionSummary);

      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.helpOffer,
          aggregateId: 'beacon-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      expect(repository.fetchCalls, fetchCallsBefore + 2);
      final refreshed = repository.fetches.sublist(fetchCallsBefore);
      expect(
        refreshed.map((f) => f.surface),
        containsAll(<AttentionSurface?>[AttentionSurface.activity, null]),
        reason: 'the stream reads its own surface; History reads unscoped',
      );
      expect(refreshed.every((f) => f.view == AttentionView.all), isTrue);
      transitionStreamHead.complete(attentionCaseTestFeed());
      transitionHistoryHead.complete(attentionCaseTestFeed());
      transitionSummary.complete(_surfaceSummary());
      await attentionCaseTestSettle();
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
      initialSummary.complete(_surfaceSummary(deskCount: 2, myDeskDot: true, forYouDot: true));
      await attentionCaseTestSettle();

      final summaries = <AttentionSurfaceSummary>[];
      final sub = attention.surfaceSummary.listen(summaries.add);
      attention.markSeen(['a']);
      await attentionCaseTestSettle();
      expect(
        attention.surfaceSummarySnapshot,
        _surfaceSummary(deskCount: 2, myDeskDot: true, forYouDot: true),
      );
      await sub.cancel();
    });
  });
}
