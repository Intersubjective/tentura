import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';

import '../../domain/attention/attention_case_test_support.dart';
import '../../support/attention_case_factory.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import 'support/noop_invite_setup_port.dart';

void main() {
  test(
    'History keeps unread totals from a cross-surface refresh whose page predates the search',
    () async {
      const account = 'account-a';
      const request = 'request-a';
      final accounts = AttentionCaseTestAccounts();
      final repository = AttentionCaseTestRepository();
      final realtime = buildTestRealtimeSync();
      final attention = buildAttentionCase(
        repository: repository,
        accounts: accounts,
        realtimeSyncCase: realtime.case_,
      );
      addTearDown(accounts.dispose);
      addTearDown(realtime.port.dispose);
      addTearDown(attention.dispose);

      accounts.emit(account);
      await attentionCaseTestSettle();
      final initial = Completer<AttentionFeed>();
      repository.pendingFetches.add(initial);
      final history = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.history,
        attention: attention,
        setup: NoopInviteAcceptedSetupPort(),
        actorProfiles: buildNoopAttentionActorProfiles(),
        realtime: realtime.case_,
        logger: Logger('history-reconnect-summary-test'),
      );
      addTearDown(history.close);
      initial.complete(_page('unfiltered'));
      await attentionCaseTestSettle();
      expect(history.state.items.map((row) => row.id), ['unfiltered']);
      expect(history.state.canReadAll, isFalse);

      final crossSurfaceSummary = Completer<AttentionSurfaceSummary>();
      final preSearchPage = Completer<AttentionFeed>();
      repository.pendingSurfaceSummaries.add(crossSurfaceSummary);
      repository.pendingFetches.add(preSearchPage);
      final refreshSettled = attention.requestInvalidations
          .firstWhere((id) => id == request)
          .timeout(const Duration(seconds: 5));
      realtime.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.notification,
          aggregateId: account,
          childId: request,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await attentionCaseTestSettle();
      expect(repository.pendingSurfaceSummaries, isEmpty);
      expect(repository.pendingFetches, isEmpty);
      expect(repository.fetches.last.search, isNull);

      final searchPage = Completer<AttentionFeed>();
      repository.pendingFetches.add(searchPage);
      history.setSearch('a');
      expect(repository.fetches.last.search, 'a');

      final catchUpSummary = Completer<AttentionSurfaceSummary>();
      final catchUpPage = Completer<AttentionFeed>();
      repository.pendingSurfaceSummaries.add(catchUpSummary);
      repository.pendingFetches.add(catchUpPage);
      realtime.port.emitCatchUp();
      await attentionCaseTestSettle();
      expect(repository.pendingSurfaceSummaries, isEmpty);

      const unread = AttentionSurfaceSummary(
        historySummary: AttentionSummary(unreadTotal: 2),
        forYouReceiptSweepEligible: true,
      );
      crossSurfaceSummary.complete(unread);
      preSearchPage.complete(_page('stale-unfiltered'));
      await refreshSettled;
      expect(history.state.items, isEmpty);
      searchPage.complete(_page('matched'));
      await attentionCaseTestSettle();

      expect(history.state.refreshError, isNull);
      expect(history.state.searchText, 'a');
      expect(repository.fetches.last.search, 'a');
      expect(history.state.items.map((row) => row.id), ['matched']);
      final afterCrossSurfaceRefresh = (
        attention.surfaceSummarySnapshot.forYouReceiptSweepEligible,
        history.state.summary.unreadTotal,
        history.state.sweepEligible,
        history.state.canReadAll,
      );

      // The later reconnect reads remain pending until the stale-page
      // refresh has finished and its effect on History has been observed.
      catchUpSummary.complete(unread);
      catchUpPage.complete(_page('matched'));
      await attentionCaseTestSettle();
      expect(afterCrossSurfaceRefresh, (true, 2, true, true));
    },
  );
}

AttentionFeed _page(String id) => attentionCaseTestFeed(
  unread: 0,
  items: [attentionCaseTestSeenReceipt(id: id)],
);
