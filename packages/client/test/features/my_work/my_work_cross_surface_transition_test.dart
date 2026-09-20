import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import '../block/support/controllable_block_case.dart';
import '../../domain/attention/attention_case_test_support.dart';
import '../../support/test_realtime_sync.dart';
import 'my_work_test_support.dart';

/// R5 — cross-surface atomicity, observed on **both** surfaces.
///
/// The U15 test that claimed "never on two surfaces at once" watched My
/// Desk's archived and non-archived lists and never looked at For You, so it
/// could not have seen the failure it was named for. This one mounts both
/// projections off one `AttentionCase`, holds the server's answers, and
/// samples every frame in between.
void main() {
  for (final kind in const [
    RealtimeEntityKind.beacon,
    RealtimeEntityKind.helpOffer,
    RealtimeEntityKind.inboxItem,
    // CHANGES IN U15R-d: `notification` joins the loop. R5's brief named the
    // other three, so U15R-c routed those through the coordinated transition
    // and recorded this one as still refreshing the counters and the pages in
    // two uncoordinated steps. Same defect class, same route.
    RealtimeEntityKind.notification,
  ]) {
    test(
      'a ${kind.name} transition never shows the Request on both surfaces',
      () async {
        final realtime = buildTestRealtimeSync();
        final attentionRepo = AttentionCaseTestRepository();
        final accounts = AttentionCaseTestAccounts();
        final attention = AttentionCase(
          attentionRepo,
          accounts,
          realtime.case_,
          noopBlockCase(),
          FeedSessionRegistry(),
          Logger('cross-surface-$kind'),
          qaLatencyMeasurementEnabled: false,
        );
        addTearDown(attention.dispose);
        addTearDown(accounts.dispose);
        addTearDown(realtime.port.dispose);

        // For You is mounted and holds the Request.
        attention.attachFeedSession(
          AttentionFeedDestinationId.activityStream,
        );
        final head = Completer<AttentionFeed>();
        final summary = Completer<AttentionSurfaceSummary>();
        attentionRepo.pendingFetches.add(head);
        attentionRepo.pendingSurfaceSummaries.add(summary);
        accounts.emit('account-a');
        await attentionCaseTestSettle();
        head.complete(
          AttentionFeed(
            summary: const AttentionSummary(unreadTotal: 1),
            page: AttentionFeedPage(items: [_onForYou()]),
          ),
        );
        summary.complete(
          const AttentionSurfaceSummary(forYouDot: true),
        );
        await attentionCaseTestSettle();

        // My Desk is mounted off the same case and does not hold it yet.
        final deskRepo = FakeMyWorkRepository()
          ..initResult = (
            authoredNonArchived: const <Beacon>[],
            helpOfferedNonArchived: const [],
            obligationBeacons: const [],
            archivedCountHint: 0,
          );
        final desk = MyWorkCubit(
          userId: 'user-1',
          myWorkCase: buildTestMyWorkCase(
            repo: deskRepo,
            attentionCase: attention,
            realtimeSyncCase: realtime.case_,
          ),
        );
        addTearDown(desk.close);
        await desk.stream.firstWhere((s) => s.attentionLoaded);

        // Every frame of the transition, sampled on both surfaces at once.
        final frames = <({bool forYou, bool myDesk})>[];
        void sample() => frames.add((
          forYou: attention
              .feedSession(AttentionFeedDestinationId.activityStream)
              .pages
              .values
              .expand((page) => page.items)
              .any((item) => item.beaconId == 'moved'),
          myDesk: [
            ...desk.state.nonArchivedCards,
            ...desk.state.archivedCards,
          ].any((card) => card.beaconId == 'moved'),
        ));

        final deskSub = desk.stream.listen((_) => sample());
        addTearDown(deskSub.cancel);
        sample();

        // The Request changed hands. Both servers' answers are held.
        deskRepo.initResult = (
          authoredNonArchived: [Beacon.empty.copyWith(id: 'moved')],
          helpOfferedNonArchived: const [],
          obligationBeacons: const [],
          archivedCountHint: 0,
        );
        final movedHead = Completer<AttentionFeed>();
        final movedSummary = Completer<AttentionSurfaceSummary>();
        attentionRepo.pendingFetches.add(movedHead);
        attentionRepo.pendingSurfaceSummaries.add(movedSummary);

        realtime.port.emitChange(
          RealtimeEntityChange(
            kind: kind,
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
            aggregateId: 'moved',
            // A notification hint names its Request on `childId`; the other
            // three name it on `aggregateId`. Both are set so one loop can
            // drive all four.
            childId: 'moved',
          ),
        );

        // Well past My Desk's invalidation debounce, with For You's answer
        // still held. My Desk must not have jumped ahead of the commit.
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          sample();
        }

        movedSummary.complete(
          const AttentionSurfaceSummary(myDeskDot: true),
        );
        movedHead.complete(
          const AttentionFeed(
            summary: AttentionSummary(),
            page: AttentionFeedPage(),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          sample();
        }

        expect(
          frames.where((f) => f.forYou && f.myDesk),
          isEmpty,
          reason: 'on two surfaces at once during $kind: $frames',
        );
        expect(
          frames.first,
          (forYou: true, myDesk: false),
          reason: 'it started on For You',
        );
        expect(
          frames.last,
          (forYou: false, myDesk: true),
          reason: 'it finished on My Desk',
        );
      },
    );
  }
}

AttentionReceipt _onForYou() => AttentionReceipt(
  id: 'r-moved',
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: 'Moved',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  beaconId: 'moved',
  surface: AttentionSurface.activity,
);
