import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import 'attention_case_test_support.dart';

/// U13c step 2 — the duplicate-page property U10c handed to the client.
///
/// The server cannot test this: there, a group whose sort key moves between
/// the head query and the tail query **vanishes**, because the two queries are
/// independent. Duplication is the client-side symptom of the same jump, and
/// it can only appear where pages are merged. Both halves are asserted here:
/// the moved group appears once, and nothing that either page carried is lost.
void main() {
  late _PagingRepository repository;
  late AttentionCaseTestAccounts accounts;
  late TestRealtimeSyncPort realtimePort;
  late AttentionCase attention;

  AttentionReceipt groupRow(String rowId, String beaconId) =>
      attentionCaseTestReceipt(id: rowId).copyWith(
        beaconId: beaconId,
        itemKind: AttentionItemKind.requestActivity,
      );

  List<AttentionReceipt> items() =>
      attention
          .feedSession(attentionCaseTestFeedDest)
          .pages[AttentionView.all]
          ?.items ??
      const [];

  setUp(() {
    repository = _PagingRepository();
    accounts = AttentionCaseTestAccounts();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    attention = AttentionCase(
      repository,
      accounts,
      realtime.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('AttentionPageMergeTest'),
      qaLatencyMeasurementEnabled: false,
    );
  });

  tearDown(() async {
    await attention.dispose();
    await accounts.dispose();
    await realtimePort.dispose();
  });

  test('a group whose sort key moves between pages merges once, losing nothing',
      () async {
    // Page one, held by the user.
    repository.pages.add(
      AttentionFeed(
        summary: const AttentionSummary(unreadTotal: 2),
        page: AttentionFeedPage(
          items: [groupRow('row-b1', 'B1'), groupRow('row-b2', 'B2')],
          nextCursor: 'page-two',
        ),
      ),
    );
    attention.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();

    expect(items().map((item) => item.beaconId), ['B1', 'B2']);

    // B1 gains an optional event, so its key moves past the cursor and the
    // tail query returns it again -- under a fresh row id, which is what
    // makes receipt-id dedupe insufficient.
    repository.pages.add(
      AttentionFeed(
        summary: const AttentionSummary(unreadTotal: 3),
        page: AttentionFeedPage(
          items: [groupRow('row-b1-again', 'B1'), groupRow('row-b3', 'B3')],
        ),
      ),
    );
    await attention.fetchNextPage(destinationId: attentionCaseTestFeedDest);
    await attentionCaseTestSettle();

    final beaconIds = items()
        .map((item) => item.beaconId)
        .toList(growable: false);
    expect(
      beaconIds.toSet().length,
      beaconIds.length,
      reason: 'one Request, one card -- the moved group is not duplicated',
    );
    expect(
      beaconIds.toSet(),
      {'B1', 'B2', 'B3'},
      reason: 'and the other direction: nothing either page carried vanished',
    );
  });

  test('two distinct Requests are never collapsed into one row', () async {
    repository.pages.add(
      AttentionFeed(
        summary: const AttentionSummary(unreadTotal: 1),
        page: AttentionFeedPage(
          items: [groupRow('row-b1', 'B1')],
          nextCursor: 'page-two',
        ),
      ),
    );
    attention.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();

    repository.pages.add(
      AttentionFeed(
        summary: const AttentionSummary(unreadTotal: 2),
        page: AttentionFeedPage(items: [groupRow('row-b4', 'B4')]),
      ),
    );
    await attention.fetchNextPage(destinationId: attentionCaseTestFeedDest);
    await attentionCaseTestSettle();

    expect(items().map((item) => item.beaconId), ['B1', 'B4']);
  });

  test('plain receipts on one Request keep their own rows', () async {
    // Ungrouped receipts share a beaconId legitimately -- they are separate
    // events, not two renderings of one card.
    repository.pages.add(
      AttentionFeed(
        summary: const AttentionSummary(unreadTotal: 1),
        page: AttentionFeedPage(
          items: [
            attentionCaseTestReceipt(id: 'r-1').copyWith(beaconId: 'B9'),
          ],
          nextCursor: 'page-two',
        ),
      ),
    );
    attention.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();

    repository.pages.add(
      AttentionFeed(
        summary: const AttentionSummary(unreadTotal: 2),
        page: AttentionFeedPage(
          items: [
            attentionCaseTestReceipt(id: 'r-2').copyWith(beaconId: 'B9'),
          ],
        ),
      ),
    );
    await attention.fetchNextPage(destinationId: attentionCaseTestFeedDest);
    await attentionCaseTestSettle();

    expect(items().map((item) => item.id), ['r-1', 'r-2']);
  });
}

final class _PagingRepository extends AttentionRepositoryFake {
  final List<AttentionFeed> pages = [];

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    if (pages.isEmpty) {
      return const AttentionFeed(
        summary: AttentionSummary(),
        page: AttentionFeedPage(),
      );
    }
    return pages.removeAt(0);
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
}
